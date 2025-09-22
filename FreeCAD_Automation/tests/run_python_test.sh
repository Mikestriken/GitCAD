#!/bin/bash
# ==============================================================================================
#                                  Verify and Retrieve Dependencies
# ==============================================================================================
# Ensure working dir is the root of the repo
GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/functions.sh"
source "$FUNCTIONS_FILE"

# ==============================================================================================
#                                          Get Binaries
# ==============================================================================================
git checkout test_binaries -- FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd
git add FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd

# ! git add executes the clean FCStd filter on the added .FCStd files.
# ! Make sure to remove them after running the tests (don't commit them)

# ==============================================================================================
#                                           Run Tests
# ==============================================================================================
"$PYTHON_PATH" -m unittest --failfast FreeCAD_Automation.tests.test_FCStdFileTool

exit $SUCCESS