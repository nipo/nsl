"""NSL Tree Loader for GBS

Loads NSL tree repositories into GBS data structures.

NSL Structure:
- lib/ contains libraries (directories)
- Each library has a Makefile defining packages (partitions)
- Each package directory has a Makefile with sources and deps

IMPORTANT: NSL Makefiles are evaluated on demand during dependency resolution.
Filter variables are passed as Makefile variables when evaluating partitions.
"""

from pathlib import Path
from typing import Optional
import sys

# Import from main GBS
gbs_src = Path(__file__).parents[4] / "src"
if gbs_src.exists() and str(gbs_src) not in sys.path:
    sys.path.insert(0, str(gbs_src))

from gbs.repository.model import Repository, Partition, SourceFile
from gbs.repository.loader import RepositoryLoader, LoadError
from gbs.logging import get_logger
from .makefile import Makefile, Context

logger = get_logger(__name__)


class NSLRepository(Repository):
    """NSL tree repository with on-demand Makefile-based enumeration

    NSL repositories evaluate Makefiles with filter variables to determine
    which packages (partitions) are available and what sources they contain.
    """

    def __init__(self, name: str, root: Path, libraries: dict[str, Path]):
        """Initialize NSL repository

        Args:
            name: Repository name
            root: Repository root path
            libraries: Dictionary of library name -> library directory path
        """
        super().__init__(name, root)
        self._libraries = libraries

    def file_types(self) -> set[str]:
        """Get all possible file types from NSL repository

        NSL repositories can contain VHDL, Verilog, and SystemVerilog.
        """
        return {"vhdl"}

    def partition_lookup(self, partition_name: str, filter_vars: dict[str, str]) -> Optional[Partition]:
        """Lookup partition by name and expand with filter variables

        Args:
            partition_name: Partition name in "library.partition" format
            filter_vars: Filter variables for Makefile evaluation

        Returns:
            Expanded Partition or None if not found
        """
        # Parse partition name
        if '.' not in partition_name:
            logger.warning(f"Partition name must be in 'library.partition' format: {partition_name}")
            return None

        library_name, package_name = partition_name.split('.', 1)

        # Find library
        if library_name not in self._libraries:
            return None

        lib_path = self._libraries[library_name]

        # Handle bare libraries (libraries without packages)
        # If partition name is "libname._bare", evaluate the library Makefile directly
        if package_name == "_bare":
            makefile_path = lib_path / "Makefile"
            if not makefile_path.exists():
                logger.warning(f"Bare library {library_name} has no Makefile at {makefile_path}")
                return None
            return self._evaluate_package(partition_name, lib_path, makefile_path, filter_vars, library_name)

        # Enumerate packages for this library using filter vars
        packages = self._enumerate_library_packages(lib_path, filter_vars)

        # Check if requested package is in the enumerated list
        if package_name not in packages:
            return None

        # Evaluate package Makefile to get sources and deps
        package_path = lib_path / package_name
        makefile_path = package_path / "Makefile"

        if not makefile_path.exists():
            logger.warning(f"Package {package_name} has no Makefile at {makefile_path}")
            return None

        return self._evaluate_package(partition_name, package_path, makefile_path, filter_vars, library_name)

    def _enumerate_library_packages(self, lib_path: Path, filter_vars: dict[str, str]) -> list[str]:
        """Enumerate packages in a library by evaluating library Makefile

        Args:
            lib_path: Path to library directory
            filter_vars: Filter variables for enumeration

        Returns:
            List of package names available with these filter vars
        """
        makefile_path = lib_path / "Makefile"
        if not makefile_path.exists():
            logger.warning(f"Library has no Makefile at {makefile_path}")
            return []

        # Create Makefile context with filter variables
        context = Context()

        for key, value in filter_vars.items():
            if key == "target":
                context["target-usage"] = str(value)
            context[key] = str(value)

        # Parse and interpret library Makefile
        makefile = Makefile(makefile_path)
        makefile.interpret(context)

        # Extract package list (filter-dependent!)
        packages_str = context.expand(context.get("packages", ""))
        packages = packages_str.split()

        logger.debug(f"Library {lib_path.name} enumerated: {len(packages)} packages")
        return packages

    def _evaluate_package(
        self,
        partition_name: str,
        package_path: Path,
        makefile_path: Path,
        filter_vars: dict[str, str],
        library_name: str
    ) -> Partition:
        """Evaluate package Makefile to get sources and dependencies

        Args:
            partition_name: Full partition name ("library.partition")
            package_path: Path to package directory
            makefile_path: Path to package Makefile
            filter_vars: Filter variables
            library_name: Library name for qualifying deps

        Returns:
            Expanded Partition
        """
        logger.debug(f"Evaluating NSL package {makefile_path} with filter vars {filter_vars}")

        # Create Makefile context with filter variables
        context = Context()

        for key, value in filter_vars.items():
            if key == "target":
                context["target-usage"] = str(value)
            context[key] = str(value)

        # Parse and interpret Makefile
        makefile = Makefile(makefile_path)
        makefile.interpret(context)

        # Extract sources
        vhdl_sources_str = context.expand(context.get("vhdl-sources", ""))
        verilog_sources_str = context.expand(context.get("verilog-sources", ""))
        systemverilog_sources_str = context.expand(context.get("systemverilog-sources", ""))

        sources = []

        # VHDL sources
        for source_file in vhdl_sources_str.split():
            source_file = source_file.strip()
            if source_file and not source_file.startswith('$('):
                sources.append(SourceFile(
                    path=package_path / source_file,
                    file_type="vhdl"
                ))

        # Verilog sources
        for source_file in verilog_sources_str.split():
            source_file = source_file.strip()
            if source_file and not source_file.startswith('$('):
                sources.append(SourceFile(
                    path=package_path / source_file,
                    file_type="verilog"
                ))

        # SystemVerilog sources
        for source_file in systemverilog_sources_str.split():
            source_file = source_file.strip()
            if source_file and not source_file.startswith('$('):
                sources.append(SourceFile(
                    path=package_path / source_file,
                    file_type="systemverilog"
                ))

        # Extract dependencies and qualify them
        deps_str = context.expand(context.get("deps", ""))
        deps = set()

        for dep in deps_str.split():
            dep = dep.strip()
            if dep and not dep.startswith('$('):
                # Qualify dependency with library name if not already qualified
                if '.' in dep:
                    # Already qualified (library.partition format)
                    deps.add(dep)
                else:
                    # Unqualified dependency - could be a package in current library
                    # or a bare library reference
                    # Check if it's a known library name (bare library)
                    if dep in self._libraries:
                        # Promote bare library to libname._bare
                        deps.add(f"{dep}._bare")
                    else:
                        # Package in current library
                        deps.add(f"{library_name}.{dep}")

        logger.debug(f"Evaluated partition {partition_name}: {len(sources)} sources, {len(deps)} deps")

        return Partition(
            name=partition_name,
            sources=sources,
            deps=deps
        )


