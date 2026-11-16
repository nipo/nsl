from gbs.plugin.nsl.cdc.gowin import (GowinNetlist, explicit_constraints,
                                      wildcard_constraints)

NETLIST = r"""module sync (
  clock,
  q
)
;
input clock;
output q;
  DFFC \async_clr.tig_reg_clr_0_s0  (
    .Q(q),
    .D(VCC),
    .CLK(clock),
    .CLEAR(n9_6) 
);
  DFF \x.cross_region_reg_0_s0  (
    .Q(q),
    .D(VCC),
    .CLK(clock) 
);
endmodule /* sync */
module top (
  clock
)
;
input clock;
  sync \gen[0].s  (
    .clock(clock) 
);
  sync b (
    .clock(clock) 
);
endmodule /* top */
"""


def test_netlist_hierarchy():
    netlist = GowinNetlist(NETLIST)
    assert netlist.top() == "top"
    cells = {path: (cell, pins) for path, cell, pins in netlist.leaf_cells()}
    assert cells["gen[0].s/async_clr.tig_reg_clr_0_s0"] \
        == ("DFFC", {"Q", "D", "CLK", "CLEAR"})
    assert set(cells) == {
        "gen[0].s/async_clr.tig_reg_clr_0_s0", "gen[0].s/x.cross_region_reg_0_s0",
        "b/async_clr.tig_reg_clr_0_s0", "b/x.cross_region_reg_0_s0",
    }


def test_explicit_constraints_name_existing_pins():
    assert explicit_constraints(NETLIST) == [
        "set_false_path -to [get_pins {gen[0].s/async_clr.tig_reg_clr_0_s0/CLEAR}]",
        "set_false_path -to [get_pins {b/async_clr.tig_reg_clr_0_s0/CLEAR}]",
        "set_false_path -to [get_pins {gen[0].s/x.cross_region_reg_0_s0/D}]",
        "set_false_path -to [get_pins {b/x.cross_region_reg_0_s0/D}]",
    ]


def test_wildcard_constraints():
    assert wildcard_constraints(NETLIST) == [
        "set_false_path -to [get_pins {*tig_reg_clr*/CLEAR}]",
        "set_false_path -to [get_pins {*cross_region_reg*/D}]",
    ]
