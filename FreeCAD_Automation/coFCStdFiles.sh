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

# Parse arguments: COMMIT_HASH FILE [FILE ...]
if [ $# -lt 2 ]; then
    echo "Error: Invalid arguments. Usage: coFCStdFiles.sh COMMIT_HASH FILE [FILE ...]" >&2
    exit $FAIL
fi

COMMIT_HASH=$1
shift
FILES=("$@")

# Collect dirs to checkout
dirs_to_checkout=()
for file in "${FILES[@]}"; do
    # Check for wildcards in file names (not supported)
    if [[ "$file" == *[*?]* ]]; then
        echo "Error: Wildcards not supported in file names. Please specify exact file paths." >&2
        exit $FAIL
    fi

    # Prepend CALLER_SUBDIR if set
    if [ "$CALLER_SUBDIR" != "" ]; then
        file="$CALLER_SUBDIR$file"
    fi

    # Ensure file has .fcstd extension (case insensitive)
    if ! echo "$file" | grep -iq '\.fcstd$'; then
        echo "Error: '$file' is not a .FCStd file, skipping..." >&2
        continue
    fi

    FCStd_dir_path=$(get_FCStd_dir "$file") || {
        echo "Error: Failed to get directory path for '$file', skipping..." >&2
        continue
    }
    dirs_to_checkout+=("$FCStd_dir_path")
done

if [ ${#dirs_to_checkout[@]} -eq 0 ]; then
    echo "Error: No valid files to checkout" >&2
    exit $FAIL
fi

# ==============================================================================================
#                                      File Checkout Logic
# ==============================================================================================

# Checkout the uncompressed dirs from the commit
echo "DEBUG: Checking out dirs from commit '$COMMIT_HASH': ${dirs_to_checkout[*]}" >&2
git checkout "$COMMIT_HASH" -- "${dirs_to_checkout[@]}" || {
    echo "Error: Failed to checkout dirs from commit '$COMMIT_HASH'" >&2
    exit $FAIL
}

# Get changed files after checkout
changed_files=$(git diff --name-only)
echo "DEBUG: Changed files after checkout: '$changed_files'" >&2

# For each file, check if dir exists and import if it does
for file in "${FILES[@]}"; do
    if [ "$CALLER_SUBDIR" != "" ]; then
        file="$CALLER_SUBDIR$file"
    fi

    FCStd_dir_path=$(get_FCStd_dir "$file") || continue

    echo "DEBUG: Processing '$file' with dir '$FCStd_dir_path'" >&2

    if [ -d "$FCStd_dir_path" ] && echo "$changed_files" | grep -q "^$FCStd_dir_path/"; then
        echo "DEBUG: Dir has has modifications, importing changes to '$file'..." >&2

        # Import data to FCStd file
        "$PYTHON_PATH" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$file" || {
            echo "Error: Failed to import $file, skipping..." >&2
            continue
        }
    else
        echo "DEBUG: Dir '$FCStd_dir_path' does not exist, skipping import for '$file'" >&2
        continue
    fi

    # Handle locks
    if [ "$REQUIRE_LOCKS" == "1" ]; then
        FCSTD_FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$file") || continue

        if [ "$FCSTD_FILE_HAS_VALID_LOCK" == "0" ]; then
            # User doesn't have lock, set .FCStd file to readonly
            make_readonly "$file"
            echo "DEBUG: Set '$file' readonly." >&2
        else
            # User has lock, set .FCStd file to writable
            make_writable "$file"
            echo "DEBUG: Set '$file' writable." >&2
        fi
    fi
done

exit $SUCCESS