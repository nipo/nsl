library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

entity axi4_stream_sized_to_framed is
  generic(
    in_config_c : config_t;
    out_config_c : config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    invalid_o : out std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture rtl of axi4_stream_sized_to_framed is

  type state_t is (
    STATE_RESET,
    STATE_INVAL,
    STATE_SIZE_L,
    STATE_SIZE_H,
    STATE_DATA
    );

  type regs_t is record
    state: state_t;
    count: unsigned(15 downto 0);
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
        rin.state <= STATE_SIZE_L;

      when STATE_INVAL =>
        if is_valid(in_config_c, in_i) and in_byte = x"00" then
          rin.state <= STATE_RESET;
        end if;

      when STATE_SIZE_L =>
        if is_valid(in_config_c, in_i) then
          rin.count(7 downto 0) <= unsigned(in_byte);
          rin.state <= STATE_SIZE_H;
        end if;

      when STATE_SIZE_H =>
        if is_valid(in_config_c, in_i) then
          rin.count(15 downto 8) <= unsigned(in_byte);
          if r.count(7 downto 0) = x"FF" and in_byte = x"FF" then
            rin.state <= STATE_INVAL;
          else
            rin.state <= STATE_DATA;
          end if;
        end if;

      when STATE_DATA =>
        if is_valid(in_config_c, in_i) and is_ready(out_config_c, out_i) then
          rin.count <= r.count - 1;
          if r.count = 0 then
            rin.state <= STATE_SIZE_L;
          end if;
        end if;
    end case;
  end process;

  mealy: process(r, in_i, out_i) is
  begin
    out_o <= transfer_defaults(out_config_c);
    in_o <= accept(in_config_c, false);
    invalid_o <= '0';

    case r.state is
      when STATE_INVAL =>
        in_o <= accept(in_config_c, true);
        invalid_o <= '1';

      when STATE_RESET =>
        invalid_o <= '1';

      when STATE_SIZE_L | STATE_SIZE_H =>
        in_o <= accept(in_config_c, true);

      when STATE_DATA =>
        out_o <= transfer(out_config_c,
                         bytes => bytes(in_config_c, in_i),
                         valid => is_valid(in_config_c, in_i),
                         last => r.count = 0);
        in_o <= out_i;
    end case;
  end process;

end architecture;
