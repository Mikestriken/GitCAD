#!/bin/bash
# ==============================================================================================
#                                     Verify Dependencies
# ==============================================================================================
# Check if inside a Git repository and ensure working dir is the root of the repo
if ! git rev-parse --git-dir > /dev/null; then
    echo "Error: Not inside a Git repository" >&2
    exit 1
fi

GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/functions.sh"
source "$FUNCTIONS_FILE"

CONFIG_FILE="FreeCAD_Automation/git-freecad-config.json"

# Extract Python path
PYTHON_PATH=$(get_json_value "$CONFIG_FILE" "freecad-python-instance-path") || {
    echo "Error: get_json_value failed" >&2
    exit 1
}

if [ -z "$PYTHON_PATH" ]; then
    echo "Error: Python path is empty" >&2
    exit 1
fi

# Check if Python runs correctly
if ! "$PYTHON_PATH" --version > /dev/null; then
    echo "Error: Python does not run or path is invalid" >&2
    exit 1
fi

# Check if the import works
if ! "$PYTHON_PATH" -c "from freecad import project_utility as PU; print('Import successful')" > /dev/null; then
    echo "Error: Import 'from freecad import project_utility as PU' failed" >&2
    exit 1
fi

# ==============================================================================================
#                                          Get Binaries
# ==============================================================================================
git checkout test_binaries -- FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd
git add FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd

# git add executes the clean FCStd filter on the added .FCStd files. This cleans up the unintentional use of the clean filter.
rm -rf FreeCAD_Automation/tests/uncompressed/

# ==============================================================================================
#                                           Run Tests
# ==============================================================================================
"$PYTHON_PATH" -m unittest --failfast FreeCAD_Automation.tests.test_FCStdFileTool