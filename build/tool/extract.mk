all: extract

define rewriter
export-num-$2 := $1$2

endef

define rewriter2
$(call rewriter,00,$n)
$(foreach n,0 1 2 3 4 5 6 7 8 9,$(call rewriter,0,$1$n))
endef

$(eval $(foreach n,0 1 2 3 4 5 6 7 8 9,$(call rewriter2,$n)))

export-language-ext-vhdl = vhd
export-language-ext-verilog = v
export-language-ext-xdc = xdc
export-language-comment-vhdl = --
export-language-comment-v = //
export-language-comment-xdc = \#

lib_outname = $(export-index-$1)_$1.$(export-language-ext-$2)

export-libs :=
export-files :=

lpad = $(if $(export-num-$1),$(export-num-$1),$1)

define lib_declare

export-libs := $$(export-libs) $1
export-index-$1 := $$(call lpad,$$(words $$(export-libs)))
export-languages-$1 := $(sort $(foreach s,$($1-sources),$(if $(export-language-ext-$($s-language)),$($s-language))))

endef

define lib_file_append
	$(SILENT)echo "" >> $$@
	$(SILENT)echo "$(export-language-comment-$2) Original file: $(notdir $3)" >> $$@
	$(SILENT)echo "" >> $$@
	$(SILENT)cat "$3" >> $$@
	
endef

define lib_lang_generate

$(call lib_outname,$1,$2): $(foreach s,$($1-sources),$(if $(filter $2,$($s-language)),$s))
	$(SILENT)echo "$(export-language-comment-$2) This is a partial extract from NSL" > $$@
	$(SILENT)echo "$(export-language-comment-$2) https://code.ssji.net/git/nipo/nsl" >> $$@
	$(SILENT)echo "$(export-language-comment-$2) performed on `date`" >> $$@
	$(SILENT)echo "$(export-language-comment-$2)" >> $$@
	$(SILENT)echo "$(export-language-comment-$2) This file should be compiled as $2, in library $1" >> $$@
	$(SILENT)echo "$(export-language-comment-$2)" >> $$@
	$(SILENT)cat $(BUILD_ROOT)/../license.rst | sed -e "s:^:$(export-language-comment-$2) :" >> $$@
	$(SILENT)echo "$(export-language-comment-$2)" >> $$@
$(foreach s,$($1-sources),$(if $(filter $2,$($s-language)),$(call lib_file_append,$1,$2,$s)))

export-files += $(call lib_outname,$1,$2)
clean-files += $(call lib_outname,$1,$2)
extract: $(call lib_outname,$1,$2)

endef

define lib_generate

$(foreach l,$(export-languages-$1),$(call lib_lang_generate,$1,$l))

endef

$(eval $(foreach l,$(libraries),$(if $($l-sources),$(call lib_declare,$l))))
$(eval $(foreach l,$(libraries),$(if $($l-sources),$(call lib_generate,$l))))

extract:
	@
