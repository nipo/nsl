library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, work;
use work.smi.all;
use work.slave.all;

entity smi_c22_slave_regmap is
  generic (
    phy_addr_c: unsigned(4 downto 0);
    reg_count_c: integer := 16
    );
  port (
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    smi_i           : in smi_slave_i;
    smi_o           : out smi_slave_o;

    register_i     : in smi_reg_array_t(0 to reg_count_c-1);
    register_o     : out smi_reg_array_t(0 to reg_count_c-1)
    );
end entity smi_c22_slave_regmap;

architecture rtl of smi_c22_slave_regmap is

  constant config_c: nsl_amba.axi4_mm.config_t := nsl_amba.axi4_mm.config(
    address_width => 7,
    data_bus_width => 32);
  signal bus_s: nsl_amba.axi4_mm.bus_t;

  signal reg_no_s: natural range 0 to 31;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s : std_ulogic;

begin

  slave: smi_c22_slave_axi_master
    generic map(
      phy_addr_c => phy_addr_c,
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      smi_i => smi_i,
      smi_o => smi_o,
      regmap_i => bus_s.s,
      regmap_o => bus_s.m
      );

  mm_regmap: nsl_amba.axi4_mm.axi4_mm_lite_regmap
    generic map(
      config_c => config_c,
      reg_count_l2_c => 5
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      axi_i => bus_s.m,
      axi_o => bus_s.s,
      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s
      );

  write_proc: process(clock_i)
  begin
    if rising_edge(clock_i) then
      if w_strobe_s = '1' then
        for i in register_o'range
        loop
          if i = reg_no_s then
            register_o(i) <= w_value_s(15 downto 0);
          end if;
        end loop;
      end if;
    end if;

    if reset_n_i = '0' then
      for i in register_o'range
      loop
        register_o(i) <= (others => '0');
      end loop;
    end if;
  end process;

  read_mux: process(reg_no_s, register_i)
  begin
    r_value_s <= (others => '0');
    for i in register_i'range
    loop
      if i = reg_no_s then
        r_value_s(15 downto 0) <= register_i(i);
      end if;
    end loop;
  end process;

end architecture;
