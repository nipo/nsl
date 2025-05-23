targets=headless_run run simulate clean tb list

all: run

simulate:
clean:
run:
headless_run:

define target_declare

$1/$2: $1/Makefile
	$(MAKE) -C $1 $2

endef

define tb_declare

headless_run: $1/headless_run
simulate: $1/simulate
clean: $1/clean
run: $1/run

$(eval $(foreach i,$(targets),$(call target_declare,$1,$i)))

endef

$(eval $(foreach i,$(tb),$(call tb_declare,$i)))
