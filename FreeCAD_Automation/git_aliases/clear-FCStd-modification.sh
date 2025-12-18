#!/bin/bash
echo "DEBUG: clear-FCStd-modification.sh trap-card triggered!" >&2
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to make git see a .FCStd file as empty (despite it containing data).
# If the file is already empty then to git it will show as not having any modifications in the working directory.
# First it makes sure there are no added .FCStd files then it calls `RESET_MOD=$TRUE git add` to clear the modification.

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Note: PWD for all scripts called via git aliases is the root of the git repository

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
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
parsed_file_path_args=()
while [ $# -gt 0 ]; do
    echo "DEBUG: parsing '$1'..." >&2
    case $1 in
        # Set boolean flag if arg is a valid flag
        -*)
            echo "Error: '$1' flag is not recognized, skipping..." >&2
            ;;
        
        # Assume arg is path. Fix path to be relative to root of the git repo instead of user's terminal pwd.
        *)
            if [ -n "$CALLER_SUBDIR" ]; then
                case $1 in
                    ".")
                        echo "DEBUG: '$1' -> '$CALLER_SUBDIR'" >&2
                        parsed_file_path_args+=("$CALLER_SUBDIR")
                        ;;
                    *)
                        echo "DEBUG: prepend '$1'" >&2
                        parsed_file_path_args+=("${CALLER_SUBDIR}${1}")
                        ;;
                esac
            else
                echo "DEBUG: Don't prepend '$1'" >&2
                parsed_file_path_args+=("$1")
            fi
            ;;
    esac
    shift
done

# ==============================================================================================
#                                   Restore Staged FCStd files
# ==============================================================================================
# Get staged `.FCStd` files
# Diff Filter => (A)dded / (C)opied / (D)eleted / (M)odified / (R)enamed / (T)ype changed / (U)nmerged / (X) unknown / (B)roken pairing
git update-index --refresh -q >/dev/null 2>&1
STAGED_FCSTD_FILES=$(git diff-index --cached --name-only --diff-filter=CDMRTUXB HEAD | grep -i -- '\.fcstd$')

if [ -n "$STAGED_FCSTD_FILES" ]; then
    mapfile -t STAGED_FCSTD_FILES <<<"$STAGED_FCSTD_FILES"
    git restore --staged "${STAGED_FCSTD_FILES[@]}"
fi

# ==============================================================================================
#                              Clear Modifications For Specified Files
# ==============================================================================================
RESET_MOD=$TRUE git add "${parsed_file_path_args[@]}"