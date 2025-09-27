#!/bin/sh
echo "DEBUG: post-rewrite hook trap-card triggered!" >&2
# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Ensure working dir is the root of the repo
# GIT_ROOT=$(git rev-parse --show-toplevel)
# cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
    echo "Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                                        Pull LFS files
# ==============================================================================================
git lfs pull
echo "DEBUG: Pulled lfs files" >&2

# ==============================================================================================
#                                      Execute Git Reset
# ==============================================================================================

# ==============================================================================================
#                           Update .FCStd files with uncompressed files
# ==============================================================================================