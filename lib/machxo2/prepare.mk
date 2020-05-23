DIAMOND = /usr/local/diamond/3.11/
MACHXO2 = $(DIAMOND)/cae_library/simulation/vhdl/machxo2/src

all: copy

copy: .prepared

clean:

internal := 1
include Makefile

define src-declare

clean-files += $1

copy: $(MACHXO2)/$1

endef

$(eval $(foreach s,$(vhdl-sources),$(call src-declare,$s)))

clean-files += .prepared

.prepared:
	touch $@

copy:
	cp $(filter %.vhd,$^) .

clean:
	rm -f $(clean-files)
