"""NSL Plugin for GBS

Provides:
- tree: NSL tree repository loader
- cdc: CDC constraint generation dispatchers for Gowin and ISE

The CDC dispatchers activate when a netlist is generated (gowin-netlist or ise-netlist).
"""

# Import from main GBS for plugin system (not gbs.plugins)
import sys
from pathlib import Path
from gbs.base import *

__all__ = ['gbs_register']


class NslPlugin(BasePlugin):
    """NSL plugin providing repository parser and CDC dispatcher"""

    def __init__(self):
        super().__init__(
            name="gbs.plugin.nsl",
            description="NSL tree repository parser and CDC constraint generator",
            version="1.0.0"
        )

    def generic_dispatchers(self, context):
        """Return NSL CDC dispatchers"""
        from pathlib import Path
        from .cdc import CdcGowinDispatcher
        from .cdc import CdcVivadoDispatcher
        return [
            CdcGowinDispatcher(context),
            CdcVivadoDispatcher(context),
        ]

    def enumerate_backends(self):
        """Return NSL CDC backends"""
        from .cdc import CdcIseBackend
        return [CdcIseBackend()]
    
    def enumerate_repository_parsers(self):
        """Return NSL tree repository parser class"""
        # Return dict mapping loader name to class
        from .repository import NSLTreeLoader
        return {"nsl-tree": NSLTreeLoader}

def gbs_register():
    """Plugin registration function

    Called by the plugin system during discovery.
    Must return one or more Plugin instances.
    """
    return NslPlugin()
