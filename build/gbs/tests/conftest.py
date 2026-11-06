import sys
from pathlib import Path

# Test this tree's plugin, not an installed one.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
