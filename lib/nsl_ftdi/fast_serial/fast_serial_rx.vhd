library ieee;
use ieee.std_logic_1164.all;

entity fast_serial_rx is
  port (
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    clock_en_o : out std_ulogic;
    serial_i : in  std_ulogic;
    cts_o    : out std_ulogic;

    ready_i   : in  std_ulogic;
    valid_o   : out std_ulogic;
    data_o    : out std_ulogic_vector(7 downto 0);
    channel_o : out std_ulogic
    );
end fast_serial_rx;

architecture arch of fast_serial_rx is
  
  type state_t is (
    RESET,
    START_WAITING,
    SHIFTING,
    PARALLEL_PIPELINED,
    PARALLEL_STALLED,
    PARALLEL_RESUME
    );
  
  type regs_t is record
    data : std_ulogic_vector(8 downto 0);
    cycle : integer range 0 to 8;
    state : state_t;
    cts : std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin
  
  regs: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= RESET;
    end if;
  end process;

  transition: process (r, serial_i, ready_i)
    variable start_bit : boolean;
  begin
    rin <= r;
    start_bit := false;

    case r.state is
      when RESET =>
        rin.state <= START_WAITING;
        rin.cts <= '0';

      when START_WAITING | PARALLEL_RESUME =>
        rin.cts <= ready_i;
        if serial_i = '0' then
          start_bit := true;
        end if;

      when SHIFTING =>
        rin.data <= serial_i & r.data(8 downto 1);
        if r.cycle /= 0 then
          rin.cycle <= r.cycle - 1;
        elsif ready_i = '1' then
          rin.state <= PARALLEL_PIPELINED;
        else
          rin.state <= PARALLEL_STALLED;
        end if;

      when PARALLEL_PIPELINED =>
        assert ready_i = '1'
          report "ready_i was asserted on previous cycle but got deasserted early"
          severity failure;

        if serial_i = '0' then
          start_bit := true;
        else
          rin.state <= START_WAITING;
        end if;

      when PARALLEL_STALLED =>
        if ready_i = '1' then
          rin.state <= PARALLEL_RESUME;
        end if;
    end case;

    if start_bit then
      rin.data <= (others => '-');
      rin.state <= SHIFTING;
      rin.cycle <= 8;
      rin.cts <= ready_i;
    end if;    
  end process;

  moore: process (clock_i)
  begin
    if falling_edge(clock_i) then
      cts_o <= r.cts;

      case r.state is
        when PARALLEL_STALLED | RESET =>
          clock_en_o <= '0';

        when others =>
          clock_en_o <= '1';
      end case;

      case r.state is
        when PARALLEL_PIPELINED | PARALLEL_STALLED =>
          data_o <= r.data(7 downto 0);
          channel_o <= r.data(8);
          valid_o <= '1';

        when others =>
          data_o <= (others => '-');
          channel_o <= '-';
          valid_o <= '0';
      end case;
    end if;
  end process;

end arch;
