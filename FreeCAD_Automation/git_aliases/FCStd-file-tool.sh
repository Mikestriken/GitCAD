#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to run the FCStdFileTool.py script manually via `git ftool`, git `fimport`, `git fexport` aliases

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Note: PWD for all scripts called via git aliases is the root of the git repository

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ]; then
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                                          Parse Args
# ==============================================================================================
# CALLER_SUBDIR=${GIT_PREFIX}:
    # If caller's pwd is $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller's pwd is $GIT_ROOT, $(GIT_PREFIX) = ""
CALLER_SUBDIR=$1
shift

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_args=()
if [ "$CALLER_SUBDIR" != "" ]; then
    for arg in "$@"; do
        case $arg in
            -*)
                parsed_args+=("$arg")
                ;;
            ".")
                parsed_args+=("$CALLER_SUBDIR")
                ;;
            *)
                parsed_args+=("${CALLER_SUBDIR}${arg}")
                ;;
        esac
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