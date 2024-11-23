library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_logic, work, nsl_data;
use work.axi4_mm.all;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4_mm_ram is
  generic(
    config_c : config_t;
    byte_size_l2_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in master_t;
    axi_o : out slave_t
    );
end entity;

architecture beh of axi4_mm_ram is

  subtype ram_addr_t is unsigned(byte_size_l2_c-config_c.data_bus_width_l2-1 downto 0);
  subtype ram_strobe_t is std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
  subtype ram_data_t is std_ulogic_vector(0 to 8*ram_strobe_t'length-1);

  signal write_enable_s, read_enable_s: std_ulogic;
  signal write_address_s, read_address_s: ram_addr_t;
  signal write_strobe_s: ram_strobe_t;
  signal write_data_s, read_data_s: ram_data_t;

begin

  write_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_WRITING,
      ST_RESP
      );

    type regs_t is
    record
      state: state_t;
      transaction: transaction_t;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition: process(r, axi_i) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.transaction.valid <= '0';

        when ST_IDLE =>
          if is_valid(config_c, axi_i.aw) then
            rin.transaction <= transaction(config_c, axi_i.aw);
            rin.state <= ST_WRITING;
          end if;

        when ST_WRITING =>
          if is_valid(config_c, axi_i.w) then
            rin.transaction <= step(config_c, r.transaction);
            if is_last(config_c, r.transaction) then
              rin.state <= ST_RESP;
            end if;
          end if;

        when ST_RESP =>
          if is_ready(config_c, axi_i.b) then
            rin.state <= ST_IDLE;
          end if;
      end case;
    end process;

    write_address_s <= resize(address(config_c, r.transaction, config_c.data_bus_width_l2), write_address_s'length);
    write_enable_s <= to_logic(r.state = ST_WRITING and is_valid(config_c, axi_i.w));
    write_strobe_s <= strb(config_c, axi_i.w);
    write_data_s <= std_ulogic_vector(value(config_c, axi_i.w, ENDIAN_BIG));

    axi_o.aw.ready <= to_logic(r.state = ST_IDLE);
    axi_o.w.ready <= to_logic(r.state = ST_WRITING);
    axi_o.b <= write_response(config_c,
                              id => id(config_c, r.transaction),
                              user => user(config_c, r.transaction),
                              valid => r.state = ST_RESP,
                              resp => RESP_OKAY);
  end block;
  
  read_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_READ,
      ST_WAIT
      );

    type rsp_t is (
      RSP_IDLE,
      RSP_SEND
      );

    type ram_data_vector is array(integer range <>) of ram_data_t;
    constant ram_latency_c : natural := 2;
    constant fifo_depth_c : natural := ram_latency_c + 2;

    type regs_t is
    record
      state: state_t;
      rsp: rsp_t;
      transaction: transaction_t;
      rdata_valid: std_ulogic_vector(0 to ram_latency_c-1);
      fifo_fillness: integer range 0 to fifo_depth_c;
      fifo: ram_data_vector(integer range 0 to fifo_depth_c);
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
        r.rsp <= RSP_IDLE;
        r.fifo_fillness <= 0;
        r.rdata_valid <= (others => '0');
      end if;
    end process;

    transition: process(r, axi_i, read_data_s) is
      variable fifo_put, fifo_pop : boolean;
    begin
      rin <= r;

      fifo_put := false;
      fifo_pop := false;

      rin.rdata_valid <= r.rdata_valid(1 to r.rdata_valid'right) & "0";
      fifo_put := r.rdata_valid(0) = '1';

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if is_valid(config_c, axi_i.ar) then
            rin.transaction <= transaction(config_c, axi_i.ar);
            rin.state <= ST_READ;
          end if;

        when ST_READ =>
          if r.fifo_fillness < fifo_depth_c - ram_latency_c then
            rin.rdata_valid(rin.rdata_valid'right) <= '1';
            rin.transaction <= step(config_c, r.transaction);
            if is_last(config_c, r.transaction) then
              rin.state <= ST_WAIT;
            end if;
          end if;

        when ST_WAIT =>
          if r.rdata_valid = (r.rdata_valid'range => '0')
            and (r.fifo_fillness = 0
                 or (r.fifo_fillness = 1 and is_ready(config_c, axi_i.r))) then
            rin.state <= ST_IDLE;
          end if;
      end case;

      case r.rsp is
        when RSP_IDLE =>
          if r.state = ST_READ then
            rin.rsp <= RSP_SEND;
          end if;

        when RSP_SEND =>
          if r.fifo_fillness > 0 and is_ready(config_c, axi_i.r) then
            fifo_pop := true;
            if r.rdata_valid = (r.rdata_valid'range => '0') and r.fifo_fillness = 1 and r.state = ST_WAIT then
              rin.rsp <= RSP_IDLE;
            end if;
          end if;
      end case;

      if fifo_pop then
        rin.fifo(0 to r.fifo'right-1) <= r.fifo(1 to r.fifo'right);
        if fifo_put then
          rin.fifo(r.fifo_fillness-1) <= read_data_s;
        else
          rin.fifo_fillness <= r.fifo_fillness - 1;
        end if;
      elsif fifo_put then
        rin.fifo(r.fifo_fillness) <= read_data_s;
        rin.fifo_fillness <= r.fifo_fillness + 1;
      end if;
    end process;

    moore: process(r) is
    begin
      read_address_s <= resize(address(config_c, r.transaction, config_c.data_bus_width_l2), read_address_s'length);
      read_enable_s <= to_logic(r.state /= ST_IDLE and r.state /= ST_RESET);
      axi_o.ar <= accept(config_c, r.state = ST_IDLE);

      case r.rsp is
        when RSP_IDLE =>
          axi_o.r <= read_data_defaults(config_c);
          
        when RSP_SEND =>
          axi_o.r <= read_data(config_c,
                               id => id(config_c, r.transaction),
                               value => unsigned(r.fifo(0)),
                               endian => ENDIAN_BIG,
                               resp => RESP_OKAY,
                               user => user(config_c, r.transaction),
                               last => r.state = ST_WAIT and r.fifo_fillness = 1 and r.rdata_valid = (r.rdata_valid'range => '0'),
                               valid => r.fifo_fillness /= 0);
      end case;            
    end process;
  end block;
  
  fifo: nsl_memory.ram.ram_2p_homogeneous
    generic map(
      addr_size_c => ram_addr_t'length,
      word_size_c => 8,
      data_word_count_c => ram_strobe_t'length,
      registered_output_c => true,
      b_can_write_c => false
      )
    port map(
      a_clock_i => clock_i,

      a_enable_i => write_enable_s,
      a_address_i => write_address_s,
      a_data_i => write_data_s,
      a_write_en_i => write_strobe_s,

      b_clock_i => clock_i,

      b_enable_i => read_enable_s,
      b_address_i => read_address_s,
      b_data_o => read_data_s
      );

end architecture;
