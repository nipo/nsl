library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;

entity axi4_stream_meta_packer is
  generic(
    in_config_c : config_t;
    out_config_c : config_t;
    meta_elements_c : string := "iou";
    endian_c : endian_t := ENDIAN_BIG
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );

begin

  assert in_config_c.data_width = out_config_c.data_width
    report "Input and output data widths must be equal"
    severity failure;

  assert in_config_c.has_last
    report "Input configuration must have last signal"
    severity failure;

  assert out_config_c.has_last
    report "Output configuration must have last signal"
    severity failure;

  assert in_config_c.has_ready
    report "Input configuration must have ready signal"
    severity failure;

  assert out_config_c.has_ready
    report "Output configuration must have ready signal"
    severity failure;

end entity;

architecture beh of axi4_stream_meta_packer is

  constant meta_bits_c : natural := vector_length(in_config_c, meta_elements_c);
  constant meta_bytes_c : natural := (meta_bits_c + 7) / 8;
  constant padding_bits_c : natural := meta_bytes_c * 8 - meta_bits_c;

  constant meta_config_c : buffer_config_t := buffer_config(out_config_c, meta_bytes_c);

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_META,
    ST_DATA
    );

  type regs_t is
  record
    state: state_t;
    meta: buffer_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    constant padding_c : std_ulogic_vector(padding_bits_c-1 downto 0) := (others => '0');
    variable meta_vector : std_ulogic_vector(meta_bits_c-1 downto 0);
    variable meta_padded : std_ulogic_vector(meta_bytes_c * 8 - 1 downto 0);
    variable meta_bytes : byte_string(0 to meta_bytes_c-1);
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if is_valid(in_config_c, in_i) then
          -- Sample metadata from first beat (master holds it stable)
          if meta_bits_c > 0 then
            meta_vector := vector_pack(in_config_c, meta_elements_c, in_i);
            meta_padded := padding_c & meta_vector;
            meta_bytes := to_endian(unsigned(meta_padded), endian_c);
            rin.meta <= reset(meta_config_c, meta_bytes);
            rin.state <= ST_META;
          else
            -- No metadata to pack, go straight to data
            rin.state <= ST_DATA;
          end if;
        end if;

      when ST_META =>
        if is_ready(out_config_c, out_i) then
          rin.meta <= shift(meta_config_c, r.meta);
          if is_last(meta_config_c, r.meta) then
            rin.state <= ST_DATA;
          end if;
        end if;

      when ST_DATA =>
        if is_valid(in_config_c, in_i) and is_ready(out_config_c, out_i) and is_last(in_config_c, in_i) then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  mealy: process(r, in_i, out_i) is
  begin
    in_o <= accept(in_config_c, false);
    out_o <= transfer_defaults(out_config_c);

    case r.state is
      when ST_RESET =>
        null;

      when ST_IDLE =>
        null;

      when ST_META =>
        -- Send metadata prefix
        out_o <= next_beat(meta_config_c, r.meta, last => false);

      when ST_DATA =>
        -- Forward data beats
        out_o <= transfer(out_config_c, in_config_c, in_i);
        in_o <= out_i;
    end case;
  end process;

end architecture;
