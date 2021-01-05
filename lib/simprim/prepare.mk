ISE = /opt/Xilinx/14.7
ISE_VHDL = $(ISE)/ISE_DS/ISE/vhdl/src
SIMPRIM_VHDL = $(ISE_VHDL)/simprims

all: copy

copy: .prepared

clean:

internal := 1
include Makefile

define src-declare

clean-files += $1/$2

$1/copy: $(wildcard $(SIMPRIM_VHDL)/$2 $(SIMPRIM_VHDL)/primitive/other/$2)

endef

define pkg-declare

vhdl-sources :=

include $1/Makefile

.prepared: $1/copy

$$(eval $$(foreach s,$$(vhdl-sources),$$(call src-declare,$1,$$s)))

$1/copy:
	cp $$^ $1/

endef

$(eval $(foreach p,$(packages),$(call pkg-declare,$p)))

clean-files += .prepared

.prepared:
	touch $@

clean:
	rm -f $(clean-files)
