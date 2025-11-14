#!/bin/bash
# echo "DEBUG: FCStdClearModification.sh trap-card triggered!" >&2
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to make git see a .FCStd file as empty (despite it containing data).
# If the file is already empty then to git it will show as not having any modifications in the working directory.
# First it makes sure there are no added .FCStd files then it calls `RESET_MOD=$TRUE git add` to clear the modification.

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
    echo "Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                                   Restore Staged FCStd files
# ==============================================================================================
# Get staged `.FCStd` files
# Diff Filter => (A)dded / (C)opied / (D)eleted / (M)odified / (R)enamed / (T)ype changed / (U)nmerged / (X) unknown / (B)roken pairing
git update-index --refresh -q >/dev/null 2>&1
STAGED_FCSTD_FILES=$(git diff-index --cached --name-only --diff-filter=CDMRTUXB HEAD | grep -i '\.fcstd$')

if [ -n "$STAGED_FCSTD_FILES" ]; then
    git restore --staged $STAGED_FCSTD_FILES
fi

# ==============================================================================================
#                              Clear Modifications For Specified Files
# ==============================================================================================
RESET_MOD=$TRUE git add "$@"