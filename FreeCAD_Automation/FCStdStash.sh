#!/bin/bash
# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Ensure working dir is the root of the repo
# GIT_ROOT=$(git rev-parse --show-toplevel)
# cd "$GIT_ROOT"

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
FIRST_ARG="$1"

# ==============================================================================================
#                                   Execute Stash n' Import
# ==============================================================================================
if [ "$FIRST_ARG" = "pop" ] || [ "$FIRST_ARG" = "apply" ]; then
    echo "DEBUG: Stash application detected" >&2
    # Execute git stash pop/apply
    git stash "$@"
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne 0 ]; then
        echo "git stash $FIRST_ARG failed" >&2
        exit $STASH_RESULT
    fi

    # Check for changed lockfiles in the working dir (similar to post-checkout)
    for lockfile in $(git diff --name-only | grep -i '\.lockfile$'); do
        FCStd_file_path=$(get_FCStd_file_from_lockfile "$lockfile") || continue

        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        "$PYTHON_PATH" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo "Failed to import $FCStd_file_path" >&2
        }
        echo "SUCCESS" >&2
    done

else
    echo "DEBUG: Stashing away or something else..." >&2
    
    # Get modified lockfiles before stash
    BEFORE_STASH_LOCKFILES=$(git diff --name-only | grep -i '\.lockfile$')

    # Execute git stash
    git stash "$@"
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne 0 ]; then
        echo "git stash failed" >&2
        exit $STASH_RESULT
    fi

    # Get modified lockfiles after stash
    AFTER_STASH_LOCKFILES=$(git diff --name-only | grep -i '\.lockfile$')

    # Import the files that are no longer modified (those that were stashed)
    for lockfile in $BEFORE_STASH_LOCKFILES; do
        if ! echo "$AFTER_STASH_LOCKFILES" | grep -q "^$lockfile$"; then
            FCStd_file_path=$(get_FCStd_file_from_lockfile "$lockfile") || continue
            echo -n "IMPORTING: '$FCStd_file_path'...." >&2
            "$PYTHON_PATH" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
                echo "Failed to import $FCStd_file_path" >&2
            }
            echo "SUCCESS" >&2
        fi
    done
fi

exit $SUCCESS