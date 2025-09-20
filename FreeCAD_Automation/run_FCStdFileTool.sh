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
# `$(GIT_PREFIX:-.)`:
    # If caller is in $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller is in $GIT_ROOT, $(GIT_PREFIX) = ""
CALLER_SUBDIR=$1
shift

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_args=()
if [ "$CALLER_SUBDIR" != "" ]; then
    for arg in "$@"; do
        if [[ "$arg" == -* ]]; then
            parsed_args+=("$arg")
        else
            parsed_args+=("$CALLER_SUBDIR$arg")
        fi
    done
else
    parsed_args=("$@")
fi

# ==============================================================================================
#                                    Call FCStdFileTool.py
# ==============================================================================================
# Test to see how the args will be passed
"$PYTHON_PATH" "$FCStdFileTool" "${parsed_args[@]}"