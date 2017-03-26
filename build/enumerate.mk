
define y_clear

$1:=
$1-y:=

endef

define y_merge

$1 := $$($1) $$($1-y)
$1-y :=

endef

define library_scan_sub

$(call y_clear,subdirs)
$(call y_clear,vhdl-sources)
$(call y_clear,verilog-sources)

include $2/Makefile

srcdir := $$(shell cd $$(shell pwd) ; cd $$(dir $$(lastword $$(MAKEFILE_LIST))) ; pwd)

$(call y_merge,subdirs)
$(call y_merge,vhdl-sources)
$(call y_merge,verilog-sources)

$(1)-vhdl-sources += $$(foreach v,$$(vhdl-sources),$$(srcdir)/$$v)
$(1)-verilog-sources += $$(foreach v,$$(verilog-sources),$$(srcdir)/$$v)

$$(eval $$(foreach s,$$(subdirs),$$(call library_scan_sub,$1,$2/$$s)))

endef

define library_scan

$1-vhdl-sources :=
$1-verilog-sources :=

$$(eval $$(call library_scan_sub,$1,$2))

endef
