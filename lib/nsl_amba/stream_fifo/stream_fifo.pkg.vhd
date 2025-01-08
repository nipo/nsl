library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

package stream_fifo is

  -- Single or dual-clock stream fifo
  component axi4_stream_fifo is
    generic(
      config_c : nsl_amba.axi4_stream.config_t;
      depth_c : positive range 4 to positive'high;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;
      in_free_o : out integer range 0 to depth_c;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;
      out_available_o : out integer range 0 to depth_c + 1
      );
  end component;

  -- Single-clock register slice (i.e. a 3-depth fifo).
  -- Totally decouples input clocking constraints from output ones.
  -- Has at least one cycle latency.
  component axi4_stream_slice is
    generic(
      config_c : nsl_amba.axi4_stream.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

  -- Stream CDC. Does it by resynchronizing handshake both ways. Takes
  -- at most 2 slow + 2 fast clock cycles for one beat crossing.
  component axi4_stream_cdc is
    generic(
      config_c : nsl_amba.axi4_stream.config_t
      );
    port(
      clock_i : in std_ulogic_vector(0 to 1);
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

  -- Cancellable fifo handling AXI4 stream, do not support
  -- 2 differents clock
  component axi4_stream_fifo_cancellable is
    generic(
      config_c : nsl_amba.axi4_stream.config_t;
      word_count_l2_c : integer
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i : in  std_ulogic;
  
      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in  nsl_amba.axi4_stream.slave_t;
      out_commit_i : in std_ulogic := '1';
      out_rollback_i : in std_ulogic := '0';
      out_available_o : out unsigned(word_count_l2_c downto 0);
  
      in_i  : in  nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;
      in_commit_i : in std_ulogic := '1';
      in_rollback_i : in std_ulogic := '0';
      in_free_o : out unsigned(word_count_l2_c downto 0)
      );
  end component;

end package stream_fifo;
