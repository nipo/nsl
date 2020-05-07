
define pkg_dirdep_list
echo "        directly depends on $1"
	$(SILENT)
endef

define pkg_indirdep_list
echo "        indirectly depends on $1"
	$(SILENT)
endef

define pkg_list
echo "    - $1"
	$(SILENT)$(foreach d,$($1-deps-unsorted),$(call pkg_dirdep_list,$d))
	$(SILENT)$(foreach d,$(call filter-out-many,$($1-deepdeps-unsorted),$($1-deps-unsorted)),$(call pkg_indirdep_list,$d))
	$(SILENT)
endef

define lib_dep_list
echo "    depends on $1"
	$(SILENT)
endef

define lib_list
echo "  library $1:"
	$(SILENT)$(foreach d,$($1-libdeps-unsorted),$(call lib_dep_list,$d))
	$(SILENT)$(foreach p,$($1-packages),$(call pkg_list,$p))
	$(SILENT)
endef

define list_source_list
echo "  $($1-library), $($1-language): $1"
	$(SILENT)
endef

# Exclude vendor libraries by default, they are not really interesting.
EXCLUDE_LIBS ?= unisim xilinxcorelib

ifneq ($(EXCLUDE_LIBS),)
$(call exclude-libs,$(EXCLUDE_LIBS))
endif

analyze elaborate simulate: list

all-packages:
	$(SILENT)echo "$(all-packages)"

enabled-packages:
	$(SILENT)echo "$(enabled-packages)"

top-info:
	$(SILENT)echo "Top design: $(top)"
	$(SILENT)echo "Top library: $(top-lib)"
	$(SILENT)echo "Top package: $(top-package)"
	$(SILENT)echo "Top entity: $(top-entity)"
	$(SILENT)echo "Package build order: $(enabled-packages)"
	$(SILENT)echo "Lib build order: $(libraries)"

library-info:
	$(SILENT)echo "Info"
	$(SILENT)echo " - VHDL version: $($(LIBRARY)-vhdl-version)"
	$(SILENT)echo " - Deps: $($(LIBRARY)-libdeps-unsorted)"
	$(SILENT)echo "Packages"
	$(SILENT)echo " - all: $($(LIBRARY)-all-packages)"
	$(SILENT)echo " - enabled: $($(LIBRARY)-enabled-packages)"
	$(SILENT)echo " - ordered: $($(LIBRARY)-packages)"

list:
	$(SILENT)echo "Dependencies:"
	$(SILENT)$(foreach l,$(libraries),$(call lib_list,$l))
	$(SILENT)echo
	$(SILENT)echo "Sources, in build order:"
	$(SILENT)$(foreach s,$(sources),$(call list_source_list,$s))
	$(SILENT)echo
	$(SILENT)echo "Useless stats:"
	$(SILENT)echo "  total LOC: $$(cat $(sources) | wc -l)"
