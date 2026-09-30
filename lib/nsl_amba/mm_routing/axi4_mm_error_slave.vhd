library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_data.bytestream.all;

-- Error slave that responds with resp_c to all transactions.
entity axi4_mm_error_slave is
  generic(
    config_c : config_t;
    resp_c : resp_enum_t := RESP_DECERR
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in master_t;
    axi_o : out slave_t
    );
end entity;

architecture beh of axi4_mm_error_slave is

  type w_state_t is (
    ST_W_RESET,
    ST_W_IDLE,
    ST_W_DATA,
    ST_W_RESP
    );

  type r_state_t is (
    ST_R_RESET,
    ST_R_IDLE,
    ST_R_DATA
    );

  type regs_t is
  record
    w_state : w_state_t;
    w_id : std_ulogic_vector(config_c.id_width-1 downto 0);
    r_state : r_state_t;
    r_id : std_ulogic_vector(config_c.id_width-1 downto 0);
    r_len_m1 : unsigned(config_c.len_width-1 downto 0);
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.w_state <= ST_W_RESET;
      r.r_state <= ST_R_RESET;
    end if;
  end process;

  transition: process(r, axi_i)
  begin
    rin <= r;

    -- Write channel FSM
    case r.w_state is
      when ST_W_RESET =>
        rin.w_state <= ST_W_IDLE;

      when ST_W_IDLE =>
        if is_valid(config_c, axi_i.aw) then
          rin.w_state <= ST_W_DATA;
          rin.w_id <= id(config_c, axi_i.aw);
        end if;

      when ST_W_DATA =>
        if is_valid(config_c, axi_i.w) and is_last(config_c, axi_i.w) then
          rin.w_state <= ST_W_RESP;
        end if;

      when ST_W_RESP =>
        if is_ready(config_c, axi_i.b) then
          rin.w_state <= ST_W_IDLE;
        end if;
    end case;

    -- Read channel FSM
    case r.r_state is
      when ST_R_RESET =>
        rin.r_state <= ST_R_IDLE;

      when ST_R_IDLE =>
        if is_valid(config_c, axi_i.ar) then
          rin.r_state <= ST_R_DATA;
          rin.r_id <= id(config_c, axi_i.ar);
          rin.r_len_m1 <= length_m1(config_c, axi_i.ar, config_c.len_width);
        end if;

      when ST_R_DATA =>
        if is_ready(config_c, axi_i.r) then
          if config_c.len_width = 0 or r.r_len_m1 = 0 then
            rin.r_state <= ST_R_IDLE;
          else
            rin.r_len_m1 <= r.r_len_m1 - 1;
          end if;
        end if;
    end case;
  end process;

  outputs: process(r)
  begin
    axi_o.aw <= handshake_defaults(config_c);
    axi_o.w <= handshake_defaults(config_c);
    axi_o.b <= write_response_defaults(config_c);
    axi_o.ar <= handshake_defaults(config_c);
    axi_o.r <= read_data_defaults(config_c);

    -- Write channel outputs
    case r.w_state is
      when ST_W_RESET =>
        null;

      when ST_W_IDLE =>
        axi_o.aw <= accept(config_c, true);

      when ST_W_DATA =>
        axi_o.w <= accept(config_c, true);

      when ST_W_RESP =>
        axi_o.b <= write_response(config_c,
                                  id => r.w_id,
                                  resp => resp_c,
                                  valid => true);
    end case;

    -- Read channel outputs
    case r.r_state is
      when ST_R_RESET =>
        null;

      when ST_R_IDLE =>
        axi_o.ar <= accept(config_c, true);

      when ST_R_DATA =>
        axi_o.r <= read_data(config_c,
                             id => r.r_id,
                             bytes => null_byte_string,
                             resp => resp_c,
                             last => config_c.len_width = 0 or r.r_len_m1 = 0,
                             valid => true);
    end case;
  end process;

end architecture;
