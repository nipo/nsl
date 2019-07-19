==================
Coding conventions
==================

Libraries
=========

HDL Code-base uses VHDL library/package/entity classification:

* Libraries are used to separate code as big families
  (hardware-dependant modules, utilities, communication framework,
  etc.),

* Packages are used to separate logical groups of sources as a
  workable unit inside libraries.

Forward declaration
-------------------

Packages are used as a header for related entities. They also allow
declaring specific data‑types used as ports or generics for related
entities.

Naming
------

Naming of modules is mostly limited by VHDL:

* VHDL provides complete namespace separation across libraries, but
  not across packages in a given library. As such, entity names should
  repeat package name as a prefix.

* VHDL is case-insensitive, names of entities and signals should not
  rely on case to be readable.

Source-tree organization
------------------------

Root of tree contains the following directories:

* /lib/ The component sources, generic or not;

* /build/ Build system;

* /tests/ Test benches for modules;

* /python/ Test-bench helpers;

* /example/ Various usage examples.

Naming conventions
==================

All names should be `lower_case_with_underscores`. This because of two
main reasons:

* VHDL is case-insensitive, so we should not rely on case in the first place.

* Tools may normalize case to all upper, all lower, or anything
  else. If we rely on case to make a name readable, we may have great
  difficulties to read normalized versions of such names.

Package names
-------------

Packages should be expressive in their names, avoid “common” or “util”
generic names, they tend to get messy in the contents. Don’t worry if
a package starts with only one declaration inside.

Some relevant examples:

* axi4_lite, axis
* pwm_generator

Names not expressive enough:

* capture_control,
* communication, tooling, debug.
 
Entity names
------------

Entities should repeat the package name they are declared in as a
prefix. This is mostly a VHDL name scoping limitation (package implies
no name scoping, only library is).

Some relevant examples:

* hwdep.io.io_ddr_bus_input,
* util.gray.gray_encoder,
* coresight.dp.dp_transactor.

Port names
----------

Ports should have a base name that explains what is logically conveyed
first, data type or direction are ancillary information. All ports
should be suffixed by the direction, either _i or _o.

`inout` ports should be only used in the very top cell of a complete
design. In any other places, there should be data`_i`, data`_o` and
data`_oe_o` should be used if an input/output bus is to be created.

Names, even common ones like clock and reset should not be abbreviated
(clk, ck or rst).

Negative logic should be avoided. If negative logic is mandatory, _n
suffix should be added to base name (i.e. between name and direction
suffix). As a corollary, enable signals should be preferred to
enable_n signals, and disable signals should not exist.

Ambiguous names should be avoided. For instance, “tri” for a tri-state
is ambiguous about polarity. “output_enable” or “oe” is unambiguous.

Records should be used to group related signals. Record definitions
should be either in package related to entity using them, or in a
common signaling package.

Examples:

* clock_i, reset_i, reset_n_i,
* iq_tdata_i, iq_tvalid_i, iq_tready_o,
* duty_cycle_i, led_o,
* signalling.color.rgb24,
* signalling.diff.diff_pair.

Generic names
-------------

If generic defines length of an array, or size of a memory,
designation of thing we actually count is better than generic `_size`
(but size can be used if non ambiguous).

If generic defines with of a port with no precise meaning, `_width`
should be used.

Example:

  If we have a memory model with generic word width and total size
  where words can only be a multiple of 8, we should prefer
  `bytes_per_word`, `word_bytes` or `word_byte_count` and `word_count`
  to `data_width` and `size`. `size` and `data_width` can be
  ambiguous: are they the total memory size in words, bytes, bits,
  maybe even address size ?  is `data_width` is expressed in bytes or
  bits ?

Internal signal names
---------------------

Internal signal names have no naming requirements. They should use the
lower_case_with_underscore convention anyway. Records are recommended
when multiple signals are to be grouped, in array or not.

Internal registers (i.e. internal state of a module) should ideally be
grouped in a `r` signal record.

Package constant names
----------------------

Package constants should be all upper-case. Casing can help
distinguishing them in source code, even if it does not play any role
because of case-insensitivity of language.

Repeating package name in constants is not mandatory, but can help
disambiguate in case multiple packages may declare constants with same
base name.

Package type names
------------------

Type names may be suffixed with `_t` when it is not obvious the name
is a type.

Repeating package name in types is not mandatory, but can help
disambiguate in case multiple packages may declare types with same
base name.

Types declaring arrays of other types should be suffixed by `_vector`
to follow the standard library conventions.

Enumerations
------------

Enumerations, as public types, should follow rules for
types. Enumeration named entries should repeat the enumeration base
name as a prefix.

Example::

  type my_enum_t is (
    MY_ENUM_RESET,
    MY_ENUM_FOO,
    MY_ENUM_BAR,
    MY_ENUM_BAZ
    );

Library organization
====================

HDL tree is split in VHDL libraries and packages. As this is the only
categorization permitted by language and supported by tools, we cannot
use any deeper taxonomy tree.
