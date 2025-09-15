#!/bin/bash
# ==============================================================================================
#                                     Verify Dependencies
# ==============================================================================================
# Check if inside a Git repository and ensure working dir is the root of the repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
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
PYTHON_PATH=$(get_json_value "$CONFIG_FILE" "freecad-python-instance-path")
if [ $? -ne 0 ] || [ -z "$PYTHON_PATH" ]; then
    echo "Error: Could not extract Python path"
    exit 1
fi

# Check if Python runs correctly
if ! "$PYTHON_PATH" --version > /dev/null 2>&1; then
    echo "Error: Python does not run or path is invalid"
    exit 1
fi

# Check if the import works
if ! "$PYTHON_PATH" -c "from freecad import project_utility as PU; print('Import successful')" > /dev/null 2>&1; then
    echo "Error: Import 'from freecad import project_utility as PU' failed"
    exit 1
fi

# ==============================================================================================
#                                           Run Tests
# ==============================================================================================
"$PYTHON_PATH" -m FreeCAD_Automation.tests.test_FCStdFileTool