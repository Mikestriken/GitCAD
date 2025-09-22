#!/bin/bash
# ==============================================================================================
#                                  Verify and Retrieve Dependencies
# ==============================================================================================
# Ensure working dir is the root of the repo
GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ]; then
    echo "Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# Check for uncommitted work in working directory, exit early if so with error message
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: There are uncommitted changes in the working directory. Please commit or stash them before running tests."
    exit $FAIL
fi

# ==============================================================================================
#                                          Get Binaries
# ==============================================================================================
git checkout test_binaries -- FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd
git clearFCStdMod FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd

# ==============================================================================================
#                                           Run Tests
# ==============================================================================================
"$PYTHON_PATH" -m unittest --failfast FreeCAD_Automation.tests.test_FCStdFileTool

exit $SUCCESS