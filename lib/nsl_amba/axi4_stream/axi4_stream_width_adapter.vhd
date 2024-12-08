library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, work, nsl_data;
use work.axi4_stream.all;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

entity axi4_stream_width_adapter is
  generic(
    in_config_c : config_t;
    out_config_c : config_t
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

  assert in_config_c.user_width = out_config_c.user_width
    report "In/out user widths do not match"
    severity failure;

  assert in_config_c.id_width = out_config_c.id_width
    report "In/out id widths do not match"
    severity failure;

  assert in_config_c.dest_width = out_config_c.dest_width
    report "In/out dest widths do not match"
    severity failure;

  assert in_config_c.has_ready
    report "Must work with back pressure"
    severity failure;

end entity;

architecture beh of axi4_stream_width_adapter is
  
begin

  widths_match: if in_config_c.data_width = out_config_c.data_width
  generate
    out_o <= in_i;
    in_o <= out_i;

    assert in_config_c.has_keep = out_config_c.has_keep
      report "In/out keep do not match"
      severity failure;

    assert in_config_c.has_strobe = out_config_c.has_strobe
      report "In/out strobe do not match"
      severity failure;

    assert in_config_c.has_last = out_config_c.has_last
      report "In/out last do not match"
      severity failure;
  end generate;

  widener: if in_config_c.data_width < out_config_c.data_width
  generate

    constant data_zero_in_c : byte_string(0 to in_config_c.data_width-1) := (others => x"00");
    constant en_zero_in_c : std_ulogic_vector(0 to in_config_c.data_width-1) := (others => '0');
    
    constant part_count_c : integer := out_config_c.data_width / in_config_c.data_width;

    type state_t is (
      ST_RESET,
      ST_FORWARD,
      ST_PAD
      );
    
    type regs_t is
    record
      state: state_t;
      bytes : byte_string(0 to out_config_c.data_width-1);
      keep : std_ulogic_vector(0 to out_config_c.data_width-1);
      strobe : std_ulogic_vector(0 to out_config_c.data_width-1);
      filled : natural range 0 to part_count_c;
      post: master_t;
    end record;

    signal r, rin : regs_t;

  begin

    reg: process (clock_i, reset_n_i)
    begin
      if clock_i'event and clock_i = '1' then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process reg;

    process (r, in_i, out_i)
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_FORWARD;
          rin.filled <= 0;
          rin.post.valid <= '0';

        when ST_FORWARD =>
          if (r.filled < part_count_c - 1 or not is_valid(out_config_c, r.post)) and is_valid(in_config_c, in_i) then
            rin.bytes <= r.bytes(in_config_c.data_width to out_config_c.data_width-1) & bytes(in_config_c, in_i);
            rin.keep <= r.keep(in_config_c.data_width to out_config_c.data_width-1) & keep(in_config_c, in_i);
            rin.strobe <= r.strobe(in_config_c.data_width to out_config_c.data_width-1) & strobe(in_config_c, in_i);
            rin.filled <= r.filled + 1;

            if r.filled = part_count_c - 1 then
              rin.filled <= 0;
            end if;

            if r.filled = part_count_c - 1 or is_last(in_config_c, in_i) then  
              rin.post <= transfer(out_config_c,
                                   bytes => r.bytes(in_config_c.data_width to out_config_c.data_width-1) & bytes(in_config_c, in_i),
                                   strobe => r.strobe(in_config_c.data_width to out_config_c.data_width-1) & strobe(in_config_c, in_i),
                                   keep => r.keep(in_config_c.data_width to out_config_c.data_width-1) & keep(in_config_c, in_i),
                                   id => id(in_config_c, in_i),
                                   user => user(in_config_c, in_i),
                                   dest => dest(in_config_c, in_i),
                                   valid => r.filled = part_count_c - 1,
                                   last => is_last(in_config_c, in_i));
            end if;
            
            if is_last(in_config_c, in_i) and r.filled /= part_count_c-1 then
              rin.state <= ST_PAD;
            end if;
          end if;

        when ST_PAD =>
          if (r.filled < part_count_c - 1 or not is_valid(out_config_c, r.post)) then
            rin.bytes <= r.bytes(in_config_c.data_width to out_config_c.data_width-1) & data_zero_in_c;
            rin.keep <= r.keep(in_config_c.data_width to out_config_c.data_width-1) & en_zero_in_c;
            rin.strobe <= r.strobe(in_config_c.data_width to out_config_c.data_width-1) & en_zero_in_c;
            rin.filled <= r.filled + 1;

            if r.filled = part_count_c - 1 then
              rin.filled <= 0;
              rin.state <= ST_FORWARD;
              rin.post <= transfer(out_config_c,
                                   bytes => r.bytes(in_config_c.data_width to out_config_c.data_width-1) & data_zero_in_c,
                                   strobe => r.strobe(in_config_c.data_width to out_config_c.data_width-1) & en_zero_in_c,
                                   keep => r.keep(in_config_c.data_width to out_config_c.data_width-1) & en_zero_in_c,
                                   id => id(out_config_c, r.post),
                                   user => user(out_config_c, r.post),
                                   dest => dest(out_config_c, r.post),
                                   valid => true,
                                   last => true);
            end if;
          end if;
      end case;

      if is_ready(out_config_c, out_i) and is_valid(out_config_c, r.post) then
        rin.post.valid <= '0';
      end if;
    end process;
    
    out_o <= r.post;
    in_o <= accept(in_config_c,
                   (r.filled < part_count_c - 1 or not is_valid(out_config_c, r.post))
                   and r.state = ST_FORWARD);

    assert out_config_c.data_width mod in_config_c.data_width = 0
      report "Bad width ratio"
      severity failure;

    assert out_config_c.has_keep or out_config_c.has_strobe or not in_config_c.has_last
      report "Short frames will contain unmasked padding"
      severity warning;

    assert out_config_c.has_keep or not in_config_c.has_last
      report "Short frames will contain padding with keep"
      severity warning;
  end generate;

  narrower: if in_config_c.data_width > out_config_c.data_width
  generate

    constant part_count_c : integer := in_config_c.data_width / out_config_c.data_width;
    constant no_other_useful_c : std_logic_vector(0 to part_count_c-1) := (0 => '-', others => '0');
    
    type regs_t is
    record
      pre: master_t;
      cur: master_t;
      part_useful: std_logic_vector(0 to part_count_c-1);
    end record;

    signal r, rin : regs_t;

  begin

    reg: process (clock_i, reset_n_i)
    begin
      if clock_i'event and clock_i = '1' then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.pre.valid <= '0';
        r.cur.valid <= '0';
        r.part_useful <= (others => '0');
      end if;
    end process reg;

    process (r, in_i, out_i)
      variable k: std_ulogic_vector(0 to in_config_c.data_width-1);
      variable more_useful: boolean;
    begin
      rin <= r;

      more_useful := not std_match(r.part_useful, no_other_useful_c);
      
      if is_valid(in_config_c, in_i) and not is_valid(in_config_c, r.pre) then
        rin.pre <= in_i;
      end if;

      if is_valid(in_config_c, r.cur) and is_ready(out_config_c, out_i) then
        if more_useful then
          rin.cur <= shift_low(in_config_c, r.cur, out_config_c.data_width);
          rin.part_useful <= r.part_useful(1 to part_count_c-1) & '0';
        else
          rin.cur.valid <= '0';
        end if;
      end if;

      if (not is_valid(in_config_c, r.cur)
          or (not more_useful and is_ready(out_config_c, out_i))) then
        if is_valid(in_config_c, r.pre) then
          rin.cur <= r.pre;
          rin.pre.valid <= '0';

          k := keep(in_config_c, r.pre);
          for part in 0 to part_count_c-1
          loop
            rin.part_useful(part) <= or_reduce(k(part * out_config_c.data_width to (part+1) * out_config_c.data_width - 1));
          end loop;
        else
          rin.cur.valid <= '0';
        end if;
      end if;
    end process;

    moore: process(r) is
      variable more_useful : boolean;
      variable s: std_ulogic_vector(0 to in_config_c.data_width-1);
      variable k: std_ulogic_vector(0 to in_config_c.data_width-1);
    begin
      more_useful := not std_match(r.part_useful, no_other_useful_c);

      s := strobe(in_config_c, r.cur);
      k := keep(in_config_c, r.cur);
      
      out_o <= transfer(out_config_c,
                        bytes => r.cur.data(0 to out_config_c.data_width-1),
                        strobe => s(0 to out_config_c.data_width-1),
                        keep => k(0 to out_config_c.data_width-1),
                        id => id(in_config_c, r.cur),
                        user => user(in_config_c, r.cur),
                        dest => dest(in_config_c, r.cur),
                        valid => is_valid(in_config_c, r.cur) and r.part_useful(0) = '1',
                        last => is_last(in_config_c, r.cur) and not more_useful);
    
      in_o <= accept(in_config_c, r.pre.valid = '0');
    end process;

    assert in_config_c.data_width mod out_config_c.data_width = 0
      report "Bad width ratio"
      severity failure;

    assert out_config_c.has_keep or out_config_c.has_strobe or not in_config_c.has_last
      report "Short frames will contain unmasked padding"
      severity warning;

    assert out_config_c.has_keep or not in_config_c.has_last
      report "Short frames will contain padding with keep"
      severity warning;

    assert in_config_c.data_width mod out_config_c.data_width = 0
      report "Bad width ratio"
      severity failure;
  end generate;

end architecture;
