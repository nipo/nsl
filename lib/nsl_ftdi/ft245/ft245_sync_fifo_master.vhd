library ieee;
use ieee.std_logic_1164.all;

entity ft245_sync_fifo_master is
  generic (
    burst_length: integer := 64
    );
  port (
    clock_o    : out std_ulogic;
    reset_n_i : in std_ulogic;

    ftdi_clk_i  : in std_ulogic;
    ftdi_data_io : inout std_logic_vector(7 downto 0);
    ftdi_rxf_n_i : in std_ulogic;
    ftdi_txe_n_i : in std_ulogic;
    ftdi_rd_n_o  : out std_ulogic;
    ftdi_wr_n_o  : out std_ulogic;
    ftdi_oe_n_o  : out std_ulogic;

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

  signal s_flow_out : std_ulogic;
  signal s_flow_in : std_ulogic;
  signal s_oe : std_ulogic;
  
begin

  regs: process (ftdi_clk_i, reset_n_i)
  begin
    if (reset_n_i = '0') then
      r.state <= S_RESET;
    elsif (rising_edge(ftdi_clk_i)) then
      r <= rin;
    end if;
  end process;

  s_flow_out <= out_valid_i and not ftdi_txe_n_i;
  s_flow_in <= in_ready_i and not ftdi_rxf_n_i;
  
  -- Next state
  transition: process (r, s_flow_out, s_flow_in)
  begin
    rin <= r;
    
    case r.state is
      when S_RESET =>
        rin.state <= S_TO_P_IN_TURN;
        
      when S_TO_P_IN =>
        if s_flow_in = '1' then
          if r.counter = 0 then
            if s_flow_out = '1' then
              rin.state <= S_FROM_P_OUT_TURN;
            end if;
          else
            rin.counter <= r.counter - 1;
          end if;
        elsif s_flow_out = '1' then
          rin.state <= S_FROM_P_OUT_TURN;
        end if;
        
      when S_FROM_P_OUT =>
        if s_flow_out = '1' then
          if r.counter = 0 then
            if s_flow_in = '1' then
              rin.state <= S_TO_P_IN_TURN;
            end if;
          else
            rin.counter <= r.counter - 1;
          end if;
        elsif s_flow_in = '1' then
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

  clock_o <= ftdi_clk_i;
  in_data_o <= std_ulogic_vector(ftdi_data_io);
  ftdi_data_io <= std_logic_vector(out_data_i) when s_oe = '1' else (ftdi_data_io'range => 'Z');

  handshaking: process(r.state, s_flow_in, s_flow_out)
  begin
    out_ready_o <= '0';
    in_valid_o <= '0';
    ftdi_rd_n_o <= '1';
    ftdi_wr_n_o <= '1';

    case r.state is
      when S_TO_P_IN =>
        ftdi_rd_n_o <= not s_flow_in;
        in_valid_o <= s_flow_in;

      when S_FROM_P_OUT =>
        out_ready_o <= s_flow_out;
        ftdi_wr_n_o <= not s_flow_out;

      when others =>
        null;

    end case;
  end process;
  
  moore: process (ftdi_clk_i)
  begin
    if falling_edge(ftdi_clk_i) then
      ftdi_oe_n_o <= '1';
      s_oe <= '0';

      case r.state is
        when S_TO_P_IN_TURN | S_TO_P_IN =>
          ftdi_oe_n_o <= '0';

        when S_FROM_P_OUT_TURN | S_FROM_P_OUT =>
          s_oe <= '1';

        when others =>
          null;

      end case;
    end if;
  end process;
  
end arch;
