library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4_stream_sized_framing_1b is
  generic(
    in_config_c     : config_t;
    out_config_c    : config_t;
    header_length_c : positive range 1 to 4 := 2;
    endian_c        : endian_t := ENDIAN_LITTLE
    );
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    invalid_o : out std_ulogic;

    in_i  : in  master_t;
    in_o  : out slave_t;

    out_o : out master_t;
    out_i : in  slave_t
    );
begin
  assert in_config_c.data_width = 1
    report "in_config_c data_width must be 1"
    severity failure;
  assert not in_config_c.has_last
    report "in_config_c must not have has_last"
    severity failure;
  assert out_config_c.data_width = 1
    report "out_config_c data_width must be 1"
    severity failure;
  assert out_config_c.has_last
    report "out_config_c must have has_last"
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
  assert in_config_c.has_strobe = out_config_c.has_strobe
    report "in/out has_strobe must match"
    severity failure;
end entity;

architecture rtl of axi4_stream_sized_framing_1b is

  type state_t is (
    STATE_RESET,
    STATE_INVAL,
    STATE_HEADER,
    STATE_DATA
    );

  type regs_t is record
    state      : state_t;
    count      : unsigned(header_length_c*8-1 downto 0);
    header_idx : natural range 0 to 3;
    all_ff     : boolean;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= STATE_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable in_byte : byte;
  begin
    rin <= r;

    in_byte := bytes(in_config_c, in_i)(0);

    case r.state is
      when STATE_RESET =>
        rin.state      <= STATE_HEADER;
        rin.header_idx <= 0;
        rin.all_ff     <= true;
        rin.count      <= (others => '0');

      when STATE_INVAL =>
        if is_valid(in_config_c, in_i) and in_byte = x"00" then
          rin.state <= STATE_RESET;
        end if;

      when STATE_HEADER =>
        if is_valid(in_config_c, in_i) then
          for byte_n in 0 to header_length_c - 1 loop
            if r.header_idx = byte_n then
              if endian_c = ENDIAN_LITTLE then
                rin.count(byte_n * 8 + 7 downto byte_n * 8)
                  <= unsigned(in_byte);
              else
                rin.count((header_length_c - 1 - byte_n) * 8 + 7
                           downto (header_length_c - 1 - byte_n) * 8)
                  <= unsigned(in_byte);
              end if;
            end if;
          end loop;

          if in_byte /= x"FF" then
            rin.all_ff <= false;
          end if;

          if r.header_idx = header_length_c - 1 then
            if r.all_ff and in_byte = x"FF" then
              rin.state <= STATE_INVAL;
            else
              rin.state <= STATE_DATA;
            end if;
            rin.header_idx <= 0;
          else
            rin.header_idx <= r.header_idx + 1;
          end if;
        end if;

      when STATE_DATA =>
        if is_valid(in_config_c, in_i) and is_ready(out_config_c, out_i) then
          rin.count <= r.count - 1;
          if r.count = 0 then
            rin.state  <= STATE_HEADER;
            rin.all_ff <= true;
          end if;
        end if;
    end case;
  end process;

  mealy: process(r, in_i, out_i) is
    variable out_v : master_t;
  begin
    out_o     <= transfer_defaults(out_config_c);
    in_o      <= accept(in_config_c, false);
    invalid_o <= '0';

    case r.state is
      when STATE_RESET =>
        invalid_o <= '1';

      when STATE_INVAL =>
        in_o      <= accept(in_config_c, true);
        invalid_o <= '1';

      when STATE_HEADER =>
        in_o <= accept(in_config_c, true);

      when STATE_DATA =>
        out_v := transfer(out_config_c, in_i,
                          force_last => true,
                          last => r.count = 0);
        out_o <= out_v;
        in_o  <= accept(in_config_c, is_ready(out_config_c, out_i));
    end case;
  end process;

end architecture;
