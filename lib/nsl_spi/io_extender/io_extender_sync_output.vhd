library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ioext_sync_output is
  generic(
    clock_divisor_c : natural
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    data_i  : in  std_ulogic_vector(7 downto 0);
    ready_o : out std_ulogic;

    sr_d_o      : out std_ulogic;
    sr_clock_o  : out std_ulogic;
    sr_strobe_o : out std_ulogic
    );
end entity;

architecture beh of ioext_sync_output is

  type state_t is (
    STATE_RESET,
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
    clk_div: natural range 0 to clock_divisor_c-1;
  end record;
  
  signal r, rin: regs_t;
  
begin

  regs: process (reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, data_i)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_START;

      when STATE_IDLE =>
        if data_i /= r.data then
          rin.state <= STATE_START;
        end if;

      when STATE_START =>
        rin.data <= data_i;
        rin.state <= STATE_SHIFT_LOW;
        rin.bit_ctr <= 7;
        rin.clk_div <= clock_divisor_c - 1;

      when STATE_SHIFT_LOW =>
        if r.clk_div /= 0 then
          rin.clk_div <= r.clk_div - 1;
        else
          rin.clk_div <= clock_divisor_c - 1;
          rin.state <= STATE_SHIFT_HIGH;
        end if;

      when STATE_SHIFT_HIGH =>
        if r.clk_div /= 0 then
          rin.clk_div <= r.clk_div - 1;
        else
          rin.clk_div <= clock_divisor_c - 1;
          if r.bit_ctr = 0 then
            rin.state <= STATE_STROBE;
          else
            rin.bit_ctr <= r.bit_ctr - 1;
            rin.state <= STATE_SHIFT_LOW;
          end if;
        end if;

      when STATE_STROBE =>
        if r.clk_div /= 0 then
          rin.clk_div <= r.clk_div - 1;
        else
          rin.state <= STATE_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    sr_d_o <= r.data(r.bit_ctr);
    sr_strobe_o <= '0';
    sr_clock_o <= '0';
    ready_o <= '0';

    case r.state is
      when STATE_IDLE =>
        ready_o <= '1';

      when STATE_SHIFT_HIGH =>
        sr_clock_o <= '1';

      when STATE_STROBE =>
        sr_strobe_o <= '1';

      when others =>
        null;

    end case;
  end process;
  
end architecture;
