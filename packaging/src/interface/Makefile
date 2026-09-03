output-dir = ../../vivado_repository/interface

yamls = $(wildcard *.yaml)

all:
	gbs convert vivado-bus --output-dir $(output-dir) $(yamls)

check:
	gbs convert vivado-bus --check --output-dir $(output-dir) $(yamls)

.PHONY: all check
