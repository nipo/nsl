library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity vdma_gearbox is
  generic(
    in_config_c : nsl_amba.axi4_stream.config_t;
    out_config_c : nsl_amba.axi4_stream.config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in nsl_amba.axi4_stream.master_t;
    in_o : out nsl_amba.axi4_stream.slave_t;

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of vdma_gearbox is

  constant iw_c : positive := in_config_c.data_width;
  constant ow_c : positive := out_config_c.data_width;
  constant uw_c : natural := nsl_math.arith.min(in_config_c.user_width, out_config_c.user_width);

begin

  assert in_config_c.has_last and out_config_c.has_last
    report "Gearbox works on packets, both sides need TLAST"
    severity failure;

  same_width: if iw_c = ow_c
  generate
    out_o <= transfer(out_config_c, in_config_c, in_i);
    in_o <= out_i;
  end generate;

  gearbox: if iw_c /= ow_c
  generate
    -- Room for one input beat on top of up to 2*ow_c-1 pending bytes,
    -- which is the most that can be left behind by a beat that
    -- could not be emitted.
    constant capacity_c : positive := iw_c + 2 * ow_c - 1;
    constant accept_max_c : natural := capacity_c - iw_c;

    subtype user_t is std_ulogic_vector(uw_c downto 0);

    type regs_t is
    record
      buf : byte_string(0 to capacity_c-1);
      count : natural range 0 to capacity_c;
      tail : boolean;
      first_out : boolean;
      head_user, tail_user : user_t;
      first_in : boolean;
    end record;

    signal r, rin : regs_t;

    function lead_count(k : std_ulogic_vector) return natural
    is
      variable ret : natural range 0 to k'length := 0;
      variable kk : std_ulogic_vector(0 to k'length-1) := k;
    begin
      for i in kk'range
      loop
        if kk(i) = '1' then
          ret := i + 1;
        end if;
      end loop;
      return ret;
    end function;

    function in_user(m : master_t) return user_t
    is
      variable ret : user_t := (others => '0');
    begin
      if uw_c /= 0 then
        ret(uw_c-1 downto 0) := m.user(uw_c-1 downto 0);
      end if;
      return ret;
    end function;

  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.count <= 0;
        r.tail <= false;
        r.first_out <= true;
        r.first_in <= true;
      end if;
    end process;

    transition: process(r, in_i, out_i) is
      variable emit, take : boolean;
      variable kept : std_ulogic_vector(0 to iw_c-1);
      variable n_in : natural range 0 to iw_c;
      variable base : natural range 0 to capacity_c;
      variable data : byte_string(0 to iw_c-1);
    begin
      rin <= r;

      emit := (r.count >= ow_c or r.tail) and is_ready(out_config_c, out_i);
      take := r.count <= accept_max_c and not r.tail and is_valid(in_config_c, in_i);

      kept := keep(in_config_c, in_i);
      if in_config_c.has_keep then
        n_in := lead_count(kept);
      else
        n_in := iw_c;
      end if;
      data := bytes(in_config_c, in_i);

      if emit then
        if r.count < ow_c then
          base := 0;
        else
          base := r.count - ow_c;
        end if;
      else
        base := r.count;
      end if;

      for j in 0 to capacity_c-1
      loop
        if j < base then
          if emit then
            if j + ow_c < capacity_c then
              rin.buf(j) <= r.buf(j + ow_c);
            end if;
          end if;
        else
          rin.buf(j) <= (others => '-');
          if take then
            for i in 0 to iw_c-1
            loop
              if j = base + i then
                rin.buf(j) <= data(i);
              end if;
            end loop;
          end if;
        end if;
      end loop;

      if take then
        rin.count <= base + n_in;
      else
        rin.count <= base;
      end if;

      if emit then
        rin.first_out <= false;
        if r.tail and r.count <= ow_c then
          rin.tail <= false;
          rin.first_out <= true;
          rin.count <= 0;
        end if;
      end if;

      if take then
        rin.first_in <= false;
        if r.first_in then
          rin.head_user <= in_user(in_i);
        end if;
        if is_last(in_config_c, in_i) then
          rin.tail <= true;
          rin.tail_user <= in_user(in_i);
          rin.first_in <= true;
        end if;
      end if;
    end process;

    moore: process(r) is
      variable k : std_ulogic_vector(0 to ow_c-1);
      variable u : user_t;
      variable last : boolean;
    begin
      last := r.tail and r.count <= ow_c;

      for i in k'range
      loop
        k(i) := to_logic(i < r.count);
      end loop;

      u := (others => '0');
      if r.first_out then
        u := u or r.head_user;
      end if;
      if last then
        u := u or r.tail_user;
      end if;

      if uw_c /= 0 then
        out_o <= transfer(out_config_c,
                          bytes => r.buf(0 to ow_c-1),
                          keep => k,
                          user => u(uw_c-1 downto 0),
                          valid => r.count >= ow_c or r.tail,
                          last => last);
      else
        out_o <= transfer(out_config_c,
                          bytes => r.buf(0 to ow_c-1),
                          keep => k,
                          valid => r.count >= ow_c or r.tail,
                          last => last);
      end if;

      in_o <= accept(in_config_c, r.count <= accept_max_c and not r.tail);
    end process;

    -- pragma translate_off
    keepless_check: process(clock_i) is
    begin
      if rising_edge(clock_i) then
        if not out_config_c.has_keep
          and r.tail and r.count <= ow_c and r.count /= ow_c
          and is_ready(out_config_c, out_i) then
          assert false
            report "Packet length is not a multiple of the output beat width, but output has no TKEEP"
            severity failure;
        end if;
      end if;
    end process;
    -- pragma translate_on

  end generate;

end architecture;
