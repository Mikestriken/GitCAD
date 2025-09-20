#!/bin/bash
# ==============================================================================================
#                               Verify and Retrieve Dependencies
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
FCStdFileTool="FreeCAD_Automation/FCStdFileTool.py"

# Extract Python path
PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || exit 1

# ==============================================================================================
#                                          Parse Args
# ==============================================================================================
# * Get caller pwd
# IE if caller is in $GIT_ROOT/subdir, CALLER_PWD = "subdir/"
CALLER_PWD=$1
shift

# ==============================================================================================
#                                          get
# ==============================================================================================
echo "PWD '$CALLER_PWD'"
echo "Next Arg '$1'"