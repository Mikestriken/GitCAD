#!/bin/bash
echo "DEBUG: FCStd file checkout trap-card triggered!" >&2
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

changed_files=$(git diff --name-only HEAD) # Note: includes staged files
echo "DEBUG: Changed files BEFORE checkout: '$changed_files'" >&2

# Collect dirs to checkout
declare -A dir_to_file
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

    # Skip if file has changes
    if echo "$changed_files" | grep -q "^$file$"; then
        echo "Error: '$file' has changes, commit them before running this operation. Skipping..." >&2
        continue
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
    dir_to_file["$FCStd_dir_path"]="$file"
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
echo "DEBUG: \`git checkout "$COMMIT_HASH" -- \"${dirs_to_checkout[@]}\"\`" >&2
git checkout "$COMMIT_HASH" -- "${dirs_to_checkout[@]}" || {
    echo "Error: Failed to checkout dirs from commit '$COMMIT_HASH'" >&2
    exit $FAIL
}

# Get changed files after checkout
changed_files=$(git ls-files -m) # Note: Excludes staged files
echo "DEBUG: Changed files AFTER checkout: '$changed_files'" >&2

# For each dir, check if it exists and import if it does
for dir in "${dirs_to_checkout[@]}"; do
    FCStd_file_path="${dir_to_file[$dir]}"
    FCStd_dir_path="$dir"

    echo "DEBUG: Checking '$FCStd_file_path' & '$FCStd_dir_path'" >&2

    if [ -d "$FCStd_dir_path" ] && echo "$changed_files" | grep -q "^$FCStd_dir_path/"; then
        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        # Import data to FCStd file
        "$PYTHON_PATH" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo "Error: Failed to import $FCStd_file_path, skipping..." >&2
            continue
        }
        echo "SUCCESS" >&2
    else
        echo "DEBUG: Dir '$FCStd_dir_path' does not exist or has no changes, skipping import for '$FCStd_file_path'" >&2
        continue
    fi

    # Handle locks
    if [ "$REQUIRE_LOCKS" == "$TRUE" ]; then
        FCSTD_FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$FCStd_file_path") || continue

        if [ "$FCSTD_FILE_HAS_VALID_LOCK" == "$FALSE" ]; then
            # User doesn't have lock, set .FCStd file to readonly
            make_readonly "$FCStd_file_path"
            echo "DEBUG: Set '$FCStd_file_path' readonly." >&2
        else
            # User has lock, set .FCStd file to writable
            make_writable "$FCStd_file_path"
            echo "DEBUG: Set '$FCStd_file_path' writable." >&2
        fi
    fi
done

exit $SUCCESS