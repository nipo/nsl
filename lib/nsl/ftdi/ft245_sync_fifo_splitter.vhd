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
    S_FROM_IN,
    S_TO_OUT_TURN,
    S_TO_OUT,
    S_FROM_IN_TURN
  );

  signal r_state: state_type := S_FROM_IN;
  signal s_state: state_type := S_FROM_IN;
  signal r_counter: integer range 0 to burst_length-1 := 0;
  signal s_counter: integer range 0 to burst_length-1 := 0;

  signal s_can_in : boolean;
  signal s_can_out : boolean;
  
begin

  -- Synchronous update
  process (p_clk, p_resetn)
  begin
    if (p_resetn = '0') then
      r_state <= S_FROM_IN;
      r_counter <= 0;
    elsif (rising_edge(p_clk)) then
      r_state <= s_state;
      r_counter <= s_counter;
    end if;
  end process;

  s_can_in <= p_out_write = '1' and p_ftdi_txen = '0';
  s_can_out <= p_in_read = '1' and p_ftdi_rxfn = '0';
  
  -- Next state
  process (r_counter, r_state, s_can_in, s_can_out)
  begin
    s_counter <= r_counter;
    s_state <= r_state;
    
    case r_state is
      when S_FROM_IN =>
        if s_can_in then
          if (r_counter = burst_length-1) then
            if s_can_out then
              s_state <= S_TO_OUT_TURN;
            end if;
          else
            s_counter <= r_counter + 1;
          end if;
        elsif s_can_out then
          s_state <= S_TO_OUT_TURN;
        end if;
        
      when S_TO_OUT =>
        if s_can_out then
          if (r_counter = burst_length-1) then
            if s_can_in then
              s_state <= S_FROM_IN_TURN;
            end if;
          else
            s_counter <= r_counter + 1;
          end if;
        elsif s_can_in then
          s_state <= S_FROM_IN_TURN;
        end if;
        
      when S_FROM_IN_TURN =>
        s_state <= S_FROM_IN;
        s_counter <= 0;
        
      when S_TO_OUT_TURN =>
        s_state <= S_TO_OUT;
        s_counter <= 0;
    end case;
  end process;

  -- Constant mapping
  p_in_data <= std_ulogic_vector(p_ftdi_data);

  -- Moore signals
  process (r_state)
  begin
    case r_state is
      when S_FROM_IN | S_FROM_IN_TURN =>
        p_ftdi_oen <= '1';
      when S_TO_OUT_TURN | S_TO_OUT =>
        p_ftdi_oen <= '0';
    end case;
  end process;

  -- Mealy signals
  process (r_state, p_in_read, p_out_write, p_ftdi_rxfn, p_ftdi_txen, p_out_data)
  begin
    case r_state is
      when S_FROM_IN =>
        p_ftdi_rdn <= '1';
        p_in_empty_n <= '0';

        p_ftdi_wrn <= not p_out_write;
        p_out_full_n <= not p_ftdi_txen;

        p_ftdi_data <= std_logic_vector(p_out_data);

      when S_FROM_IN_TURN | S_TO_OUT_TURN =>
        p_ftdi_rdn <= '1';
        p_in_empty_n <= '0';

        p_ftdi_wrn <= '1';
        p_out_full_n <= '0';
          
        p_ftdi_data <= (others => 'Z');

      when S_TO_OUT =>
        p_ftdi_rdn <= not p_in_read;
        p_in_empty_n <= not p_ftdi_rxfn;

        p_ftdi_wrn <= '1';
        p_out_full_n <= '0';
          
        p_ftdi_data <= (others => 'Z');
    end case;
  end process;
  
end arch;
