#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to run the FCStdFileTool.py script manually via `git ftool`, git `fimport`, `git fexport` aliases

# ==============================================================================================
#                               Verify and Retrieve Dependencies
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
        
        elif [ "$arg" = "." ]; then
            parsed_args+=("$CALLER_SUBDIR")
            
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
"$PYTHON_EXEC" "$FCStdFileTool" "${parsed_args[@]}"

exit $SUCCESS