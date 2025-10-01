#!/bin/bash
# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ]; then
    echo "Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                                     Export Python Path
# ==============================================================================================
FREECAD_ROOT=$(dirname "$PYTHON_PATH")
FREECAD_ROOT=$(realpath "$FREECAD_ROOT/..")

export FREECAD_ROOT="$FREECAD_ROOT"
export PYTHONPATH="$FREECAD_ROOT/lib/python3.11/site-packages:$FREECAD_ROOT/lib:$PYTHONPATH"

# ==============================================================================================
#                                       Execute Python
# ==============================================================================================
"$PYTHON_PATH" "$@"