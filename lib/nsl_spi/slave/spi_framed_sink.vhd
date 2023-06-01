library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_data, nsl_logic, nsl_bnoc;
use nsl_data.bytestream.all;
use nsl_bnoc.framed.all;
use nsl_logic.bool.all;

entity spi_framed_sink is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    spi_i : in nsl_spi.spi.spi_slave_i;
    spi_o : out nsl_spi.spi.spi_slave_o;
    
    cpol_i : in std_ulogic := '0';
    cpha_i : in std_ulogic := '0';

    framed_o  : out nsl_bnoc.framed.framed_req;
    framed_i  : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of spi_framed_sink is

  type st_t is (
    ST_WAIT_IDLE,
    ST_IDLE,
    ST_PADDING,
    ST_DATA,
    ST_FLUSH
    );

  constant fifo_depth_c : integer := 3;
  
  type regs_t is
  record
    state : st_t;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    status: std_ulogic_vector(3 downto 0);
    last_status: std_ulogic_vector(3 downto 0);
  end record;

  signal r, rin: regs_t;
  signal to_spi_ready_s, from_spi_valid_s, active_s : std_ulogic;
  signal to_spi_data_s, from_spi_data_s : byte;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_WAIT_IDLE;
      r.fifo_fillness <= 0;
      r.status <= (others => '0');
      r.last_status <= (others => '0');
    end if;
  end process;
  
  transition: process(r, to_spi_ready_s, from_spi_valid_s, active_s, to_spi_data_s, from_spi_data_s,
                      framed_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    rin.status(0) <= to_logic(r.fifo_fillness /= fifo_depth_c);
    
    case r.state is
      when ST_WAIT_IDLE =>
        if active_s = '0' then
          rin.status <= (others => '0');
          rin.state <= ST_IDLE;
        end if;

      when ST_IDLE =>
        if active_s = '1' then
          rin.state <= ST_PADDING;
        end if;

      when ST_PADDING =>
        if active_s = '0' then
          rin.last_status <= r.status;
          rin.state <= ST_WAIT_IDLE;
        elsif from_spi_valid_s = '1' then
          rin.state <= ST_DATA;
        end if;

      when ST_DATA =>
        if active_s = '0' then
          rin.last_status <= r.status;
          if r.fifo_fillness = 0 then
            rin.state <= ST_WAIT_IDLE;
          else
            -- These will appear on HS byte if slave is selected again before
            -- write buffer is flushed.
            rin.status(0) <= '0';
            rin.status(1) <= '0';
            rin.status(2) <= '1';
            rin.state <= ST_FLUSH;
          end if;
        elsif from_spi_valid_s = '1' then
          if r.fifo_fillness /= fifo_depth_c then
            fifo_push := true;
          else
            rin.status(1) <= '1';
          end if;
        end if;

        fifo_pop := framed_i.ready = '1' and r.fifo_fillness > 1;
        
      when ST_FLUSH =>
        fifo_pop := framed_i.ready = '1' and r.fifo_fillness > 0;

        if r.fifo_fillness = 0 or (r.fifo_fillness = 1 and framed_i.ready = '1') then
          rin.state <= ST_WAIT_IDLE;
        end if;
    end case;
    
    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= from_spi_data_s;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= from_spi_data_s;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    to_spi_data_s <= r.last_status & r.status;

    case r.state is
      when ST_IDLE | ST_PADDING | ST_WAIT_IDLE =>
        framed_o <= framed_req_idle_c;

      when ST_DATA =>
        framed_o <= framed_flit(data => r.fifo(0),
                                valid => r.fifo_fillness > 1,
                                last => false);

      when ST_FLUSH =>
        framed_o <= framed_flit(data => r.fifo(0),
                                valid => r.fifo_fillness > 0,
                                last => r.fifo_fillness = 1);
    end case;
  end process;
  
  shreg: nsl_spi.shift_register.slave_shift_register_oversampled
    generic map(
      width_c => 8,
      msb_first_c => true,
      cs_n_active_c => '0'
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      spi_i => spi_i,
      spi_o => spi_o,
      cpol_i => cpol_i,
      cpha_i => cpha_i,

      active_o => active_s,
      tx_data_i => to_spi_data_s,
      tx_ready_o => to_spi_ready_s,
      rx_data_o => from_spi_data_s,
      rx_valid_o => from_spi_valid_s
      );

end architecture rtl;
