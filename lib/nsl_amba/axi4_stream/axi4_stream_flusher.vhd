library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, work, nsl_data;
use work.axi4_stream.all;
use nsl_logic.bool.all;
use nsl_data.endian.all;

entity axi4_stream_flusher is
  generic(
    in_config_c : config_t;
    out_config_c : config_t;
    max_packet_length_size_l2_c : natural;
    max_idle_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    max_packet_length_m1_i : in unsigned(max_packet_length_size_l2_c-1 downto 0) := (others => '1');

    out_o : out master_t;
    out_i : in slave_t
    );
begin

  assert in_config_c.data_width = out_config_c.data_width
    report "In/out data widths do not match"
    severity failure;

  assert in_config_c.user_width = out_config_c.user_width
    report "In/out user widths do not match"
    severity failure;

  assert in_config_c.id_width = out_config_c.id_width
    report "In/out id widths do not match"
    severity failure;

  assert in_config_c.dest_width = out_config_c.dest_width
    report "In/out dest widths do not match"
    severity failure;

  assert in_config_c.has_keep = out_config_c.has_keep
    report "In/out keep do not match"
    severity failure;

  assert in_config_c.has_strobe = out_config_c.has_strobe
    report "In/out strobe do not match"
    severity failure;

  assert not in_config_c.has_last
    report "In must not have last"
    severity failure;

  assert out_config_c.has_last
    report "Out must have last"
    severity failure;

end entity;

architecture beh of axi4_stream_flusher is

  type fifo_t is array(integer range <>) of master_t;
  constant fifo_depth_c : natural := 3;

  type in_state_t is (
    IN_RESET,
    IN_FORWARD,
    IN_END
    );
  type out_state_t is (
    OUT_RESET,
    OUT_FORWARD,
    OUT_END
    );
  
  type regs_t is
  record
    in_state: in_state_t;
    out_state: out_state_t;
    fifo_fillness: natural range 0 to fifo_depth_c;
    fifo: fifo_t(0 to fifo_depth_c-1);
    beats_to_go : unsigned(max_packet_length_size_l2_c-1 downto 0);
    timeout: integer range 0 to max_idle_c-1;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.in_state <= IN_RESET;
      r.out_state <= OUT_RESET;
      r.fifo_fillness <= 0;
    end if;
  end process;

  transition: process(r, in_i, out_i, max_packet_length_m1_i) is
    variable fifo_put, fifo_get : boolean;
  begin
    rin <= r;

    fifo_put := false;
    fifo_get := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_FORWARD;
        rin.beats_to_go <= max_packet_length_m1_i;
        rin.timeout <= max_idle_c-1;

      when IN_FORWARD =>
        if r.fifo_fillness < fifo_depth_c and is_valid(in_config_c, in_i) then
          fifo_put := true;

          if max_packet_length_size_l2_c /= 0 then
            if r.beats_to_go /= 0 then
              rin.beats_to_go <= r.beats_to_go - 1;
            else
              rin.in_state <= IN_END;
            end if;
          end if;
        end if;

        if r.fifo_fillness = 1 and not is_valid(in_config_c, in_i) then
          if r.timeout /= 0 then
            rin.timeout <= r.timeout - 1;
          else
            rin.in_state <= IN_END;
          end if;
        else
          rin.timeout <= max_idle_c-1;
        end if;

      when IN_END =>
        if r.out_state = OUT_END
          and (r.fifo_fillness = 0 or (r.fifo_fillness = 1 and is_ready(out_config_c, out_i))) then
          rin.in_state <= IN_FORWARD;
          rin.beats_to_go <= max_packet_length_m1_i;
          rin.timeout <= max_idle_c-1;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_FORWARD;

      when OUT_FORWARD =>
        if r.fifo_fillness > 1 and is_ready(out_config_c, out_i) then
          fifo_get := true;
        end if;

        if r.in_state = IN_END then
          rin.out_state <= OUT_END;
        end if;
        
      when OUT_END =>
        if r.fifo_fillness > 0 and is_ready(out_config_c, out_i) then
          fifo_get := true;
        end if;

        if r.fifo_fillness = 0 or (r.fifo_fillness = 1 and is_ready(out_config_c, out_i)) then
          rin.out_state <= OUT_FORWARD;
        end if;
    end case;

    if fifo_put and fifo_get then
      rin.fifo(0 to rin.fifo'right-1) <= r.fifo(1 to r.fifo'right);
      rin.fifo(r.fifo_fillness-1) <= in_i;
    elsif fifo_put then
      rin.fifo(r.fifo_fillness) <= in_i;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_get then
      rin.fifo(0 to rin.fifo'right-1) <= r.fifo(1 to r.fifo'right);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
    variable a, v, l : boolean;
  begin

    case r.in_state is
      when IN_RESET | IN_END =>
        a := false;

      when IN_FORWARD =>
        a := r.fifo_fillness < fifo_depth_c;
    end case;

    case r.out_state is
      when OUT_RESET =>
        v := false;
        l := false;

      when OUT_FORWARD =>
        v := r.fifo_fillness > 1;
        l := false;

      when OUT_END =>
        v := r.fifo_fillness > 0;
        l := r.fifo_fillness <= 1;
    end case;
    
    out_o <= transfer(out_config_c,
                      bytes => bytes(in_config_c, r.fifo(0)),
                      strobe => strobe(in_config_c, r.fifo(0)),
                      keep => keep(in_config_c, r.fifo(0)),
                      id => id(in_config_c, r.fifo(0)),
                      user => user(in_config_c, r.fifo(0)),
                      dest => dest(in_config_c, r.fifo(0)),
                      valid => v,
                      last => l);

    in_o <= accept(in_config_c,
                   ready => a);
    
  end process;
end architecture;
