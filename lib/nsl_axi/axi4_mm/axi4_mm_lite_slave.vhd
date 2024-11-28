library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_data;
use nsl_axi.axi4_mm.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

entity axi4_mm_lite_slave is
  generic (
    config_c: config_t
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic := '1';

    axi_i: in master_t;
    axi_o: out slave_t;

    address_o : out unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);

    w_data_o : out byte_string(0 to 2**config_c.data_bus_width_l2-1);
    w_mask_o : out std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
    w_ready_i : in std_ulogic := '1';
    w_error_i : in std_ulogic := '0';
    w_valid_o : out std_ulogic;

    r_data_i : in byte_string(0 to 2**config_c.data_bus_width_l2-1);
    r_ready_o : out std_ulogic;
    r_valid_i : in std_ulogic := '1'
    );
begin
  
  assert is_lite(config_c)
    report "configuration is not an AXI4-Lite subset"
    severity failure;

end entity;

architecture rtl of axi4_mm_lite_slave is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WCMD,
    ST_WEXEC,
    ST_WRSP,
    ST_WERR,
    ST_RCMD,
    ST_REXEC,
    ST_RRSP
    );

  type regs_t is
  record
    addr : unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);
    data : byte_string(0 to 2**config_c.data_bus_width_l2-1);
    mask : std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
    state: state_t;
    user : std_ulogic_vector(config_c.user_width-1 downto 0);
  end record;

  signal r, rin: regs_t;

begin
  
  regs: process(clock_i, reset_n_i)
  begin
    -- Double assertion here, most vendor VHDL implementations do not handle
    -- assertions in entity
    assert is_lite(config_c)
      report "configuration is not an AXI4-Lite subset"
      severity failure;

    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, axi_i, r_data_i, r_valid_i, w_ready_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if is_valid(config_c, axi_i.aw) and is_valid(config_c, axi_i.w) then
          rin.state <= ST_WCMD;
        elsif is_valid(config_c, axi_i.ar) then
          rin.state <= ST_RCMD;
        end if;

      when ST_WCMD =>
        if is_valid(config_c, axi_i.aw) and is_valid(config_c, axi_i.w) then
          rin.state <= ST_WEXEC;
          rin.addr <= address(config_c, axi_i.aw, lsb => config_c.data_bus_width_l2);
          rin.user <= user(config_c, axi_i.aw);
          rin.data <= bytes(config_c, axi_i.w);
          rin.mask <= strb(config_c, axi_i.w);
        end if;

      when ST_WEXEC =>
        if w_ready_i = '1' then
          if w_error_i = '1' then
            rin.state <= ST_WERR;
          else
            rin.state <= ST_WRSP;
          end if;
        end if;

      when ST_WRSP | ST_WERR =>
        if is_ready(config_c, axi_i.b) then
          rin.state <= ST_IDLE;
        end if;

      when ST_RCMD =>
        if is_valid(config_c, axi_i.ar) then
          rin.addr <= address(config_c, axi_i.ar, lsb => config_c.data_bus_width_l2);
          rin.state <= ST_REXEC;
          rin.user <= user(config_c, axi_i.ar);
        end if;

      when ST_REXEC =>
        if r_valid_i = '1' then
          rin.state <= ST_RRSP;
          rin.data <= r_data_i;
        end if;

      when ST_RRSP =>
        if is_ready(config_c, axi_i.r) then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    address_o <= r.addr;
    w_data_o <= (others => dontcare_byte_c);
    w_mask_o <= (others => '-');
    w_valid_o <= '0';
    r_ready_o <= '0';

    axi_o.ar <= handshake_defaults(config_c);
    axi_o.aw <= handshake_defaults(config_c);
    axi_o.w <= handshake_defaults(config_c);
    axi_o.r <= read_data_defaults(config_c);
    axi_o.b <= write_response_defaults(config_c);

    case r.state is
      when ST_WCMD =>
        axi_o.aw <= accept(config_c, true);
        axi_o.w <= accept(config_c, true);

      when ST_WEXEC =>
        w_valid_o <= '1';
        w_data_o <= r.data;
        w_mask_o <= r.mask;

      when ST_WRSP =>
        axi_o.b <= write_response(config_c, valid => true, user => r.user);

      when ST_WERR =>
        axi_o.b <= write_response(config_c, valid => true, resp => RESP_SLVERR, user => r.user);

      when ST_RCMD =>
        axi_o.ar <= accept(config_c, true);

      when ST_REXEC =>
        r_ready_o <= '1';

      when ST_RRSP =>
        axi_o.r <= read_data(config_c, valid => true, user => r.user, bytes => r.data);

      when others =>
        null;
    end case;
  end process;

end architecture;
