library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_mm.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal bus_s: bus_t;

  constant config_c : config_t := config(address_width => 32,
                                         data_bus_width => 32);

begin

  writer: process is
    variable value: unsigned(31 downto 0);
    variable rsp: resp_enum_t;
  begin
    done_s(0) <= '0';
    
    bus_s.m.aw <= address_defaults(config_c);
    bus_s.m.w <= write_data_defaults(config_c);
    bus_s.m.r <= handshake_defaults(config_c);
    bus_s.m.b <= handshake_defaults(config_c);
    bus_s.m.ar <= address_defaults(config_c);

    wait for 30 ns;
    wait until falling_edge(clock_s);

    lite_write(config_c, clock_s, bus_s.s, bus_s.m, reg => 0, reg_lsb => 2, val => x"00010203");
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, reg => 1, reg_lsb => 2, val => x"04050607");
    lite_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 0, reg_lsb => 2, val => x"00010203");
    lite_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 2, reg_lsb => 2, val => x"04050607");
    lite_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 18, reg_lsb => 2, val => x"04050607");
    lite_check(config_c, clock_s, bus_s.s, bus_s.m, reg => 15, reg_lsb => 2, val => x"deadbeef");
    
    done_s(0) <= '1';
    wait;
  end process;

  regmap: block is
    signal reg_no_s: natural range 0 to 15;
    signal w_value_s, r_value_s : unsigned(31 downto 0);
    signal w_strobe_s : std_ulogic;

    signal reg0: unsigned(31 downto 0);
    signal reg1: unsigned(31 downto 0);
  begin
    writing: process(clock_s, reset_n_s) is
    begin
      if rising_edge(clock_s) then
        if w_strobe_s = '1' then
          case reg_no_s is
            when 0 =>
              reg0 <= w_value_s;

            when 1 =>
              reg1 <= w_value_s;

            when others =>
              null;
          end case;
        end if;
      end if;

      if reset_n_s = '0' then
      end if;
    end process;

    with reg_no_s select r_value_s <=
      reg0        when 0,
      x"ebadf00d" when 1,
      reg1        when 2,
      x"deadbeef" when others;

    dut: nsl_amba.axi4_mm.axi4_mm_lite_regmap
      generic map(
        config_c => config_c,
        reg_count_l2_c => 4
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        axi_i => bus_s.m,
        axi_o => bus_s.s,

        reg_no_o => reg_no_s,
        w_value_o => w_value_s,
        w_strobe_o => w_strobe_s,
        r_value_i => r_value_s
        );
  end block;  

  dumper: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "RAM"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => bus_s.m,
      slave_i => bus_s.s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
