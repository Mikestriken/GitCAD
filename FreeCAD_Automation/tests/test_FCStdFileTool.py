import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../FreeCAD_Automation')))

try:
    # Module import that will fail. Left here for intellisense purposes
    from ..FCStdFileTool import *
    print_debug("Success")
except ImportError as e:
    # from FCStdFileTool import *
    print(f"Error: {e}")
    