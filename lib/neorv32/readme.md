# NeoRV32 integration

`neorv32_project` is a git submodule targetting upstream NeoRV32 project.

`neorv32_package` uses the relevant modules from upstream project.

## Reimplementations

imem / dmem memory blocks are reimplemented using blocks from
nsl_memory. Imem / boot rom initialization payloads are deferred to a
`user_data.neorv32_init` package that should be defined by user in its
project Makefile.

See nsl_neorv32 for wapping with NSL types on IOs.
