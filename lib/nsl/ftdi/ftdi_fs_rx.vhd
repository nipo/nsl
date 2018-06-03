library ieee;
use ieee.std_logic_1164.all;

library nsl;

entity ftdi_fs_rx is
  port (
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_clk_en : out std_ulogic;
    p_serial : in  std_ulogic;
    p_cts    : out std_ulogic;

    p_ready   : in  std_ulogic;
    p_valid   : out std_ulogic;
    p_data    : out std_ulogic_vector(7 downto 0);
    p_channel : out std_ulogic
    );
end ftdi_fs_rx;

architecture arch of ftdi_fs_rx is
  
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
  
  regs: process (p_clk, p_resetn)
  begin
    if (p_resetn = '0') then
      r.state <= RESET;
    elsif (rising_edge(p_clk)) then
      r <= rin;
    end if;
  end process;

  transition: process (r, p_serial, p_ready)
    variable start_bit : boolean;
  begin
    rin <= r;
    start_bit := false;

    case r.state is
      when RESET =>
        rin.state <= START_WAITING;
        rin.cts <= '0';

      when START_WAITING | PARALLEL_RESUME =>
        rin.cts <= p_ready;
        if p_serial = '0' then
          start_bit := true;
        end if;

      when SHIFTING =>
        rin.data <= p_serial & r.data(8 downto 1);
        if r.cycle /= 0 then
          rin.cycle <= r.cycle - 1;
        elsif p_ready = '1' then
          rin.state <= PARALLEL_PIPELINED;
        else
          rin.state <= PARALLEL_STALLED;
        end if;

      when PARALLEL_PIPELINED =>
        assert p_ready = '1'
          report "p_ready was asserted on previous cycle but got deasserted early"
          severity failure;

        if p_serial = '0' then
          start_bit := true;
        else
          rin.state <= START_WAITING;
        end if;

      when PARALLEL_STALLED =>
        if p_ready = '1' then
          rin.state <= PARALLEL_RESUME;
        end if;
    end case;

    if start_bit then
      rin.data <= (others => '-');
      rin.state <= SHIFTING;
      rin.cycle <= 8;
      rin.cts <= p_ready;
    end if;    
  end process;

  moore: process (p_clk)
  begin
    if falling_edge(p_clk) then
      p_cts <= r.cts;

      case r.state is
        when PARALLEL_STALLED | RESET =>
          p_clk_en <= '0';

        when others =>
          p_clk_en <= '1';
      end case;

      case r.state is
        when PARALLEL_PIPELINED | PARALLEL_STALLED =>
          p_data <= r.data(7 downto 0);
          p_channel <= r.data(8);
          p_valid <= '1';

        when others =>
          p_data <= (others => '-');
          p_channel <= '-';
          p_valid <= '0';
      end case;
    end if;
  end process;

end arch;
