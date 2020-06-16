library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

package tla202x is

  constant SADDR_GND : unsigned(7 downto 1) := "1001000";
  constant SADDR_VDD : unsigned(7 downto 1) := "1001001";
  constant SADDR_SCL : unsigned(7 downto 1) := "1001011";

  constant MUX_01 : unsigned(2 downto 0) := "000";
  constant MUX_03 : unsigned(2 downto 0) := "001";
  constant MUX_13 : unsigned(2 downto 0) := "010";
  constant MUX_23 : unsigned(2 downto 0) := "011";
  constant MUX_0G : unsigned(2 downto 0) := "100";
  constant MUX_1G : unsigned(2 downto 0) := "101";
  constant MUX_2G : unsigned(2 downto 0) := "110";
  constant MUX_3G : unsigned(2 downto 0) := "111";

  constant PGA_3mV : unsigned(2 downto 0) := "000";
  constant PGA_2mV : unsigned(2 downto 0) := "001";
  constant PGA_1mV : unsigned(2 downto 0) := "010";
  constant PGA_mV5 : unsigned(2 downto 0) := "011";
  constant PGA_mV25 : unsigned(2 downto 0) := "100";
  constant PGA_mV125 : unsigned(2 downto 0) := "101";

  constant DR_128 : unsigned(2 downto 0) := "000";
  constant DR_250 : unsigned(2 downto 0) := "001";
  constant DR_490 : unsigned(2 downto 0) := "010";
  constant DR_920 : unsigned(2 downto 0) := "011";
  constant DR_1600 : unsigned(2 downto 0) := "100";
  constant DR_2400 : unsigned(2 downto 0) := "101";
  constant DR_3300 : unsigned(2 downto 0) := "110";

  component tla202x_master is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      cmd_o : out nsl_bnoc.framed.framed_req;
      cmd_i : in  nsl_bnoc.framed.framed_ack;
      rsp_i : in  nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack;

      saddr_i : in unsigned(7 downto 1);
      
      mux_i         : in  unsigned(2 downto 0) := MUX_0G;
      pga_i         : in  unsigned(2 downto 0) := PGA_1mV;
      dr_i          : in  unsigned(2 downto 0) := DR_1600;
      single_shot_i : in  std_ulogic           := '1';
      valid_i       : in  std_ulogic;
      ready_o       : out std_ulogic;

      sample_o : out unsigned(11 downto 0);
      valid_o  : out std_ulogic;
      ready_i  : in  std_ulogic
      );
  end component;

end package tla202x;
