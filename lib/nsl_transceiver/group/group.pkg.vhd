library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver;

-- Configuration for a transceiver group: a cluster of lanes sharing
-- PLLs, reference clock routing and a configuration interface, as
-- exposed by a vendor primitive. Vendor group entities consume these
-- types; this package does not declare a generic group component, as
-- group instances are vendor-specific by nature.
package group is

  constant max_lane_count_c : natural := 8;
  constant max_pll_count_c : natural := 4;
  constant max_ref_clock_count_c : natural := 4;
  constant max_user_clock_group_count_c : natural := max_lane_count_c;

  type pll_config_t is
  record
    enabled : boolean;
    ref_clock_index : natural;
    target_vco_mhz : natural;
  end record;

  type pll_config_vector is array (natural range <>) of pll_config_t;

  constant disabled_pll_c : pll_config_t := (
    enabled => false,
    ref_clock_index => 0,
    target_vco_mhz => 0
    );

  type config_t is
  record
    lane_count : natural range 0 to max_lane_count_c;
    pll_count : natural range 0 to max_pll_count_c;
    ref_clock_count : natural range 0 to max_ref_clock_count_c;
    user_clock_group_count : natural range 0 to max_user_clock_group_count_c;
    plls : pll_config_vector(0 to max_pll_count_c-1);
    lanes : nsl_transceiver.lane.config_vector(0 to max_lane_count_c-1);
  end record;

  function config(
    plls : pll_config_vector;
    lanes : nsl_transceiver.lane.config_vector;
    ref_clock_count : natural;
    user_clock_group_count : natural
    ) return config_t;

  -- Target-agnostic intra-config consistency check. A vendor group
  -- entity must additionally assert legality against its primitive
  -- (e.g. which PLL can drive which lane at which line rate) in its
  -- architecture body.
  function is_valid(cfg : config_t) return boolean;

end package group;

package body group is

  function config(
    plls : pll_config_vector;
    lanes : nsl_transceiver.lane.config_vector;
    ref_clock_count : natural;
    user_clock_group_count : natural
    ) return config_t
  is
    variable ret : config_t;
  begin
    ret.lane_count := lanes'length;
    ret.pll_count := plls'length;
    ret.ref_clock_count := ref_clock_count;
    ret.user_clock_group_count := user_clock_group_count;
    ret.plls := (others => disabled_pll_c);
    ret.lanes := (others => nsl_transceiver.lane.disabled_lane_c);
    for i in 0 to plls'length-1 loop
      ret.plls(i) := plls(plls'low + i);
    end loop;
    for i in 0 to lanes'length-1 loop
      ret.lanes(i) := lanes(lanes'low + i);
    end loop;
    return ret;
  end function;

  function is_valid(cfg : config_t) return boolean
  is
  begin
    for i in 0 to cfg.lane_count-1 loop
      if not cfg.lanes(i).enabled then
        next;
      end if;
      if cfg.lanes(i).pll_index >= cfg.pll_count then
        return false;
      end if;
      if not cfg.plls(cfg.lanes(i).pll_index).enabled then
        return false;
      end if;
      if cfg.lanes(i).ref_clock_index >= cfg.ref_clock_count then
        return false;
      end if;
      if cfg.lanes(i).user_clock_group_index >= cfg.user_clock_group_count then
        return false;
      end if;
    end loop;
    for i in 0 to cfg.pll_count-1 loop
      if not cfg.plls(i).enabled then
        next;
      end if;
      if cfg.plls(i).ref_clock_index >= cfg.ref_clock_count then
        return false;
      end if;
    end loop;
    return true;
  end function;

end package body group;
