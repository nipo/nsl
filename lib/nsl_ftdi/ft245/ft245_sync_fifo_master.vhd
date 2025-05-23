library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi, nsl_memory, nsl_clocking;

entity ft245_sync_fifo_master is
  generic (
    burst_length: integer := 64
    );
  port (
    clock_o    : out std_ulogic;
    reset_n_i : in std_ulogic;

    bus_o : out nsl_ftdi.ft245.ft245_sync_fifo_master_o;
    bus_i : in nsl_ftdi.ft245.ft245_sync_fifo_master_i;

    in_ready_i : in  std_ulogic;
    in_valid_o : out std_ulogic;
    in_data_o  : out std_ulogic_vector(7 downto 0);

    out_ready_o : out std_ulogic;
    out_valid_i : in  std_ulogic;
    out_data_i  : in  std_ulogic_vector(7 downto 0)
    );
end ft245_sync_fifo_master;

architecture arch of ft245_sync_fifo_master is

  type state_type is (
    ST_RESET,
    ST_INBOUND,
    ST_OUTBOUND_PRE,
    ST_OUTBOUND,
    ST_INBOUND_PRE
  );

  type regs_t is record
    state: state_type;
    counter: integer range 0 to burst_length-1;
  end record;

  signal r, rin: regs_t;

  signal int_in_ready_i : std_ulogic;
  signal int_in_valid_o : std_ulogic;
  signal int_in_data_o  : std_ulogic_vector(7 downto 0);
  signal int_out_ready_o : std_ulogic;
  signal int_out_valid_i : std_ulogic;
  signal int_out_data_i  : std_ulogic_vector(7 downto 0);
  signal clock : std_ulogic;
  signal reset_sync : std_ulogic;

begin

  clock_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => bus_i.clk,
      clock_o => clock
      );

  reset_ryncer: nsl_clocking.async.async_edge
    port map(
      clock_i => clock,
      data_i => reset_n_i,
      data_o => reset_sync
      );
  
  regs: process (clock, reset_sync)
  begin
    if rising_edge(clock) then
      r <= rin;
    end if;
    if reset_sync = '0' then
      r.state <= ST_RESET;
    end if;
  end process;
  
  transition: process (r, int_out_valid_i, int_in_ready_i, bus_i)
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_INBOUND_PRE;
        
      when ST_INBOUND =>
        if int_in_ready_i = '1' and bus_i.rxf = '1' then
          if r.counter = 0 then
            if int_out_valid_i = '1' and bus_i.txe = '1' then
              rin.state <= ST_OUTBOUND_PRE;
            end if;
          else
            rin.counter <= r.counter - 1;
          end if;
        elsif int_out_valid_i = '1' and bus_i.txe = '1' then
          rin.state <= ST_OUTBOUND_PRE;
        end if;
        
      when ST_OUTBOUND =>
        if int_out_valid_i = '1' and bus_i.txe = '1' then
          if r.counter = 0 then
            if int_in_ready_i = '1' and bus_i.rxf = '1' then
              rin.state <= ST_INBOUND_PRE;
            end if;
          else
            rin.counter <= r.counter - 1;
          end if;
        elsif int_in_ready_i = '1' and bus_i.rxf = '1' then
          rin.state <= ST_INBOUND_PRE;
        end if;
        
      when ST_INBOUND_PRE =>
        rin.state <= ST_INBOUND;
        rin.counter <= burst_length - 1;
        
      when ST_OUTBOUND_PRE =>
        rin.state <= ST_OUTBOUND;
        rin.counter <= burst_length - 1;
    end case;
  end process;

  clock_o <= clock;
  int_in_data_o <= bus_i.data;
  bus_o.data <= int_out_data_i;

  handshaking: process(r, int_in_ready_i, int_out_valid_i, bus_i)
  begin
    int_out_ready_o <= '0';
    int_in_valid_o <= '0';
    bus_o.rd <= '0';
    bus_o.wr <= '0';

    case r.state is
      when ST_INBOUND =>
        bus_o.rd <= int_in_ready_i and bus_i.rxf;
        int_in_valid_o <= bus_i.rxf;

      when ST_OUTBOUND =>
        int_out_ready_o <= bus_i.txe;
        bus_o.wr <= int_out_valid_i and bus_i.txe;

      when others =>
        null;

    end case;
  end process;
  
  moore: process(r)
  begin
    bus_o.oe <= '0';
    bus_o.data_oe <= '0';

    case r.state is
      when ST_INBOUND | ST_INBOUND_PRE =>
        bus_o.oe <= '1';

      when ST_OUTBOUND =>
        bus_o.data_oe <= '1';

      when others =>
        null;

    end case;
  end process;
  
  slice_out: nsl_memory.fifo.fifo_register_slice
    generic map(
      data_width_c => 8
      )
    port map(
      reset_n_i => reset_sync,
      clock_i => clock,

      in_data_i => out_data_i,
      in_valid_i => out_valid_i,
      in_ready_o => out_ready_o,

      out_data_o => int_out_data_i,
      out_valid_o => int_out_valid_i,
      out_ready_i => int_out_ready_o
      );

  slice_in: nsl_memory.fifo.fifo_register_slice
    generic map(
      data_width_c => 8
      )
    port map(
      reset_n_i => reset_sync,
      clock_i => clock,

      in_data_i => int_in_data_o,
      in_valid_i => int_in_valid_o,
      in_ready_o => int_in_ready_i,

      out_data_o => in_data_o,
      out_valid_o => in_valid_o,
      out_ready_i => in_ready_i
      );

end arch;
