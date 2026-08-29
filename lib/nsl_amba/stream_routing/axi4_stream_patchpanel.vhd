library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_math;
use nsl_amba.axi4_stream.all;
use nsl_math.arith.all;

entity axi4_stream_patchpanel is
  generic(
    config_c : nsl_amba.axi4_stream.config_t;
    regmap_config_c : nsl_amba.axi4_mm.config_t;
    source_count_c : positive;
    destination_count_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in nsl_amba.axi4_stream.master_vector(0 to source_count_c-1);
    in_o : out nsl_amba.axi4_stream.slave_vector(0 to source_count_c-1);

    out_o : out nsl_amba.axi4_stream.master_vector(0 to destination_count_c-1);
    out_i : in nsl_amba.axi4_stream.slave_vector(0 to destination_count_c-1);

    regmap_i : in nsl_amba.axi4_mm.master_t;
    regmap_o : in nsl_amba.axi4_mm.slave_t
    );
end entity;

architecture beh of axi4_stream_patchpanel is

  constant reg_count_c : natural := align_up(destination_count_c);
  signal reg_no_s: natural range 0 to reg_count_c-1;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s, r_strobe_s : std_ulogic;

  subtype source_index_t is integer range -1 to source_count_c-1;

  type dest_context_t is
  record
    next_source, source : source_index_t;
    busy: boolean;
    active: boolean;
  end record;

  type dest_context_vector is array (integer range 0 to destination_count_c-1) of dest_context_t;
  
  type regs_t is
  record
    dest: dest_context_vector;
  end record;

  signal r, rin: regs_t;
  
begin

  regmap: nsl_amba.axi4_mm.axi4_mm_lite_regmap
    generic map(
      config_c => mm_config_c,
      reg_count_l2_c => log2(reg_count_c)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => mm_i,
      axi_o => mm_o,

      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s,
      r_strobe_o => r_strobe_s
      );

  r_value: process(r, reg_no_s) is
  begin
    r_value_s <= (others => '-');

    if reg_no_s < destination_count_c then
      r_value_s <= r.next_source_index(reg_no_s);
    end if;
  end process;
  
  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.next_source_index <= (others => -1);
      r.source_index <= (others => -1);
      r.busy_vector <= (others => false);
    end if;
  end process;

  transition: process(r, in_i, out_i, w_strobe_s, w_value_s, reg_no_s)
    variable source: source_index_t;
  begin
    rin <= r;

    if w_strobe_s = '1' then
      if r
    end if;
    
    for dest in out_i'range
    loop
      source := r.source_index(dest);

      if source < 0 then
        rin.source_index(dest) := r.next_source_index;
      elsif r.busy(dest) then
        if is_valid(config_c, in_i(source))
          and is_last(config_c, in_i(source))
          and is_ready(config_c, out_i(dest)) then
          rin.busy(dest) := false;
        end if;
      else
        if is_valid(config_c, in_i(source)) then
          rin.busy(dest) := true;
        end if;
      end if;
    end loop;
  end process;

  mux: process(r, in_i, out_i)
  begin
    for i in out_o'range
    loop
      out_o(i) <= transfer(out_config_c, in_config_c, in_i);

      if i /= r.elected or r.state /= ST_FORWARD then
        out_o(i).valid <= '0';
      end if;
    end loop;

    in_o <= out_i(r.elected);

    if r.state /= ST_FORWARD then
      in_o.ready <= '0';
    end if;
  end process;

end architecture;
