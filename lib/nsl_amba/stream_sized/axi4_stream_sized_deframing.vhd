library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.endian.all;

entity axi4_stream_sized_deframing is
  generic(
    in_config_c      : config_t;
    out_config_c     : config_t;
    header_length_c  : positive range 1 to 4 := 2;
    endian_c         : endian_t := ENDIAN_LITTLE;
    max_frame_size_c : natural := 2048
    );
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    in_i  : in  master_t;
    in_o  : out slave_t;

    out_o : out master_t;
    out_i : in  slave_t
    );
begin
  assert in_config_c.has_last
    report "in_config_c must have has_last"
    severity failure;
  assert not out_config_c.has_last
    report "out_config_c must not have has_last"
    severity failure;
  assert in_config_c.id_width = out_config_c.id_width
    report "in/out id_width must match"
    severity failure;
  assert in_config_c.dest_width = out_config_c.dest_width
    report "in/out dest_width must match"
    severity failure;
  assert in_config_c.user_width = out_config_c.user_width
    report "in/out user_width must match"
    severity failure;
  assert in_config_c.has_keep = out_config_c.has_keep
    report "in/out has_keep must match"
    severity failure;
  assert out_config_c.data_width = 1 or out_config_c.has_keep
    report "out_config_c has data_width > 1 without has_keep: partial last words will contain garbage bytes unless all frame sizes keep (header_length_c + data_size) a multiple of out_config_c.data_width"
    severity failure;
  assert in_config_c.has_strobe = out_config_c.has_strobe
    report "in/out has_strobe must match"
    severity failure;
end entity;

architecture rtl of axi4_stream_sized_deframing is

  constant in_1b_config_c : config_t := config(
    bytes  => 1,
    id     => in_config_c.id_width,
    user   => in_config_c.user_width,
    dest   => in_config_c.dest_width,
    keep   => in_config_c.has_keep,
    strobe => in_config_c.has_strobe,
    last   => true
    );

  signal framed_1b_ms : master_t;
  signal framed_1b_ss : slave_t;

begin

  narrower: nsl_amba.axi4_stream.axi4_stream_width_adapter
    generic map(
      in_config_c  => in_config_c,
      out_config_c => in_1b_config_c
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => in_i,
      in_o      => in_o,
      out_o     => framed_1b_ms,
      out_i     => framed_1b_ss
      );

  deframer: nsl_amba.stream_sized.axi4_stream_sized_deframing_1b_to_nb
    generic map(
      in_config_c      => in_1b_config_c,
      out_config_c     => out_config_c,
      header_length_c  => header_length_c,
      endian_c         => endian_c,
      max_frame_size_c => max_frame_size_c
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => framed_1b_ms,
      in_o      => framed_1b_ss,
      out_o     => out_o,
      out_i     => out_i
      );

end architecture;
