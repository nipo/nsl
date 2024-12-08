library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

package ram is

  -- AXI4 RAM which will use either full-featured dual port flavor or
  -- lite one depending on whether config is lite.
  component axi4_mm_ram is
    generic(
      config_c : nsl_amba.axi4_mm.config_t;
      byte_size_l2_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i : in nsl_amba.axi4_mm.master_t;
      axi_o : out nsl_amba.axi4_mm.slave_t
      );
  end component;
  
  -- AXI4-MM RAM with concurrent read and write channels.  It supports
  -- bursting and requires a dual-port block RAM
  component axi4_mm_full_ram is
    generic(
      config_c : nsl_amba.axi4_mm.config_t;
      byte_size_l2_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i : in nsl_amba.axi4_mm.master_t;
      axi_o : out nsl_amba.axi4_mm.slave_t
      );
  end component;

  -- AXI4-Lite RAM, using a one-port block RAM.
  component axi4_mm_lite_ram is
    generic (
      config_c: nsl_amba.axi4_mm.config_t;
      byte_size_l2_c: positive
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      axi_i: in nsl_amba.axi4_mm.master_t;
      axi_o: out nsl_amba.axi4_mm.slave_t
      );
  end component;

  component apb_ram is
    generic (
      config_c: nsl_amba.apb.config_t;
      byte_size_l2_c: positive
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      apb_i: in nsl_amba.apb.master_t;
      apb_o: out nsl_amba.apb.slave_t
      );
  end component;
  
end package;
