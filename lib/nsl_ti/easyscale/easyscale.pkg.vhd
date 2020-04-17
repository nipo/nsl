library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_io;

package easyscale is

  component easyscale_framed_master is
    generic(
      clock_rate_c : natural
      );
    port(
      reset_n_i    : in std_ulogic;
      clock_i       : in std_ulogic;

      easyscale_o: out nsl_io.io.tristated;
      easyscale_i: in std_ulogic;

      cmd_i  : in  nsl_bnoc.framed.framed_req;
      cmd_o  : out nsl_bnoc.framed.framed_ack;

      rsp_o : out nsl_bnoc.framed.framed_req;
      rsp_i : in  nsl_bnoc.framed.framed_ack
      );
  end component;

  component easyscale_master is
    generic(
      clock_rate_c : natural range 1000000 to 100000000
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      easyscale_o: out nsl_io.io.tristated;
      easyscale_i: in std_ulogic;

      dev_addr_i : in std_ulogic_vector(7 downto 0);
      ack_req_i  : in std_ulogic;
      reg_addr_i : in std_ulogic_vector(1 downto 0);
      data_i     : in std_ulogic_vector(4 downto 0);
      start_i    : in std_ulogic;

      busy_o     : out std_ulogic;
      dev_ack_o  : out std_ulogic
      );
  end component;

end package easyscale;
