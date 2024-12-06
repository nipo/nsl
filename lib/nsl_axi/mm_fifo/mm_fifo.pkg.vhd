library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

-- MM FIFO and slices
package mm_fifo is

  -- An address channel (either aw or ar) fifo
  component axi4_mm_a_fifo is
    generic(
      config_c : work.axi4_mm.config_t;
      depth_c : positive range 4 to positive'high;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i : in work.axi4_mm.address_t;
      in_o : out work.axi4_mm.handshake_t;

      out_o : out work.axi4_mm.address_t;
      out_i : in work.axi4_mm.handshake_t
      );
  end component;

  -- A write data channel fifo
  component axi4_mm_w_fifo is
    generic(
      config_c : work.axi4_mm.config_t;
      depth_c : positive range 4 to positive'high;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i : in work.axi4_mm.write_data_t;
      in_o : out work.axi4_mm.handshake_t;

      out_o : out work.axi4_mm.write_data_t;
      out_i : in work.axi4_mm.handshake_t
      );
  end component;

  -- A write response channel fifo
  component axi4_mm_b_fifo is
    generic(
      config_c : work.axi4_mm.config_t;
      depth_c : positive range 4 to positive'high;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i : in work.axi4_mm.write_response_t;
      in_o : out work.axi4_mm.handshake_t;

      out_o : out work.axi4_mm.write_response_t;
      out_i : in work.axi4_mm.handshake_t
      );
  end component;

  -- A read data channel fifo
  component axi4_mm_r_fifo is
    generic(
      config_c : work.axi4_mm.config_t;
      depth_c : positive range 4 to positive'high;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i : in work.axi4_mm.read_data_t;
      in_o : out work.axi4_mm.handshake_t;

      out_o : out work.axi4_mm.read_data_t;
      out_i : in work.axi4_mm.handshake_t
      );
  end component;

  -- A full AXI4-MM fifo, with selectable depth for each channel.
  component axi4_mm_fifo is
    generic(
      config_c : work.axi4_mm.config_t;
      aw_depth_c : positive range 4 to positive'high;
      w_depth_c : positive range 4 to positive'high;
      b_depth_c : positive range 4 to positive'high;
      ar_depth_c : positive range 4 to positive'high;
      r_depth_c : positive range 4 to positive'high;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      slave_i : in work.axi4_mm.master_t;
      slave_o : out work.axi4_mm.slave_t;

      master_o : out work.axi4_mm.master_t;
      master_i : in work.axi4_mm.slave_t
      );
  end component;

  -- An address channel (either aw or ar) slice
  component axi4_mm_a_slice is
    generic(
      config_c : work.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in work.axi4_mm.address_t;
      in_o : out work.axi4_mm.handshake_t;

      out_o : out work.axi4_mm.address_t;
      out_i : in work.axi4_mm.handshake_t
      );
  end component;

  -- A write data channel slice
  component axi4_mm_w_slice is
    generic(
      config_c : work.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in work.axi4_mm.write_data_t;
      in_o : out work.axi4_mm.handshake_t;

      out_o : out work.axi4_mm.write_data_t;
      out_i : in work.axi4_mm.handshake_t
      );
  end component;

  -- A write response channel slice
  component axi4_mm_b_slice is
    generic(
      config_c : work.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in work.axi4_mm.write_response_t;
      in_o : out work.axi4_mm.handshake_t;

      out_o : out work.axi4_mm.write_response_t;
      out_i : in work.axi4_mm.handshake_t
      );
  end component;

  -- A read data channel slice
  component axi4_mm_r_slice is
    generic(
      config_c : work.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in work.axi4_mm.read_data_t;
      in_o : out work.axi4_mm.handshake_t;

      out_o : out work.axi4_mm.read_data_t;
      out_i : in work.axi4_mm.handshake_t
      );
  end component;

  -- A full AXI4-MM slice
  component axi4_mm_slice is
    generic(
      config_c : work.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      slave_i : in work.axi4_mm.master_t;
      slave_o : out work.axi4_mm.slave_t;

      master_o : out work.axi4_mm.master_t;
      master_i : in work.axi4_mm.slave_t
      );
  end component;

end package mm_fifo;
