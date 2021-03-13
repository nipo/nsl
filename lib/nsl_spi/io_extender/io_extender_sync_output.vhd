library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity io_extender_sync_output is
  generic(
    clock_divisor_c : natural
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    data_i  : in  std_ulogic_vector;
    ready_o : out std_ulogic;

    sr_d_o      : out std_ulogic;
    sr_clock_o  : out std_ulogic;
    sr_strobe_o : out std_ulogic
    );
end entity;

architecture beh of io_extender_sync_output is

  type state_t is (
    STATE_RESET,
    STATE_START,
    STATE_SHIFT_LOW,
    STATE_SHIFT_HIGH,
    STATE_STROBE,
    STATE_IDLE
    );

  type regs_t is record
    last_value, shreg: std_ulogic_vector(0 to data_i'length-1);
    state: state_t;
    changed: boolean;
    bit_ctr: natural range 0 to data_i'length-1;
    clk_div: natural range 0 to clock_divisor_c-1;
  end record;
  
  signal r, rin: regs_t;
  
begin

  regs: process (reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= STATE_RESET;
    end if;
  end process;

  transition: process(r, data_i)
  begin
    rin <= r;

    if data_i /= r.last_value then
      rin.changed <= true;
    end if;
    
    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_START;

      when STATE_IDLE =>
        if r.changed then
          rin.state <= STATE_START;
        end if;

      when STATE_START =>
        rin.last_value <= data_i;
        rin.shreg <= data_i;
        rin.changed <= false;
        rin.state <= STATE_SHIFT_LOW;
        rin.bit_ctr <= data_i'length - 1;
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
            rin.shreg <= r.shreg(1 to r.shreg'right) & "-";
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
    sr_d_o <= r.shreg(0);
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
