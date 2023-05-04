#!/bin/sh

test -n "$1$2" || exit 1

add_rule() {
    if grep -q "$4" "$1" ; then
        echo "set_false_path -$3 [get_pins {*$4*/$5}]"
    fi
}

> $2
add_rule $1 $2 to tig_reg_clr CLEAR >> $2
add_rule $1 $2 to tig_reg_pre PRE >> $2
add_rule $1 $2 from tig_reg_q O >> $2
add_rule $1 $2 from tig_reg_q Q >> $2
add_rule $1 $2 from tig_static_reg O >> $2
add_rule $1 $2 from tig_static_reg Q >> $2
add_rule $1 $2 to tig_static_reg D >> $2
add_rule $1 $2 to cross_region_reg D >> $2
add_rule $1 $2 to async_net D >> $2
add_rule $1 $2 from async_net Q >> $2
