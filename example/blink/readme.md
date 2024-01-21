# Blinker example

## Presentation

This is a basic blinker example that exposes the following:

* Build system usage for a topcell instantiation,

* Build system usage with a portable design,

* Abstract blocks for clock generation.

## Build system

### Top-level Makefile

There is a top-level Makefile for each target.

Let's break down the Makefile for Gowin's `GW1N` FPGA series as an
example. It defines the following:

* target name,

  ```
  target = blink
  ```

* topcell library and entity name,

  ```
  top = work.top
  ```

* path where to find the topcell's library source tree,

  ```
  work-srcdir = $(SRC_DIR)/../src
  ```

* backend-dependent target definition,

  ```
  target_part_name = GW1N-9C
  target_part = GW1N-UV9UG256C6/I5
  ```

* tool to use for generating the target,

  ```
  tool = gowin
  ```

* hardware-dependent library hints,

  ```
  hwdep = gowin
  ```

* default target,

  ```
  all: blink.fs
  ```

* an include of the generic build system entry point.

  ```
  include ../../../build/build.mk
  ```

### Topcell implementation Makefile

Then in `../src/` comes the topcell's Makefile. It defines the
following:

* a source file to compile,

  ```
  vhdl-sources += blink.vhd
  ```

* some backend-dependant constraint files, where only one will be used
  by the Gowin design:

  ```
  ifeq ($(hwdep),gowin)
  constraint-sources += led.cst
  endif
  ```

* finally, there are dependencies on packages from the library:

  ```
  deps += nsl_hwdep.clock
  ```

## Topcell implementation

Breakdown of the whole VHDL implementation is unimportant, the only
interesting part is the instantiation of the clock generator, first by
declaring `nsl_hwdep` as a library:

```
library nsl_hwdep;
```

Then instantiating the relevant component from the library by its
fully qualified name:

```
  clk_gen: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => clk
      );
```

