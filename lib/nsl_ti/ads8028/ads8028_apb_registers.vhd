library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, work;
use work.ads8028.all;

entity ads8028_apb_registers is
  generic(
    config_c : nsl_amba.apb.config_t;
    channels_c : channel_mask_t := all_channels_c
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    apb_i : in nsl_amba.apb.master_t;
    apb_o : out nsl_amba.apb.slave_t;

    code_i : in code_vector(0 to channel_count_c-1);
    valid_i : in channel_mask_t;
    strobe_i : in channel_mask_t
    );
end entity;

architecture beh of ads8028_apb_registers is

  type count_vector is array(0 to channel_count_c-1) of unsigned(7 downto 0);
  signal count_s : count_vector;
  signal reg_no_s : integer range 0 to 15;
  signal r_value_s : unsigned(31 downto 0);

begin

  assert config_c.data_bus_width_l2 = 2
    report "ads8028_apb_registers: needs a 32-bit APB"
    severity failure;

  counters: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      for i in count_s'range
      loop
        if strobe_i(i) = '1' then
          count_s(i) <= count_s(i) + 1;
        end if;
      end loop;
    end if;
    if reset_n_i = '0' then
      count_s <= (others => (others => '0'));
    end if;
  end process;

  regmap: nsl_amba.apb.apb_regmap
    generic map(
      config_c => config_c,
      reg_count_l2_c => 4
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      reg_no_o => reg_no_s,
      w_value_o => open,
      w_strobe_o => open,
      r_value_i => r_value_s,
      r_strobe_o => open
      );

  r_value: process(reg_no_s, code_i, valid_i, count_s) is
  begin
    r_value_s <= (others => '0');
    case reg_no_s is
      when 0 to channel_count_c-1 =>
        r_value_s(31) <= valid_i(reg_no_s);
        r_value_s(23 downto 16) <= count_s(reg_no_s);
        r_value_s(11 downto 0) <= code_i(reg_no_s);
      when 15 =>
        r_value_s(31 downto 16) <= to_unsigned(1, 16);
        for i in channels_c'range
        loop
          r_value_s(i) <= channels_c(i);
        end loop;
      when others =>
        null;
    end case;
  end process;

end architecture;
