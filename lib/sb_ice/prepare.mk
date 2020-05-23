ICECUBE = /opt/Lattice/iCEcube2_2017.08
VHDL = $(ICECUBE)/LSE/cae_library/synthesis/vhdl

all: copy

copy: .prepared

clean:

internal := 1
include Makefile

define src-declare

clean-files += $1

copy: $(VHDL)/$1

endef

$(eval $(foreach s,$(vhdl-sources),$(call src-declare,$s)))

clean-files += .prepared

.prepared:
	touch $@

copy:
	cp $(filter %.vhd,$^) .

clean:
	rm -f $(clean-files)
