#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to lock a .FCStd file for editing. Locks the associated .lockfile using Git LFS and makes the .FCStd file writable.
# Supports force locking to steal existing locks if user has perms to do so.

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
#                                          Parse Args
# ==============================================================================================
# `$(GIT_PREFIX:-.)`:
    # If caller is in $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller is in $GIT_ROOT, $(GIT_PREFIX) = ""
CALLER_SUBDIR=$1
shift

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_args=()
FORCE_FLAG=$FALSE
for arg in "$@"; do
    echo "DEBUG: parsing '$arg'..." >&2
    if [[ "$arg" == -* ]]; then
        if [ "$arg" == "--force" ]; then
            FORCE_FLAG=$TRUE
            echo "DEBUG: FORCE_FLAG set" >&2
        fi
    else
        if [ "$CALLER_SUBDIR" != "" ]; then
            echo "DEBUG: prepend '$arg'" >&2
            parsed_args+=("$CALLER_SUBDIR$arg")
        else
            echo "DEBUG: Don't prepend '$arg'" >&2
            parsed_args+=("$arg")
        fi
    fi
done
echo "DEBUG: Args='$parsed_args'" >&2

# ==============================================================================================
#                                          Lock File
# ==============================================================================================
# Ensure num args shouldn't exceed 2 and if 2, 1 arg must be --force flag, the other the path, else if just 1 arg it should just be the path.
if [ ${#parsed_args[@]} != 1 ]; then
    echo "Error: Invalid arguments. Usage: lock.sh path/to/file.FCStd [--force]" >&2
    exit $FAIL
fi

FCStd_file_path="${parsed_args[0]}"
if [ -z "$FCStd_file_path" ]; then
    echo "Error: No file path provided" >&2
    exit $FAIL
fi

lockfile_path=$("$PYTHON_EXEC" "$FCStdFileTool" --CONFIG-FILE --lockfile "$FCStd_file_path") || {
    echo "Error: Failed to get lockfile path for '$FCStd_file_path'" >&2
    exit $FAIL
}

if [ "$FORCE_FLAG" == "$TRUE" ]; then
    # Check if locked by someone else
    LOCK_INFO=$(git lfs locks --path="$lockfile_path")
    CURRENT_USER=$(git config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        exit $FAIL
    }

    echo "DEBUG: Stealing..." >&2
    
    if echo "$LOCK_INFO" | grep -q "$CURRENT_USER"; then
        echo "DEBUG: lock already owned, no need to steal." >&2
        :
    
    elif [ -n "$LOCK_INFO" ]; then
        echo "DEBUG: Forcefully unlocking..." >&2
        git lfs unlock --force "$lockfile_path" || exit $FAIL
    fi
fi

git lfs lock "$lockfile_path" || exit $FAIL

make_writable "$FCStd_file_path" || exit $FAIL
echo "DEBUG: '$FCStd_file_path' now writable and locked" >&2

exit $SUCCESS