library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.crc.all;

entity axi4_stream_crc_adder is
  generic(
    config_c : config_t;
    crc_c : crc_params_t
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

  assert not config_c.has_keep and not config_c.has_strobe
    report "This module does not handle sparse input stream"
    severity failure;

  assert (crc_byte_length(crc_c) mod config_c.data_width) = 0
    report "CRC should be an integer count of beats"
    severity failure;

end entity;

architecture beh of axi4_stream_crc_adder is

  constant buffer_config_c: buffer_config_t
    := buffer_config(config_c, crc_byte_length(crc_c));
  
  type state_t is (
    ST_RESET,
    ST_FORWARD,
    ST_CRC
    );
  
  type regs_t is
  record
    state: state_t;
    crc_buffer: buffer_t;
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
    variable cur_crc, next_crc: crc_state_t;
  begin
    rin <= r;

    cur_crc := crc_load(crc_c, bytes(buffer_config_c, r.crc_buffer));
    next_crc := crc_update(crc_c, cur_crc, bytes(config_c, in_i));

    case r.state is
      when ST_RESET =>
        rin.state <= ST_FORWARD;
        rin.crc_buffer <= reset(buffer_config_c, crc_spill(crc_c, crc_init(crc_c)));

      when ST_FORWARD =>
        if is_valid(config_c, in_i) and is_ready(config_c, out_i) then
          rin.crc_buffer <= reset(buffer_config_c, crc_spill(crc_c, next_crc));

          if is_last(config_c, in_i) then
            rin.state <= ST_CRC;
          end if;
        end if;

      when ST_CRC =>
        if is_ready(config_c, out_i) then
          rin.crc_buffer <= shift(buffer_config_c, r.crc_buffer);
          if is_last(buffer_config_c, r.crc_buffer) then
            rin.state <= ST_FORWARD;
            rin.crc_buffer <= reset(buffer_config_c, crc_spill(crc_c, crc_init(crc_c)));
          end if;
        end if;
    end case;
  end process;

  mealy: process(r, in_i, out_i) is
  begin
    case r.state is
      when ST_RESET =>
        out_o <= transfer_defaults(config_c);
        in_o <= accept(config_c, false);

      when ST_FORWARD =>
        out_o <= transfer(config_c, in_i, force_last => true, last => false);
        in_o <= out_i;

      when ST_CRC =>
        out_o <= next_beat(buffer_config_c, r.crc_buffer, last => true);
        in_o <= accept(config_c, false);
    end case;
  end process;

end architecture;
