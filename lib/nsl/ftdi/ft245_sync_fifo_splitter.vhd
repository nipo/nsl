library ieee;
use ieee.std_logic_1164.all;

entity ft245_sync_fifo_splitter is
  generic (
    burst_length: integer := 64
    );
  port (
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_ftdi_data : inout std_logic_vector(7 downto 0);
    p_ftdi_rxfn : in    std_ulogic;
    p_ftdi_txen : in    std_ulogic;
    p_ftdi_rdn  : out   std_ulogic;
    p_ftdi_wrn  : out   std_ulogic;
    p_ftdi_oen  : out   std_ulogic;

    p_in_read    : in  std_ulogic;
    p_in_empty_n : out std_ulogic;
    p_in_data    : out std_ulogic_vector(7 downto 0);

    p_out_full_n : out std_ulogic;
    p_out_write  : in  std_ulogic;
    p_out_data   : in  std_ulogic_vector(7 downto 0)
    );
end ft245_sync_fifo_splitter;

architecture arch of ft245_sync_fifo_splitter is

  type state_type is (
    S_RESET,
    S_TO_P_IN,
    S_FROM_P_OUT_TURN,
    S_FROM_P_OUT,
    S_TO_P_IN_TURN
  );

  type regs_t is record
    state: state_type;
    counter: integer range 0 to burst_length-1;
  end record;

  signal r, rin: regs_t;

  signal s_p_out_ready : std_ulogic;
  signal s_p_in_ready : std_ulogic;
  signal s_oe : std_ulogic;
  
begin

  process (p_clk, p_resetn)
  begin
    if (p_resetn = '0') then
      r.state <= S_RESET;
    elsif (rising_edge(p_clk)) then
      r <= rin;
    end if;
  end process;

  s_p_out_ready <= p_out_write and not p_ftdi_txen;
  s_p_in_ready <= p_in_read and not p_ftdi_rxfn;
  
  -- Next state
  process (r, s_p_out_ready, s_p_in_ready)
  begin
    rin <= r;
    
    case r.state is
      when S_RESET =>
        rin.state <= S_TO_P_IN_TURN;
        
      when S_TO_P_IN =>
        if s_p_in_ready = '1' then
          if r.counter = 0 then
            if s_p_out_ready = '1' then
              rin.state <= S_FROM_P_OUT_TURN;
            end if;
          else
            rin.counter <= r.counter - 1;
          end if;
        elsif s_p_out_ready = '1' then
          rin.state <= S_FROM_P_OUT_TURN;
        end if;
        
      when S_FROM_P_OUT =>
        if s_p_out_ready = '1' then
          if r.counter = 0 then
            if s_p_in_ready = '1' then
              rin.state <= S_TO_P_IN_TURN;
            end if;
          else
            rin.counter <= r.counter - 1;
          end if;
        elsif s_p_in_ready = '1' then
          rin.state <= S_TO_P_IN_TURN;
        end if;
        
      when S_TO_P_IN_TURN =>
        rin.state <= S_TO_P_IN;
        rin.counter <= burst_length - 1;
        
      when S_FROM_P_OUT_TURN =>
        rin.state <= S_FROM_P_OUT;
        rin.counter <= burst_length - 1;
    end case;
  end process;

  p_in_data <= std_ulogic_vector(p_ftdi_data);
  p_ftdi_data <= std_logic_vector(p_out_data) when s_oe = '1' else (p_ftdi_data'range => 'Z');

  p_out_full_n <= s_p_out_ready when r.state = S_FROM_P_OUT else '0';
  p_ftdi_rdn <= not s_p_in_ready when r.state = S_TO_P_IN else '1';

  p_in_empty_n <= s_p_in_ready when r.state = S_TO_P_IN else '0';
  p_ftdi_wrn <= not s_p_out_ready when r.state = S_FROM_P_OUT else '1';
  
  process (p_clk)
  begin
    if falling_edge(p_clk) then
      p_ftdi_oen <= '1';
      s_oe <= '0';

      case r.state is
        when S_TO_P_IN_TURN =>
          p_ftdi_oen <= '0';

        when S_TO_P_IN =>
          p_ftdi_oen <= '0';

        when S_FROM_P_OUT_TURN =>
          s_oe <= '1';
          
        when S_FROM_P_OUT =>
          s_oe <= '1';

        when others =>
          null;

      end case;
    end if;
  end process;
  
end arch;
