library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.apb.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity mockup_slave is
  generic (
    config_c: config_t;
    index_c: natural
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic := '1';

    apb_i: in master_t;
    apb_o: out slave_t
    );
end entity;

architecture rtl of mockup_slave is

  signal reg_no_s: natural range 0 to 3;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s : std_ulogic;

  constant index: unsigned(31 downto 0) := to_unsigned(index_c, 32);

  signal reg0: unsigned(31 downto 0);
  signal reg1: unsigned(31 downto 0);

begin

  writing: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if w_strobe_s = '1' then
        case reg_no_s is
          when 0 =>
            reg0 <= w_value_s;

          when 1 =>
            reg1 <= w_value_s xor index;

          when others =>
            null;
        end case;
      end if;
    end if;

    if reset_n_i = '0' then
    end if;
  end process;

  with reg_no_s select r_value_s <=
    reg0        when 0,
    reg1        when 1,
    index       when 2,
    x"00000000" when others;

  regmap: nsl_amba.apb.apb_regmap
    generic map(
      config_c => config_c,
      reg_count_l2_c => 2
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s
      );

end architecture;
