==============
 Build system
==============

Overview
========

Build system relies on GNU Make. It is pluggable in the sense there
may be out-of-tree libraries and projects that reuse NSL core and
build system. For instance, NSL can be used as a git submodule from a
wrapper project.

There are different types of Makefiles in the tree.

Library makefiles
-----------------

Library makefiles should only point to packages. A typical library
Makefile contains::

  packages += foo
  packages += bar

Then in library directory, along with the Makefile, there should be
`foo` and `bar` directories for matching packages. Each of them should
contain a Package Makefile.

Package makefiles
-----------------

Package makefiles should enumerate package-related HDL source files,
and dependencies of the package on other packages.  A typical `foo`
package Makefile contains::

  vhdl-sources += foo.pkg.vhd
  vhdl-sources += foo_module_1.vhd
  vhdl-sources += foo_module_2.vhd
  deps += other.baz

Here package `foo` is composed of 3 VHDL source files, one package and
two modules. Naming of files is conventional only and is not enforced
by tools.

Dependencies are in the form `library.package`, and may reference
packages in the same library or others. Dependency cycles are
unsupported and should be avoided.

Note about package names and dependencies::

  Packages, in terms of VHDL namespacing, do not technically have to
  match the package directory name and deps variables. The
  build-system does not parse the HDL files contents. The only
  requirement is that build-system dependencies target
  build-system-declared package names (i.e. `deps += a.b` should match a
  `package += b` in library `a`).

Project makefiles
-----------------

Project makefiles share a common structure, but then have a big
backend-specific part. See relevant chapter for build backends.

Common part takes care of enumerating:

* Libraries (in-tree libraries in `lib/` are automatically
  enumerated),
* Top module (root of design),
* Build backend specifics: target, constraints, etc.

Most of the time, project makefile declares the "work" library with a
path relative to the project makefile, and declares "top" module to be
some cell in the "work" library::

  target = my_project
  top = work.top
  work-srcdir = $(SRC_DIR)/src
  tool = ghdl

  include path/to/nsl/build/build.mk

Then in src/Makefile, we have a (non-hierarchic) library containing
only one (or multiple) module::

  vhdl-sources += top.vhd
  deps += mylib.bar

`top=` variable defines a `library.entity` name to use as top cell
(`library.package.entity` notation may also be used).

That's actually the `work` library source directory that pulls the
dependencies from the rest of the library with `deps +=` lines.

`target =` simply defines the project output base name.

Two special variables may select different HDL implementation files
from the build-system: `hwdep` selects the hardware-dependent vendor
library, `target_part` defines the target part, allowing to select for
hardware-specific cells.

`tool =` defines the backend, all other variable are tool-specific.


Filesystem layout
=================

Build system looks for libraries in `lib/<library_name>` by
default. User may override a library's root directory by setting
`<library_name>-srcdir` in project's Makefile.

Library and packages declaration
================================

Build system is able to compute dependencies across packages and
libraries, and compile only used packages.

A library is a collection of packages. If a library can also have
non-packaged sources defined in its root directory.

Library Makefiles
-----------------

Each library's root directory Makefile may expose a set of packages in
the form::

  packages += <package name>

Make will recurse down in the directory with package name, and
interpret it as a package Makefile.

Libraries can also set VHDL version used. Choose among
93, 08. Defaults to 93. Setting is global for a library::

  vhdl-version = 08

Moreover, library root Makefiles may expose sources and dependencies
as package makefiles do. See following paragraph.

Package Makefiles
-----------------

Package Makefiles expose:

* source files, in the form::

    <language>-sources += <source file name>

  Source order is meaningful for some compilation backends.

* dependencies, in any of the following form::

    deps += <library name>.<package name>
    deps += <library name>

When referencing a library as dependency, only its root-defined
sources are used, not packages.

Builder backend
===============

Common work
-----------

`build.mk` handles all the hard work of finding dependencies and
computing the actual ordered source set.

Backend-specific
----------------

Global variables

* `sources`: Enabled source file names, in compilation order
* `libraries`: Enabled library names, in compilation order

Per library

* `$(library)-sources`: Sources file names
* `$(library)-packages`: Enabled packages
* `$(library)-libdeps-unsorted`: Library names it depends on
* `$(library)-deps-unsorted`: Enabled package names it depends on

Per package

* `$(package)-sources`: Sources file names
* `$(package)-deepdeps-unsorted`: Package names it depends on
* `$(package)-intradeps-unsorted`: Package names it depends on, inside own library

Per source

* `$(source)-language`: Language type for source
* `$(source)-library`: Library name it belongs to
* `$(source)-package`: Package name it belongs to

There is a public API entry from build.mk, called `exclude-libs`,
allowing a backend to remove some libraries from the build. This is
mostly useful for backend-specific simulation libraries that are
implicitly available in vendor synthesis tools. For example::

  $(call exclude-libs,unisim)
