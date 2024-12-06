library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_data, nsl_logic, nsl_math;
use nsl_math.arith.all;
use nsl_axi.axi4_mm.all;
use nsl_axi.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_logic.logic.all;
use nsl_logic.bool.all;

entity axi4_mm_on_stream is
  generic (
    mm_config_c : nsl_axi.axi4_mm.config_t;
    stream_config_c : nsl_axi.axi4_stream.config_t
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    slave_i : in nsl_axi.axi4_mm.master_t;
    slave_o : out nsl_axi.axi4_mm.slave_t;

    master_o : out nsl_axi.axi4_mm.master_t;
    master_i : in nsl_axi.axi4_mm.slave_t;
    
    rx_i : in nsl_axi.axi4_stream.master_t;
    rx_o : out nsl_axi.axi4_stream.slave_t;

    tx_o : out nsl_axi.axi4_stream.master_t;
    tx_i : in nsl_axi.axi4_stream.slave_t
    );
end entity;

architecture beh of axi4_mm_on_stream is

  function aligned_cfg(cfg: nsl_axi.axi4_stream.config_t;
                       vector_length: natural) return nsl_axi.axi4_stream.config_t
  is
    constant needed_byte_count : natural := (vector_length + 7) / 8;
    constant total_byte_count : natural := mod_up(needed_byte_count, cfg.data_width);
  begin
    return nsl_axi.axi4_stream.config(bytes => total_byte_count,
                                      keep => true,
                                      strobe => false,
                                      ready => true,
                                      last => true);
  end function;

  function vector_to_transfer(cfg: nsl_axi.axi4_stream.config_t;
                              v: std_ulogic_vector;
                              valid, last : boolean)
    return nsl_axi.axi4_stream.master_t
  is
    constant needed_byte_count : natural := (v'length + 7) / 8;
    constant padding_byte_count : natural := cfg.data_width - needed_byte_count;
    constant padding_bit_count : natural := cfg.data_width * 8 - v'length;
    
    constant mask : std_ulogic_vector(0 to needed_byte_count-1)
      := (others => '1');
    constant mask_pad : std_ulogic_vector(0 to padding_byte_count-1)
      := (others => '0');
    constant pad : byte_string(0 to padding_byte_count-1)
      := (others => dontcare_byte_c);
    constant bit_pad : std_ulogic_vector(0 to padding_bit_count-1)
      := (others => '0');
  begin
    return nsl_axi.axi4_stream.transfer(
      cfg,
      bytes => to_le(unsigned(bit_pad) & unsigned(v)),
      keep => mask & mask_pad,
      valid => valid,
      last => last);
  end function;

  function transfer_to_vector(cfg: nsl_axi.axi4_stream.config_t;
                              t: nsl_axi.axi4_stream.master_t;
                              len: natural)
    return std_ulogic_vector
  is
    constant needed_byte_count : natural := (len + 7) / 8;
    constant padding_byte_count : natural := cfg.data_width - needed_byte_count;
    constant padding_bit_count : natural := cfg.data_width * 8 - len;

    constant blob: byte_string(0 to cfg.data_width-1) := bytes(cfg, t);
    constant bv: std_ulogic_vector(needed_byte_count*8-1 downto 0)
      := std_ulogic_vector(from_le(blob(0 to needed_byte_count-1)));
  begin
    return bv(len-1 downto 0);
  end function;

  constant common_config_c: nsl_axi.axi4_stream.config_t
    := nsl_axi.axi4_stream.config(
      bytes => stream_config_c.data_width,
      id => stream_config_c.id_width - 3,
      keep => true,
      last => true,
      ready => true);

begin

  encode: block is
    signal aw_s, w_s, b_s, ar_s, r_s : nsl_axi.axi4_stream.bus_t;
  begin

    aw_enc: block is
      constant packed_len: natural := address_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
    begin
      packed_s.m <= vector_to_transfer(
        packed_cfg, vector_pack(mm_config_c, slave_i.aw),
        valid => is_valid(mm_config_c, slave_i.aw),
        last => true);
      slave_o.aw <= accept(mm_config_c, is_ready(packed_cfg, packed_s.s));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => packed_cfg,
          out_config_c => common_config_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => packed_s.m,
          in_o => packed_s.s,

          out_o => aw_s.m,
          out_i => aw_s.s
          );
    end block;

    w_enc: block is
      constant packed_len: natural := write_data_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
    begin
      packed_s.m <= vector_to_transfer(
        packed_cfg, vector_pack(mm_config_c, slave_i.w),
        valid => is_valid(mm_config_c, slave_i.w),
        last => is_last(mm_config_c, slave_i.w));
      slave_o.w <= accept(mm_config_c, is_ready(packed_cfg, packed_s.s));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => packed_cfg,
          out_config_c => common_config_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => packed_s.m,
          in_o => packed_s.s,

          out_o => w_s.m,
          out_i => w_s.s
          );
    end block;

    b_enc: block is
      constant packed_len: natural := write_response_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
    begin
      packed_s.m <= vector_to_transfer(
        packed_cfg, vector_pack(mm_config_c, master_i.b),
        valid => is_valid(mm_config_c, master_i.b),
        last => true);
      master_o.b <= accept(mm_config_c, is_ready(packed_cfg, packed_s.s));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => packed_cfg,
          out_config_c => common_config_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => packed_s.m,
          in_o => packed_s.s,

          out_o => b_s.m,
          out_i => b_s.s
          );
    end block;
    
    ar_enc: block is
      constant packed_len: natural := address_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
    begin
      packed_s.m <= vector_to_transfer(
        packed_cfg, vector_pack(mm_config_c, slave_i.ar),
        valid => is_valid(mm_config_c, slave_i.ar),
        last => true);
      slave_o.ar <= accept(mm_config_c, is_ready(packed_cfg, packed_s.s));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => packed_cfg,
          out_config_c => common_config_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => packed_s.m,
          in_o => packed_s.s,

          out_o => ar_s.m,
          out_i => ar_s.s
          );
    end block;

    r_enc: block is
      constant packed_len: natural := read_data_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
    begin
      packed_s.m <= vector_to_transfer(
        packed_cfg, vector_pack(mm_config_c, master_i.r),
        valid => is_valid(mm_config_c, master_i.r),
        last => is_last(mm_config_c, master_i.r));
      master_o.r <= accept(mm_config_c, is_ready(packed_cfg, packed_s.s));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => packed_cfg,
          out_config_c => common_config_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => packed_s.m,
          in_o => packed_s.s,

          out_o => r_s.m,
          out_i => r_s.s
          );
    end block;

    funnel: nsl_axi.stream_routing.axi4_stream_funnel
      generic map(
        in_config_c => common_config_c,
        out_config_c => stream_config_c,
        source_count_c => 5
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i(0) => b_s.m,
        in_i(1) => aw_s.m,
        in_i(2) => ar_s.m,
        in_i(3) => r_s.m,
        in_i(4) => w_s.m,
        in_o(0) => b_s.s,
        in_o(1) => aw_s.s,
        in_o(2) => ar_s.s,
        in_o(3) => r_s.s,
        in_o(4) => w_s.s,

        out_o => tx_o,
        out_i => tx_i
        );
  end block;

  decode: block is
    signal aw_s, w_s, b_s, ar_s, r_s : nsl_axi.axi4_stream.bus_t;
  begin

    dispatch: nsl_axi.stream_routing.axi4_stream_dispatch
      generic map(
        in_config_c => stream_config_c,
        out_config_c => common_config_c,
        destination_count_c => 5
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        out_o(0) => b_s.m,
        out_o(1) => aw_s.m,
        out_o(2) => ar_s.m,
        out_o(3) => r_s.m,
        out_o(4) => w_s.m,
        out_i(0) => b_s.s,
        out_i(1) => aw_s.s,
        out_i(2) => ar_s.s,
        out_i(3) => r_s.s,
        out_i(4) => w_s.s,

        in_o => rx_o,
        in_i => rx_i
        );

    aw_dec: block is
      constant packed_len: natural := address_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
      signal v: std_ulogic_vector(packed_len-1 downto 0);
    begin
      v <= transfer_to_vector(packed_cfg, packed_s.m, packed_len);
      packed_s.s <= accept(packed_cfg, is_ready(mm_config_c, master_i.aw));
      master_o.aw <= address_vector_unpack(
        mm_config_c, v,
        valid => is_valid(packed_cfg, packed_s.m));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => common_config_c,
          out_config_c => packed_cfg
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => aw_s.m,
          in_o => aw_s.s,

          out_o => packed_s.m,
          out_i => packed_s.s
          );
    end block;

    w_dec: block is
      constant packed_len: natural := write_data_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
      signal v: std_ulogic_vector(packed_len-1 downto 0);
    begin
      v <= transfer_to_vector(packed_cfg, packed_s.m, packed_len);
      packed_s.s <= accept(packed_cfg, is_ready(mm_config_c, master_i.w));
      master_o.w <= write_data_vector_unpack(
        mm_config_c, v,
        valid => is_valid(packed_cfg, packed_s.m),
        last => is_last(packed_cfg, packed_s.m));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => common_config_c,
          out_config_c => packed_cfg
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => w_s.m,
          in_o => w_s.s,

          out_o => packed_s.m,
          out_i => packed_s.s
          );
    end block;

    b_dec: block is
      constant packed_len: natural := write_response_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
      signal v: std_ulogic_vector(packed_len-1 downto 0);
    begin
      v <= transfer_to_vector(packed_cfg, packed_s.m, packed_len);
      packed_s.s <= accept(packed_cfg, is_ready(mm_config_c, slave_i.b));
      slave_o.b <= write_response_vector_unpack(
        mm_config_c, v,
        valid => is_valid(packed_cfg, packed_s.m));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => common_config_c,
          out_config_c => packed_cfg
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => b_s.m,
          in_o => b_s.s,

          out_o => packed_s.m,
          out_i => packed_s.s
          );
    end block;

    ar_dec: block is
      constant packed_len: natural := address_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
      signal v: std_ulogic_vector(packed_len-1 downto 0);
    begin
      v <= transfer_to_vector(packed_cfg, packed_s.m, packed_len);
      packed_s.s <= accept(packed_cfg, is_ready(mm_config_c, master_i.ar));
      master_o.ar <= address_vector_unpack(
        mm_config_c, v,
        valid => is_valid(packed_cfg, packed_s.m));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => common_config_c,
          out_config_c => packed_cfg
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => ar_s.m,
          in_o => ar_s.s,

          out_o => packed_s.m,
          out_i => packed_s.s
          );
    end block;

    r_dec: block is
      constant packed_len: natural := read_data_vector_length(mm_config_c);
      constant packed_cfg: nsl_axi.axi4_stream.config_t
        := aligned_cfg(common_config_c, packed_len);
      signal packed_s: nsl_axi.axi4_stream.bus_t;
      signal v: std_ulogic_vector(packed_len-1 downto 0);
    begin
      v <= transfer_to_vector(packed_cfg, packed_s.m, packed_len);
      packed_s.s <= accept(packed_cfg, is_ready(mm_config_c, slave_i.r));
      slave_o.r <= read_data_vector_unpack(
        mm_config_c, v,
        valid => is_valid(packed_cfg, packed_s.m));

      adapter: nsl_axi.axi4_stream.axi4_stream_width_adapter
        generic map(
          in_config_c => common_config_c,
          out_config_c => packed_cfg
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => r_s.m,
          in_o => r_s.s,

          out_o => packed_s.m,
          out_i => packed_s.s
          );
    end block;
  end block;
  
end architecture;
