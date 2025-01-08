library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity axi4_stream_header_inserter is
  generic(
    config_c : nsl_amba.axi4_stream.config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    header_i : in byte_string;
    header_strobe_o : out std_ulogic;
    in_i : in nsl_amba.axi4_stream.master_t;
    in_o : out nsl_amba.axi4_stream.slave_t;

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of axi4_stream_header_inserter is

  constant header_config_c : buffer_config_t := buffer_config(config_c, header_i'length);

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_HEADER,
    ST_DATA
    );
  
  type regs_t is
  record
    header: buffer_t;
    state: state_t;
  end record;
  
  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= st_reset;
    end if;
  end process;

  transition: process(r, in_i, header_i, out_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if is_valid(config_c, in_i) then
          rin.header <= reset(header_config_c, header_i);
          rin.state <= ST_HEADER;
        end if;

      when ST_HEADER =>
        if is_ready(config_c, out_i) then
          rin.header <= shift(header_config_c, r.header);
          if is_last(header_config_c, r.header) then
            rin.state <= ST_DATA;
          end if;
        end if;

      when ST_DATA =>
        if is_valid(config_c, in_i) and is_last(config_c, in_i) and is_ready(config_c, out_i) then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  mealy: process(r, in_i, out_i) is
  begin
    in_o <= accept(config_c, false);
    out_o <= transfer_defaults(config_c);
    header_strobe_o <= '0';

    case r.state is
      when ST_RESET =>
        null;

      when ST_IDLE =>
        header_strobe_o <= to_logic(is_valid(config_c, in_i));

      when ST_HEADER =>
        out_o <= next_beat(header_config_c, r.header, last => false);

      when ST_DATA =>
        out_o <= in_i;
        in_o <= out_i;
    end case;
  end process;
end architecture;

        
