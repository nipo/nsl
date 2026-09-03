library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_time, nsl_math, work;
use nsl_amba.axi4_mm.all;
use nsl_time.timestamp.all;
use nsl_math.fixed.all;

entity phc_main is
  generic(
    increment_msb: integer := 7;
    increment_lsb: integer := -15;
    config_c : config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in master_t;
    axi_o : out slave_t;

    timestamp_o : out timestamp_t
    );
end entity;

architecture rtl of phc_main is

  constant reg_sub_ns_inc_c : integer := 0;
  constant reg_ns_adj_c : integer := 1;
  constant reg_timestamp_sec_c : integer := 2;
  constant reg_timestamp_ns_c : integer := 3;
  
  signal timestamp_s : timestamp_t;

  signal reg_no_s: natural range 0 to 3;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s, r_strobe_s : std_ulogic;

  type regs_t is
  record
    sub_ns_inc: ufixed(increment_msb downto increment_lsb);
    ns_adj: timestamp_nanosecond_offset_t;
    ns_adj_strobe, axi_timestamp_strobe: std_ulogic;
    axi_timestamp: timestamp_t;
    read_ns_cap: timestamp_nanosecond_t;
  end record;

  signal r, rin: regs_t;
  
begin

  regmap: nsl_amba.axi4_mm.axi4_mm_lite_regmap
    generic map(
      config_c => config_c,
      reg_count_l2_c => 2
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => axi_i,
      axi_o => axi_o,
      
      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s,
      r_strobe_o => r_strobe_s
      );

  regs: process(aclk, aresetn) is
  begin
    if rising_edge(aclk) then
      r <= rin;
    end if;

    if aresetn = '0' then
      r.sub_ns_inc <= (others => '0');
      r.ns_adj <= (others => '0');
      r.axi_timestamp.second <= (others => '0');
      r.axi_timestamp.nanosecond <= (others => '0');
      r.read_ns_cap <= (others => '0');
      r.ns_adj_strobe <= '0';
      r.axi_timestamp_strobe <= '0';
    end if;
  end process;

  transition: process(r, reg_no_s, w_value_s, w_strobe_s, r_strobe_s) is
  begin
    rin <= r;

    rin.ns_adj_strobe <= '0';
    rin.axi_timestamp_strobe <= '0';
    
    if w_strobe_s = '1' then
      case reg_no_s is
        when reg_sub_ns_inc_c =>
          rin.sub_ns_inc <= ufixed(w_value_s(rin.sub_ns_inc'left+16 downto rin.sub_ns_inc'right+16));

        when reg_ns_adj_c =>
          rin.ns_adj <= signed(w_value_s(rin.ns_adj'range));
          rin.ns_adj_strobe <= '1';

        when reg_timestamp_sec_c =>
          rin.axi_timestamp.second <= w_value_s(rin.axi_timestamp.second'range);

        when reg_timestamp_ns_c =>
          rin.axi_timestamp.nanosecond <= w_value_s(rin.axi_timestamp.nanosecond'range);
          rin.axi_timestamp_strobe <= '1';

        when others =>
          null;
      end case;
    end if;

    if r_strobe_s = '1' and reg_no_s = reg_timestamp_sec_c then
      rin.read_ns_cap <= timestamp_s.nanosecond;
    end if;
  end process;

  mealy: process(r, timestamp_s, reg_no_s) is
  begin
    rin <= r;

    r_value_s <= (others => '0');
    
    case reg_no_s is
      when reg_sub_ns_inc_c =>
        r_value_s(rin.sub_ns_inc'left+16 downto rin.sub_ns_inc'right+16) <= to_unsigned(r.sub_ns_inc);

      when reg_ns_adj_c =>
        null;

      when reg_timestamp_sec_c =>
        r_value_s(timestamp_s.second'range) <= unsigned(timestamp_s.second);

      when reg_timestamp_ns_c =>
        r_value_s(timestamp_s.nanosecond'range) <= unsigned(r.read_ns_cap);

      when others =>
        null;
    end case;
  end process;

  backend: nsl_time.clock.clock_adjustable
    port map(
      clock_i => aclk,
      reset_n_i => aresetn,

      sub_nanosecond_inc_i => r.sub_ns_inc,

      nanosecond_adj_i => r.ns_adj,
      nanosecond_adj_set_i => r.ns_adj_strobe,

      timestamp_i => r.axi_timestamp,
      timestamp_set_i => r.axi_timestamp_strobe,
      
      timestamp_o => timestamp_s
      );

  timestamp_o <= timestamp_s;

end architecture;
