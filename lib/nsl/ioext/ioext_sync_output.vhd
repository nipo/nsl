library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ioext_sync_output is
  generic(
    p_clk_rate : natural;
    p_sr_clk_rate : natural
    );
  port(
    p_resetn    : in std_ulogic;
    p_clk       : in std_ulogic;

    p_data      : in std_ulogic_vector(7 downto 0);
    p_done      : out std_ulogic;

    p_sr_d      : out std_ulogic;
    p_sr_clk    : out std_ulogic;
    p_sr_strobe : out std_ulogic
    );
end entity;

architecture beh of ioext_sync_output is

  type state_t is (
    STATE_START,
    STATE_SHIFT_LOW,
    STATE_SHIFT_HIGH,
    STATE_STROBE,
    STATE_IDLE
    );

  type regs_t is record
    data: std_ulogic_vector(7 downto 0);
    state: state_t;
    bit_ctr: natural range 0 to 7;
    clk_div: natural range 0 to p_clk_rate-1;
  end record;
  
  signal r, rin: regs_t;
  
begin

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_START;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_data)
  begin
    rin <= r;

    case r.state is
      when STATE_IDLE =>
        if p_data /= r.data then
          rin.state <= STATE_START;
        end if;

      when STATE_START =>
        rin.data <= p_data;
        rin.state <= STATE_SHIFT_LOW;
        rin.bit_ctr <= 7;
        rin.clk_div <= 0;

      when STATE_SHIFT_LOW =>
        if r.clk_div < p_clk_rate - p_sr_clk_rate / 2 then
          rin.clk_div <= r.clk_div + p_sr_clk_rate / 2;
        else
          rin.clk_div <= r.clk_div + p_sr_clk_rate / 2 - p_clk_rate;
          rin.state <= STATE_SHIFT_HIGH;
        end if;

      when STATE_SHIFT_HIGH =>
        if r.clk_div < p_clk_rate - p_sr_clk_rate / 2 then
          rin.clk_div <= r.clk_div + p_sr_clk_rate / 2;
        else
          rin.clk_div <= r.clk_div + p_sr_clk_rate / 2 - p_clk_rate;
          if r.bit_ctr = 0 then
            rin.state <= STATE_STROBE;
          else
            rin.bit_ctr <= r.bit_ctr - 1;
            rin.state <= STATE_SHIFT_LOW;
          end if;
        end if;

      when STATE_STROBE =>
        if r.clk_div < p_clk_rate - p_sr_clk_rate / 2 then
          rin.clk_div <= r.clk_div + p_sr_clk_rate / 2;
        else
          rin.state <= STATE_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    p_sr_d <= r.data(r.bit_ctr);
    
    case r.state is
      when STATE_SHIFT_HIGH =>
        p_sr_strobe <= '0';
        p_sr_clk <= '1';

      when STATE_STROBE =>
        p_sr_strobe <= '1';
        p_sr_clk <= '0';

      when others =>
        p_sr_strobe <= '0';
        p_sr_clk <= '0';

    end case;
  end process;

  p_done <= '1' when r.data = p_data and r.state = STATE_IDLE and p_resetn = '1' else '0';
  
end architecture;
