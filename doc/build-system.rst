==============
 Build system
==============

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
