library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_simulation, nsl_data;
use nsl_simulation.logging.all;
use nsl_data.text.all;

package testing is

  procedure a32_d32_snooper(constant prefix: string;
                            signal b: in nsl_axi.axi4_lite.a32_d32;
                            signal clock: in std_ulogic;
                            constant clock_period: time);
                            
  
  component axis_16l_file_reader is
    generic(
      filename: string
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      m_o   : out nsl_axi.stream.axis_16l_ms;
      m_i   : in nsl_axi.stream.axis_16l_sm;

      done_o : out std_ulogic
      );
  end component;

  component axis_16l_file_checker is
    generic(
      filename: string
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      s_o   : out nsl_axi.stream.axis_16l_sm;
      s_i   : in nsl_axi.stream.axis_16l_ms;

      done_o     : out std_ulogic
      );
  end component;

end package testing;

package body testing is

  procedure a32_d32_snooper(constant prefix: string;
                            signal b: in nsl_axi.axi4_lite.a32_d32;
                            signal clock: in std_ulogic;
                            constant clock_period: time)
  is
    variable waddr, raddr : unsigned(31 downto 0);
  begin
    while true
    loop
      wait until rising_edge(clock);
      wait for clock_period * 9 / 10;

      if b.ms.awvalid = '1' and b.sm.awready = '1' then
        waddr := unsigned(b.ms.awaddr);
      end if;

      if b.ms.arvalid = '1' and b.sm.arready = '1' then
        raddr := unsigned(b.ms.araddr);
      end if;

      if b.ms.wvalid = '1' and b.sm.wready = '1' then
        log_info(prefix & " W @" & to_string(waddr) & ": " & to_hex_string(b.ms.wdata) & ", strobe: " & to_string(b.ms.wstrb));
      end if;

      if b.ms.rready = '1' and b.sm.rvalid = '1' then
        log_info(prefix & " r @" & to_string(raddr) & ": " & to_hex_string(b.sm.rdata) & ", resp: " & to_string(b.sm.rresp));
      end if;

    end loop;
  end procedure;

end package body;
