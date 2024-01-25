library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_io, nsl_color, nsl_i2c, nsl_hwdep, nsl_math, nsl_bnoc;

package neorv32_tester is

  component tester_root is
    generic(
      clock_i_hz_c : integer
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      serial_i : in string(1 to 8);

      ulpi_o: out nsl_usb.ulpi.ulpi8_link2phy;
      ulpi_i: in nsl_usb.ulpi.ulpi8_phy2link;

      flash_cs_n_o : out nsl_io.io.opendrain;
      flash_d_o : out nsl_io.io.directed_vector(0 to 1);
      flash_d_i : in std_ulogic_vector(0 to 1);
      flash_sel_o : out std_ulogic;
      flash_sck_o : out std_ulogic;

      sda_io, scl_io : inout std_logic;

      button_i: in std_ulogic_vector(1 to 4);
      led_color_o: out nsl_color.rgb.rgb24_vector(1 to 4);
      done_led_o: out std_ulogic
      );
  end component;

  component usb_function is
    generic(
      clock_i_hz_c: natural;
      transactor_count_c: natural
      );
    port(
      clock_i: in std_ulogic;
      app_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      app_reset_n_o : out std_ulogic;

      serial_i : in string(1 to 8);

      ulpi_o: out nsl_usb.ulpi.ulpi8_link2phy;
      ulpi_i: in nsl_usb.ulpi.ulpi8_phy2link;

      -- Transactors
      cmd_i: in nsl_bnoc.framed.framed_ack_array(0 to transactor_count_c-1);
      cmd_o: out nsl_bnoc.framed.framed_req_array(0 to transactor_count_c-1);
      rsp_i: in nsl_bnoc.framed.framed_req_array(0 to transactor_count_c-1);
      rsp_o: out nsl_bnoc.framed.framed_ack_array(0 to transactor_count_c-1);

      -- Serial port
      rx_o  : out nsl_bnoc.pipe.pipe_req_t;
      rx_i  : in  nsl_bnoc.pipe.pipe_ack_t;
      tx_i  : in  nsl_bnoc.pipe.pipe_req_t;
      tx_o  : out  nsl_bnoc.pipe.pipe_ack_t;
      
      online_o : out std_ulogic
      );
  end component;
  
end package;
