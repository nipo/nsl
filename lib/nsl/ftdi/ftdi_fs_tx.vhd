library ieee;
use ieee.std_logic_1164.all;

library nsl;

entity ftdi_fs_tx is
  port (
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_clk_en : in  std_ulogic;
    p_serial : out std_ulogic;
    p_cts    : in  std_ulogic;

    p_ready   : out std_ulogic;
    p_valid   : in  std_ulogic;
    p_data    : in  std_ulogic_vector(7 downto 0);
    p_channel : in  std_ulogic
    );
end ftdi_fs_tx;

architecture arch of ftdi_fs_tx is
  
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
  
  regs: process (p_clk, p_resetn)
  begin
    if (p_resetn = '0') then
      r.state <= RESET;
    elsif (rising_edge(p_clk)) then
      r <= rin;
    end if;
  end process;

  transition: process (r, p_clk_en, p_cts, p_valid, p_data, p_channel)
  begin
    rin <= r;

    case r.state is
      when RESET =>
        rin.state <= PARALLEL_WAITING;

      when PARALLEL_WAITING =>
        if p_valid = '1' then
          if p_cts = '1' and p_clk_en = '1' then
            rin.state <= STARTING;
          else
            rin.state <= CTS_WAITING;
          end if;
          rin.data <= p_channel & p_data;
        end if;

      when CTS_WAITING =>
        if p_cts = '1' and p_clk_en = '1' then
          rin.state <= STARTING;
        end if;

      when STARTING =>
        if p_clk_en = '1' then
          rin.state <= SHIFTING;
          rin.cycle <= 8;
        end if;

      when SHIFTING =>
        if p_clk_en = '1' then
          if r.cycle /= 0 then
            rin.cycle <= r.cycle - 1;
            rin.data <= "-" & r.data(8 downto 1);
          else
            rin.state <= PARALLEL_WAITING;
          end if;
        end if;
    end case;
  end process;
  
  moore: process (p_clk)
  begin
    if falling_edge(p_clk) then
      case r.state is
        when STARTING =>
          p_serial <= '0';
          
        when SHIFTING =>
          p_serial <= r.data(0);

        when others =>
          p_serial <= '1';
      end case;

      case r.state is
        when PARALLEL_WAITING =>
          p_ready <= '1';

        when others =>
          p_ready <= '0';
      end case;
    end if;
  end process;

end arch;
