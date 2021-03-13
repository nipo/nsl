library ieee;
use ieee.std_logic_1164.all;

entity fast_serial_tx is
  port (
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    clock_en_i : in  std_ulogic;
    serial_o : out std_ulogic;
    cts_i    : in  std_ulogic;

    ready_o   : out std_ulogic;
    valid_i   : in  std_ulogic;
    data_i    : in  std_ulogic_vector(7 downto 0);
    channel_i : in  std_ulogic
    );
end fast_serial_tx;

architecture arch of fast_serial_tx is
  
  type state_t is (
    RESET,
    PARALLEL_WAITING,
    CTS_WAITING,
    STARTING,
    SHIFTING
    );
  
  type regs_t is record
    data : std_ulogic_vector(8 downto 0);
    cycle : integer range 0 to 8;
    state : state_t;
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

  transition: process (r, clock_en_i, cts_i, valid_i, data_i, channel_i)
  begin
    rin <= r;

    case r.state is
      when RESET =>
        rin.state <= PARALLEL_WAITING;

      when PARALLEL_WAITING =>
        if valid_i = '1' then
          if cts_i = '1' and clock_en_i = '1' then
            rin.state <= STARTING;
          else
            rin.state <= CTS_WAITING;
          end if;
          rin.data <= channel_i & data_i;
        end if;

      when CTS_WAITING =>
        if cts_i = '1' and clock_en_i = '1' then
          rin.state <= STARTING;
        end if;

      when STARTING =>
        if clock_en_i = '1' then
          rin.state <= SHIFTING;
          rin.cycle <= 8;
        end if;

      when SHIFTING =>
        if clock_en_i = '1' then
          if r.cycle /= 0 then
            rin.cycle <= r.cycle - 1;
            rin.data <= "-" & r.data(8 downto 1);
          else
            rin.state <= PARALLEL_WAITING;
          end if;
        end if;
    end case;
  end process;
  
  moore: process (clock_i)
  begin
    if falling_edge(clock_i) then
      case r.state is
        when STARTING =>
          serial_o <= '0';
          
        when SHIFTING =>
          serial_o <= r.data(0);

        when others =>
          serial_o <= '1';
      end case;

      case r.state is
        when PARALLEL_WAITING =>
          ready_o <= '1';

        when others =>
          ready_o <= '0';
      end case;
    end if;
  end process;

end arch;
