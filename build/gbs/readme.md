# GBS Plugin: NSL Tree Loader

This plugin allows GBS to load NSL tree repositories, which use Makefiles to define library structure and dependencies.

## Installation

```bash
pip install -e .
```

## Usage

In your project file:

```yaml
repositories:
  - path: /path/to/nsl
    loader: nsl-tree
```

## NSL Structure

- `lib/` contains libraries
- Each library directory contains a Makefile that defines packages (partitions)
- Each package directory contains a Makefile with:
  - `vhdl-sources`: VHDL source files
  - `verilog-sources`: Verilog/SystemVerilog source files
  - `deps`: Dependencies on other packages (format: `library.package`)
