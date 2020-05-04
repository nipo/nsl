library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi;

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

begin

  regs: process (bus_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(bus_i.clk) then
      r <= rin;
    end if;
  end process;
  
  transition: process (r, out_valid_i, in_ready_i, bus_i)
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_INBOUND_PRE;
        
      when ST_INBOUND =>
        if in_ready_i = '1' and bus_i.rxf = '1' then
          if r.counter = 0 then
            if out_valid_i = '1' and bus_i.txe = '1' then
              rin.state <= ST_OUTBOUND_PRE;
            end if;
          else
            rin.counter <= r.counter - 1;
          end if;
        elsif out_valid_i = '1' and bus_i.txe = '1' then
          rin.state <= ST_OUTBOUND_PRE;
        end if;
        
      when ST_OUTBOUND =>
        if out_valid_i = '1' and bus_i.txe = '1' then
          if r.counter = 0 then
            if in_ready_i = '1' and bus_i.rxf = '1' then
              rin.state <= ST_INBOUND_PRE;
            end if;
          else
            rin.counter <= r.counter - 1;
          end if;
        elsif in_ready_i = '1' and bus_i.rxf = '1' then
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

  clock_o <= bus_i.clk;
  in_data_o <= bus_i.data;
  bus_o.data <= out_data_i;

  handshaking: process(r, in_ready_i, out_valid_i, bus_i)
  begin
    out_ready_o <= '0';
    in_valid_o <= '0';
    bus_o.rd <= '0';
    bus_o.wr <= '0';

    case r.state is
      when ST_INBOUND =>
        bus_o.rd <= in_ready_i and bus_i.rxf;
        in_valid_o <= bus_i.rxf;

      when ST_OUTBOUND =>
        out_ready_o <= bus_i.txe;
        bus_o.wr <= out_valid_i and bus_i.txe;

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
  
end arch;
