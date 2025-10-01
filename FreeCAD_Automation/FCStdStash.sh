#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Wrapper script to handle Git stash operations for .FCStd files. Ensures .FCStd files remain synchronized with their uncompressed directories.
# For stash pop/apply, checks that the user owns locks for stashed .lockfiles. Imports .FCStd files after pop/apply.
# For stashing, re-imports .FCStd files after stashing to keep them synchronized to with the working directory.

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

if [ "$REQUIRE_LOCKS" == "$TRUE" ]; then
    CURRENT_USER=$(git config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        exit $FAIL
    }

    CURRENT_LOCKS=$(git lfs locks | awk '$2 == "'$CURRENT_USER'" {print $1}') || {
        echo "Error: failed to list of active lock info." >&2
        exit $FAIL
    }
fi

# ==============================================================================================
#                                          Parse Args
# ==============================================================================================
FIRST_ARG="$1"
STASH_INDEX="$2"

# ==============================================================================================
#                                   Execute Stash n' Import
# ==============================================================================================
if [ "$FIRST_ARG" = "pop" ] || [ "$FIRST_ARG" = "apply" ]; then
    # echo "DEBUG: Stash application detected" >&2

    # Check that user has locks for stashed lockfiles
    if [ "$REQUIRE_LOCKS" == "$TRUE" ]; then
        if [ -n "$STASH_INDEX" ]; then
            STASH_REF="stash@{$STASH_INDEX}"
        else
            STASH_REF="stash@{0}"
        fi
        
        STASHED_LOCKFILES=$(git stash show --name-only "$STASH_REF" 2>/dev/null | grep -i '\.lockfile$' || true)

        # echo -e "\nDEBUG: checking stashed lockfiles: '$(echo $STASHED_LOCKFILES | xargs)'" >&2

        for lockfile in $STASHED_LOCKFILES; do
            if ! echo "$CURRENT_LOCKS" | grep -q "$lockfile"; then
                echo "ERROR: User does not have lock for $lockfile in stash" >&2
                exit $FAIL
            fi
        done
    fi

    # Execute git stash pop/apply
    STASH_CALL=1 git stash "$@"
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne 0 ]; then
        echo "git stash $FIRST_ARG failed" >&2
        exit $STASH_RESULT
    fi

    # Check for changed lockfiles in the working dir (similar to post-checkout)
    for lockfile in $(git diff-index --name-only HEAD | grep -i '\.lockfile$'); do
        FCStd_file_path=$(get_FCStd_file_from_lockfile "$lockfile") || continue

        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo "Failed to import $FCStd_file_path" >&2
        }
        echo "SUCCESS" >&2
    done

else
    # Check for uncommitted .FCStd files
    UNCOMMITTED_FCSTD_FILES=$(git diff-index --name-only HEAD | grep -i '\.fcstd$' || true)
    if [ -n "$UNCOMMITTED_FCSTD_FILES" ]; then
        echo "Error: Cannot stash .FCStd files, export them first with \`git add\`" >&2
        exit $FAIL
    fi

    # echo "DEBUG: Stashing away or something else..." >&2
    
    # Get modified lockfiles before stash
    BEFORE_STASH_LOCKFILES=$(git diff-index --name-only HEAD | grep -i '\.lockfile$' | sort)
    
    # echo "DEBUG: retrieved before stash lockfiles..." >&2

    # Execute git stash
    STASH_CALL=1 git stash "$@" # Note: Sometimes calls clean filter... other times not... really weird....
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne 0 ]; then
        echo "git stash failed" >&2
        exit $STASH_RESULT
    fi

    # Get modified lockfiles after stash
    AFTER_STASH_LOCKFILES=$(git diff-index --name-only HEAD | grep -i '\.lockfile$' | sort)

    # Find files present before stash but not after stash (files that were stashed)
    STASHED_LOCKFILES=$(comm -23 <(echo "$BEFORE_STASH_LOCKFILES") <(echo "$AFTER_STASH_LOCKFILES"))

    # echo -e "\nDEBUG: Importing stashed lockfiles: '$(echo $STASHED_LOCKFILES | xargs)'" >&2

    # Import the files that are no longer modified (those that were stashed)
    for lockfile in $STASHED_LOCKFILES; do
        FCStd_file_path=$(get_FCStd_file_from_lockfile "$lockfile") || continue
        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo "Failed to import $FCStd_file_path" >&2
        }
        echo "SUCCESS" >&2
        
        git fcmod "$FCStd_file_path"
    done
fi

exit $SUCCESS