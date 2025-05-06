library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;

entity stupid_fifo is
  generic(
    config_c : config_t;
    depth_c : positive range 1 to positive'high
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of stupid_fifo is

  constant buf_cfg_c : buffer_config_t := buffer_config(config_c, depth_c * config_c.data_width);

  type state_t is (
    ST_RESET,
    ST_GET,
    ST_ALIGN,
    ST_PUT
    );
  
  type regs_t is
  record
    buf: buffer_t;
    last: boolean;
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
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_GET;
        rin.buf <= reset(buf_cfg_c);

      when ST_GET =>
        if is_valid(config_c, in_i) then
          rin.last <= is_last(config_c, in_i);
          rin.buf <= shift(buf_cfg_c, r.buf, in_i);

          if should_align(buf_cfg_c, r.buf, in_i) then
            rin.state <= ST_ALIGN;
          elsif is_last(buf_cfg_c, r.buf) then
            rin.state <= ST_PUT;
          end if;
        end if;

      when ST_ALIGN =>
        rin.buf <= realign(buf_cfg_c, r.buf);
        if is_last(buf_cfg_c, r.buf) then
          rin.state <= ST_PUT;
        end if;

      when ST_PUT =>
        if is_ready(config_c, out_i) then
          rin.buf <= shift(buf_cfg_c, r.buf);
          if is_last(buf_cfg_c, r.buf) then
            rin.state <= ST_GET;
            rin.buf <= reset(buf_cfg_c);
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    out_o <= transfer_defaults(config_c);
    in_o <= accept(config_c, false);

    case r.state is
      when ST_RESET | ST_ALIGN =>
        null;

      when ST_GET =>
        in_o <= accept(config_c, true);

      when ST_PUT =>
        out_o <= next_beat(buf_cfg_c, r.buf, last => r.last);
    end case;
  end process;
    
end architecture;
