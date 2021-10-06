library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_clocking, nsl_line_coding, nsl_data;
use nsl_simulation.assertions.all;
use nsl_line_coding.tmds.all;

entity tb is
end tb;

architecture arch of tb is

  type io_t is
  record
    de : std_ulogic;
    data : unsigned(7 downto 0);
    terc4 : std_ulogic;
    control : std_ulogic_vector(3 downto 0);
  end record;

  signal gen_s, dec_s : io_t;
  type io_pipe_t is array (integer range 0 to 3) of io_t;
  signal pipe_s : io_pipe_t;

  signal symbol_s : tmds_symbol_t;
  signal reset_n, reset_n_async, clock: std_ulogic;
  signal done: std_ulogic_vector(0 to 0);
  signal ok : std_ulogic;
  
begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_async,
      data_o => reset_n,
      clock_i => clock
      );

  stim: process
    variable prbs: nsl_data.prbs.prbs_state(14 downto 0) := (others => '1');
  begin
    done(0) <= '0';
    gen_s <= io_t'(de => '0', data => x"00", terc4 => '0', control => x"0");
    wait until rising_edge(reset_n);
    wait until rising_edge(clock);

    for i in 0 to 32768
    loop
      wait until falling_edge(clock);
      case prbs(13 downto 8) is
        when "000000" =>
          gen_s.de <= '0';
          gen_s.data <= "--------";
          gen_s.control <= "00" & std_ulogic_vector(prbs(1 downto 0));
          gen_s.terc4 <= '0';

        when "000001" =>
          gen_s.de <= '0';
          gen_s.data <= "--------";
          gen_s.control <= std_ulogic_vector(prbs(3 downto 0));
          gen_s.terc4 <= '1';

        when others =>
          gen_s.de <= '1';
          gen_s.data <= unsigned(prbs(7 downto 0));
          gen_s.control <= "----";
          gen_s.terc4 <= '0';
      end case;
        
      wait until rising_edge(clock);
      prbs := nsl_data.prbs.prbs_forward(prbs, nsl_data.prbs.prbs15, 11);
    end loop;

    wait for 1000 ns;
    done(0) <= '1';
    wait;
  end process;

  pi: process(clock) is
  begin
    if rising_edge(clock) then
      pipe_s <= pipe_s(1 to pipe_s'right) & gen_s;
    end if;
  end process;
  
  checker: process
    variable c: io_t;
  begin
    ok <= '0';
    wait for 3 us;

    while true
    loop
      wait until rising_edge(clock);
      wait for 10 ns;

      ok <= '0';
    
      c := pipe_s(0);
      ok <= '1';
      if c.terc4 = '0' then
        assert_equal("de", dec_s.de, c.de, ERROR);
        if dec_s.de /= c.de then
          ok <= '0';
        end if;
      end if;
      if c.de = '1' then
        assert_equal("data", dec_s.data, c.data, ERROR);
        if dec_s.data /= c.data then
          ok <= '0';
        end if;
      else
        assert_equal("control", dec_s.control(1 downto 0), c.control(1 downto 0), ERROR);
        if dec_s.control(1 downto 0) /= c.control(1 downto 0) then
          ok <= '0';
        end if;
      end if;
      if c.terc4 = '1' then
        assert_equal("T4 control", dec_s.control, c.control, ERROR);
        assert_equal("T4 terc4", dec_s.terc4, '1', ERROR);
        if dec_s.control /= c.control then
          ok <= '0';
        end if;
        if dec_s.terc4 = '0' then
          ok <= '0';
        end if;
      end if;
    end loop;

    wait;
  end process;

  enc: nsl_line_coding.tmds.tmds_encoder
    port map(
      clock_i => clock,
      reset_n_i => reset_n,

      pixel_i => gen_s.data,
      de_i => gen_s.de,
      terc4_i => gen_s.terc4,
      control_i => gen_s.control,

      symbol_o => symbol_s
      );

  decoder: nsl_line_coding.tmds.tmds_decoder
    port map(
      clock_i => clock,
      reset_n_i => reset_n,

      symbol_i => symbol_s,

      pixel_o => dec_s.data,
      de_o => dec_s.de,
      terc4_o => dec_s.terc4,
      control_o => dec_s.control
      );
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 800 ns,
      reset_n_o(0) => reset_n_async,
      clock_o(0) => clock,
      done_i => done
      );
  
end;
