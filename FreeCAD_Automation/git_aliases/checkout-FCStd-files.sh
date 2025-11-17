#!/bin/bash
echo "DEBUG: FCStd file checkout trap-card triggered!" >&2
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to checkout specific .FCStd files from a given commit. 
# Handles resynchronization by reimporting data back into the .FCStd files that were checked out
# Ensures .FCStd file is readonly/writable per lock permissions after resynchronization.

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

# Parse arguments: CHECKOUT_COMMIT FILE [FILE ...]
if [ $# -lt 2 ]; then
    echo "Error: Invalid arguments. Usage: fco.sh CHECKOUT_COMMIT FILE [FILE ...]" >&2
    exit $FAIL
fi

CHECKOUT_COMMIT=$1
shift
PATTERNS=("$@")

# For every FCStd_file_path matched with patterns, check if the corresponding FCStd_dir_path will change between commits
    # If checking out HEAD (resetting modified files)
        # We also need to check if the FCStd_dir_path is modified in the working directory
    # We'll only checkout dirs for files that will actually be change between commits OR if it's currently modified (HEAD checkout case).
HEAD_SHA=$(git rev-parse HEAD)
CHECKOUT_SHA=$(git rev-parse "$CHECKOUT_COMMIT")
IS_HEAD_CHECKOUT=$FALSE
changefiles_with_modifications_not_yet_committed=""

if [ "$HEAD_SHA" = "$CHECKOUT_SHA" ]; then
    echo "DEBUG: Detected HEAD checkout (resetting modified files)" >&2
    
    IS_HEAD_CHECKOUT=$TRUE
    git update-index --refresh -q >/dev/null 2>&1

    changefiles_with_modifications_not_yet_committed=$(git diff-index --name-only HEAD | grep -i '\.changefile$')
    
    FCStd_files_with_modifications_not_yet_committed=$(git diff-index --name-only HEAD | grep -i '\.fcstd$')
    
    for FCStd_file_path in $FCStd_files_with_modifications_not_yet_committed; do
        FCStd_dir_path=$(get_FCStd_dir "$FCStd_file_path") || continue
        changefile_path="$FCStd_dir_path/.changefile"

        if echo "$changefiles_with_modifications_not_yet_committed" | grep -Fxq "$changefile_path"; then
            continue
        else
            changefiles_with_modifications_not_yet_committed="$changefiles_with_modifications_not_yet_committed"$'\n'"$changefile_path"
        fi
    done

    echo "DEBUG: Found modified changefiles for HEAD checkout: $(echo $changefiles_with_modifications_not_yet_committed | xargs)" >&2
fi

MATCHED_FCStd_file_paths=()
for pattern in "${PATTERNS[@]}"; do
    # Prepend CALLER_SUBDIR if set
    if [ "$CALLER_SUBDIR" != "" ]; then
        pattern="$CALLER_SUBDIR$pattern"
    fi
    
    echo "DEBUG: Matching pattern: '$pattern'...." >&2
    
    if [[ -d "$pattern" || "$pattern" == *"*"* || "$pattern" == *"?"* ]]; then
        echo "DEBUG: Pattern contains wildcards or is a directory" >&2
        while IFS= read -r file; do
            if [[ "$file" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                MATCHED_FCStd_file_paths+=("$file")
            fi
        done < <(git ls-files "$pattern")
        
    elif [[ "$pattern" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
        echo "DEBUG: Pattern is an FCStd file" >&2
        MATCHED_FCStd_file_paths+=("$pattern")
    else
        echo "DEBUG: Pattern '$pattern' is not an FCStd file, directory, or wildcard..... skipping" >&2
    fi
done

MATCHED_FCStd_file_paths=($(printf '%s\n' "${MATCHED_FCStd_file_paths[@]}" | sort -u)) # Remove duplicates

echo "DEBUG: matched FCStd files: ${MATCHED_FCStd_file_paths[*]}" >&2

if [ ${#MATCHED_FCStd_file_paths[@]} -eq 0 ]; then
    echo "DEBUG: No FCStd files matched the patterns" >&2
    exit $SUCCESS
fi

FCStd_dirs_to_checkout=()
declare -A FCStd_dir_to_file_dict # Bash Dictionary
changefiles_changed_between_commits=$(git diff-tree --no-commit-id --name-only -r "$CHECKOUT_COMMIT" HEAD | grep -i '\.changefile$')
for FCStd_file_path in "${MATCHED_FCStd_file_paths[@]}"; do
    echo "DEBUG: Processing FCStd file: $FCStd_file_path" >&2
    
    FCStd_dir_path=$(get_FCStd_dir "$FCStd_file_path") || continue
    changefile_path="$FCStd_dir_path/.changefile"
    
    if echo "$changefiles_changed_between_commits" | grep -q "^$changefile_path$" || echo "$changefiles_with_modifications_not_yet_committed" | grep -q "^$changefile_path$"; then
        FCStd_dir_to_file_dict["$FCStd_dir_path"]="$FCStd_file_path"
        FCStd_dirs_to_checkout+=("$FCStd_dir_path")
        echo "DEBUG: Added '$FCStd_dir_path' to checkout list (changefile has changes or is modified)" >&2
    else
        echo "DEBUG: Skipping '$FCStd_dir_path' (no changefile changes between $CHECKOUT_COMMIT and HEAD, and not modified)" >&2
    fi
done

FCStd_dirs_to_checkout=($(printf '%s\n' "${FCStd_dirs_to_checkout[@]}" | sort -u)) # Remove duplicates from FCStd_dirs_to_checkout

if [ ${#FCStd_dirs_to_checkout[@]} -eq 0 ]; then
    echo "DEBUG: No FCStd files with changefile changes to checkout" >&2
    exit $SUCCESS
fi

# ==============================================================================================
#                                      File Checkout Logic
# ==============================================================================================

echo "DEBUG: Checking out dirs from commit '$CHECKOUT_COMMIT': ${FCStd_dirs_to_checkout[*]}" >&2

git checkout "$CHECKOUT_COMMIT" -- "${FCStd_dirs_to_checkout[@]}" > /dev/null 2>&1  || {
    echo "Error: Failed to checkout dirs from commit '$CHECKOUT_COMMIT'" >&2
    exit $FAIL
}

# Import data from checked out FCStd dirs into their FCStd files
for FCStd_dir_path in "${FCStd_dirs_to_checkout[@]}"; do
    FCStd_file_path="${FCStd_dir_to_file_dict[$FCStd_dir_path]}"
    
    echo -n "IMPORTING: '$FCStd_file_path'...." >&2
    
    # Import data to FCStd file
    "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
        echo "Error: Failed to import $FCStd_file_path, skipping..." >&2
        continue
    }
    
    echo "SUCCESS" >&2
    
    # Only clear modification flag when checking out HEAD (resetting modified files)
    if [ "$IS_HEAD_CHECKOUT" == "$TRUE" ]; then
        git fcmod "$FCStd_file_path"
        echo "DEBUG: Cleared modification flag for '$FCStd_file_path' (HEAD checkout)" >&2
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