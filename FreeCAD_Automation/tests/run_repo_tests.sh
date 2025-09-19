#!/bin/bash
# ==============================================================================================
#                                  Verify and Retrieve Dependencies
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
PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || exit 1

# ==============================================================================================
#                                          Test Functions
# ==============================================================================================
# ToDo: setup function
    # Checkout -b active_test
        # Err if returns 1 (branch already exists)
    # Copies binaries into active_test dir

# ToDo: tearDown function
    # Reset back to main
    # Delete active_test branch (local and remote)

# ToDo: Any custom assert functions

# ToDo: Await user modification of `.FCStd` file (verify file was modified before exiting)
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
# ToDo: Test FCStd-filter.sh
    # `git add` .FCStd files copied during setup
    # Assert dir was

# ToDo: Test Pre-Commit Hook

# ToDo: Test Pre-Push Hook

# ToDo: Test Post-Checkout Hook

# ToDo: Test Post-Merge Hook