class NSLTreeLoader(RepositoryLoader):
    """Repository loader for NSL tree format"""

    def load(self) -> Repository:
        """Load NSL tree repository

        Returns:
            NSLRepository instance

        Raises:
            LoadError: If repository cannot be loaded
        """
        logger.debug(f"Loading NSL tree repository from {self.path}")

        # Repository root is the path provided (should point to lib/ directory)
        root = self.path
        if not root.is_dir():
            raise LoadError(f"NSL repository root is not a directory: {root}")

        # Enumerate libraries from the provided directory
        lib_dir = root
        if not lib_dir.exists():
            raise LoadError(f"NSL repository missing lib/ directory: {lib_dir}")

        # Enumerate libraries (subdirectories of lib/ with Makefiles)
        libraries = {}
        for item in lib_dir.iterdir():
            if item.is_dir():
                makefile_path = item / "Makefile"
                if makefile_path.exists():
                    lib_name = item.name
                    libraries[lib_name] = item
                    logger.debug(f"Found NSL library: {lib_name}")

        if not libraries:
            raise LoadError(f"No libraries found in {lib_dir}")

        # Use directory name as repository name
        name = root.name

        logger.info(f"Loaded NSL repository '{name}' with {len(libraries)} libraries")
        return NSLRepository(name=name, root=root, libraries=libraries)


def enumerate_repository_parsers():
    """Plugin entry point for NSL tree loader"""
    return {
        "nsl-tree": NSLTreeLoader
    }


__all__ = ["NSLRepository", "NSLTreeLoader", "enumerate_repository_parsers"]
