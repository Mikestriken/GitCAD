#!/bin/bash
# echo "DEBUG: ============== FCStd file checkout trap-card triggered! ==============" >&2
# ==============================================================================================
#                                        Script Overview
# ==============================================================================================
# Script to checkout specific .FCStd files from a given commit. 
# Handles resynchronization by reimporting data back into the .FCStd files that were checked out
# Ensures .FCStd file is readonly/writable per lock permissions after resynchronization.

# ==============================================================================================
#                                Verify and Retrieve Dependencies
# ==============================================================================================
# Note: PWD for all scripts called via git aliases is the root of the git repository

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# Note: Controlled by "FreeCAD_Automation/activate.sh" and "FreeCAD_Automation/git"
if [ "$GITCAD_ACTIVATED" = "$TRUE" ]; then
    git_path="$REAL_GIT"
else
    git_path="git"
fi

# ==============================================================================================
#                                      Pull LFS files
# ==============================================================================================
GIT_COMMAND="lfs" git lfs pull
# echo "DEBUG: Pulled lfs files" >&2

# ==============================================================================================
#                                           Parse Args
# ==============================================================================================
# CALLER_SUBDIR=${GIT_PREFIX}:
    # If caller's pwd is $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller's pwd is $GIT_ROOT, $(GIT_PREFIX) = ""
CALLER_SUBDIR="$1"
shift

# Parse arguments: CHECKOUT_COMMIT FILE [FILE ...] OR -- CHECKOUT_COMMIT FILE [FILE ...]
if [ $# -lt 2 ]; then
    echo "Error: Invalid arguments. Usage: git fco CHECKOUT_COMMIT FILE [FILE ...] OR git fco CHECKOUT_COMMIT -- FILE [FILE ...]" >&2
    exit $FAIL
fi

CHECKOUT_COMMIT="$1"
shift

# Note: In case user uses `git fco CHECKOUT_COMMIT -- FILE [FILE ...]` format
if [ "$1" = "--" ]; then
    shift
    
    if [ $# -lt 1 ]; then
        echo "Error: Invalid arguments. Usage: git fco CHECKOUT_COMMIT FILE [FILE ...] OR git fco CHECKOUT_COMMIT -- FILE [FILE ...]" >&2
        exit $FAIL
    fi
fi

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_file_path_args=()
while [ $# -gt 0 ]; do
    # echo "DEBUG: parsing '$1'..." >&2
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
                        # echo "DEBUG: '$1' -> '$CALLER_SUBDIR'" >&2
                        parsed_file_path_args+=("$CALLER_SUBDIR")
                        ;;
                    *)
                        # echo "DEBUG: prepend '$1'" >&2
                        parsed_file_path_args+=("${CALLER_SUBDIR}${1}")
                        ;;
                esac
            else
                # echo "DEBUG: Don't prepend '$1'" >&2
                parsed_file_path_args+=("$1")
            fi
            ;;
    esac
    shift
done

# ==============================================================================================
#                                     HEAD Checkout Edgecase
# ==============================================================================================
# Note: If checking out HEAD (resetting modified files), We also need to check if the FCStd_dir_path or FCStd_file_path is modified in the working directory PRIOR to checkout
HEAD_SHA="$(GIT_COMMAND="rev-parse" "$git_path" rev-parse HEAD)"
CHECKOUT_SHA="$(GIT_COMMAND="rev-parse" "$git_path" rev-parse "$CHECKOUT_COMMIT")"
IS_HEAD_CHECKOUT=$FALSE
changefiles_with_modifications_not_yet_committed=""

if [ "$HEAD_SHA" = "$CHECKOUT_SHA" ]; then
    # echo "DEBUG: Detected HEAD checkout (resetting modified files)" >&2
    
    IS_HEAD_CHECKOUT=$TRUE
    GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1

    # List of all modified changefiles
    changefiles_with_modifications_not_yet_committed="$(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.changefile$')"
    # echo "DEBUG: Found modified changefiles for HEAD checkout: $(echo "$changefiles_with_modifications_not_yet_committed" | xargs)" >&2
    
    FCStd_files_with_modifications_not_yet_committed="$(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.fcstd$')"
    # echo "DEBUG: Found modified FCStd files for HEAD checkout: $(echo "$FCStd_files_with_modifications_not_yet_committed" | xargs)" >&2
    
    # For each modified FCStd file, find its changefile and add it to the list of modified changefiles
    mapfile -t FCStd_files_with_modifications_not_yet_committed <<<"$FCStd_files_with_modifications_not_yet_committed"
    for FCStd_file_path in "${FCStd_files_with_modifications_not_yet_committed[@]}"; do
        [ -z "$FCStd_file_path" ] && continue
        
        # echo "DEBUG: Finding changefile for FCStd file: '$FCStd_file_path'" >&2
        FCStd_dir_path="$(get_FCStd_dir "$FCStd_file_path")" || continue
        changefile_path="$FCStd_dir_path/.changefile"

        if printf '%s\n' "$changefiles_with_modifications_not_yet_committed" | grep -Fxq -- "$changefile_path"; then
            # echo "DEBUG: '$changefile_path' already in list of modified changefiles" >&2
            continue
        else
            changefiles_with_modifications_not_yet_committed="$changefiles_with_modifications_not_yet_committed"$'\n'"$changefile_path"
            # echo "DEBUG: Added '$changefile_path' to list of modified changefiles" >&2
        fi
    done

    # echo "DEBUG: Found modified changefiles for HEAD checkout: $(echo "$changefiles_with_modifications_not_yet_committed" | xargs)" >&2
fi

# ==============================================================================================
#                                    Perform Initial Checkout
# ==============================================================================================
# Note: This is to checkout non-FCStd files
    # This checks out ALL files/patterns (including FCStd files and non-FCStd files)
    # FCStd files will be checked out again later (their uncompressed dirs), but this is fine
    # because we already captured the modification list before this checkout
# echo "DEBUG: Checking out '${parsed_file_path_args[@]}' from commit '$CHECKOUT_COMMIT'" >&2

# Note: `FILE_CHECKOUT_IN_PROGRESS=$TRUE` suppresses GitCAD activation warning message
FILE_CHECKOUT_IN_PROGRESS=$TRUE GIT_COMMAND="checkout" "$git_path" checkout "$CHECKOUT_COMMIT" -- "${parsed_file_path_args[@]}" > /dev/null  || {
    echo "Error: Failed to checkout files from commit '$CHECKOUT_COMMIT'" >&2
    exit $FAIL
}

# ==============================================================================================
#                                 Match Patterns to FCStd Files
# ==============================================================================================
MATCHED_FCStd_file_paths=()
for file_path in "${parsed_file_path_args[@]}"; do
    # echo "DEBUG: Matching file_path: '$file_path'...." >&2
    
    if [[ -d "$file_path" || "$file_path" == *"*"* || "$file_path" == *"?"* ]]; then
        # echo "DEBUG: file_path contains wildcards or is a directory" >&2
        
        mapfile -t files_matching_pattern < <(GIT_COMMAND="ls-files" "$git_path" ls-files "$file_path")
        for file in "${files_matching_pattern[@]}"; do
            if [[ "$file" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                # echo "DEBUG: Matched '$file'" >&2
                MATCHED_FCStd_file_paths+=("$file")
            fi
        done
        
    elif [[ "$file_path" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
        # echo "DEBUG: file_path is an FCStd file" >&2
        MATCHED_FCStd_file_paths+=("$file_path")
    else
        # echo "DEBUG: file_path '$file_path' is not an FCStd file, directory, or wildcard..... skipping" >&2
        :
    fi
done

if [ ${#MATCHED_FCStd_file_paths[@]} -gt 0 ]; then
    mapfile -t MATCHED_FCStd_file_paths < <(printf '%s\n' "${MATCHED_FCStd_file_paths[@]}" | sort -u) # Remove duplicates (creates an empty element if no elements)
fi

# echo "DEBUG: matched '${#MATCHED_FCStd_file_paths[@]}' FCStd files: '${MATCHED_FCStd_file_paths[@]}'" >&2

if [ ${#MATCHED_FCStd_file_paths[@]} -eq 0 ]; then
    # echo "DEBUG: No FCStd files matched the patterns" >&2
    exit $SUCCESS
fi

# ==============================================================================================
#            Get list of Matches that Actually Change Between Commits / Modified Dir
# ==============================================================================================
# For every FCStd_file_path matched with patterns, check if the corresponding FCStd_dir_path will change between commits
    # We'll only checkout dirs for files that will actually change between commits OR if it's currently modified (HEAD checkout case).
FCStd_dirs_to_checkout=()
declare -A FCStd_dir_to_file_dict # Bash Dictionary
changefiles_changed_between_commits="$(GIT_COMMAND="diff-tree" "$git_path" diff-tree --no-commit-id --name-only -r "$CHECKOUT_COMMIT" HEAD | grep -i -- '\.changefile$')"
for FCStd_file_path in "${MATCHED_FCStd_file_paths[@]}"; do
    # echo "DEBUG: Processing FCStd file: '$FCStd_file_path'" >&2
    
    FCStd_dir_path="$(get_FCStd_dir "$FCStd_file_path")" || continue
    changefile_path="$FCStd_dir_path/.changefile"
    
    if printf '%s\n' "$changefiles_changed_between_commits" | grep -Fxq -- "$changefile_path" || printf '%s\n' "$changefiles_with_modifications_not_yet_committed" | grep -Fxq -- "$changefile_path"; then
        FCStd_dir_to_file_dict["$FCStd_dir_path"]="$FCStd_file_path"
        FCStd_dirs_to_checkout+=("$FCStd_dir_path")
        # echo "DEBUG: Added '$FCStd_dir_path' to checkout list (changefile has changes or is modified)" >&2
    else
        # echo "DEBUG: Skipping '$FCStd_dir_path' (no changefile changes between $CHECKOUT_COMMIT and HEAD, and not modified)" >&2
        :
    fi
done

if [ ${#FCStd_dirs_to_checkout[@]} -gt 0 ]; then
    mapfile -t FCStd_dirs_to_checkout < <(printf '%s\n' "${FCStd_dirs_to_checkout[@]}" | sort -u) # Remove duplicates (creates an empty element if no elements)
fi

# echo "DEBUG: matched '${#FCStd_dirs_to_checkout[@]}' FCStd dirs: '${FCStd_dirs_to_checkout[@]}'" >&2

if [ ${#FCStd_dirs_to_checkout[@]} -eq 0 ]; then
    # echo "DEBUG: No FCStd files with changefile changes to checkout" >&2
    exit $SUCCESS
fi

# ==============================================================================================
#                                    File Checkout FCStd Dirs
# ==============================================================================================
# echo "DEBUG: Checking out dirs from commit '$CHECKOUT_COMMIT': ${FCStd_dirs_to_checkout[@]}" >&2

# Note: `FILE_CHECKOUT_IN_PROGRESS=$TRUE` suppresses GitCAD activation warning message
FILE_CHECKOUT_IN_PROGRESS=$TRUE GIT_COMMAND="checkout" "$git_path" checkout "$CHECKOUT_COMMIT" -- "${FCStd_dirs_to_checkout[@]}" > /dev/null 2>&1  || {
    echo "Error: Failed to checkout dirs from commit '$CHECKOUT_COMMIT'" >&2
    exit $FAIL
}

# ==============================================================================================
#                         Synchronize / Import FCStd Dirs to FCStd Files
# ==============================================================================================
# Import data from checked out FCStd dirs into their FCStd files
for FCStd_dir_path in "${FCStd_dirs_to_checkout[@]}"; do
    FCStd_file_path="${FCStd_dir_to_file_dict[$FCStd_dir_path]}"
    
    echo -n "IMPORTING: '$FCStd_file_path'...." >&2
    
    # Import data to FCStd file
    "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
        echo >&2
        echo "Error: Failed to import '$FCStd_file_path', skipping..." >&2
        continue
    }
    
    echo "SUCCESS" >&2
    
    # Only clear modification flag when checking out HEAD (resetting modified files)
    if [ "$IS_HEAD_CHECKOUT" = "$TRUE" ]; then
        GIT_COMMAND="fcmod" "$git_path" fcmod "$FCStd_file_path"
        # echo "DEBUG: Cleared modification flag for '$FCStd_file_path' (HEAD checkout)" >&2
    fi

    # Handle locks
    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || continue

        if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
            # User doesn't have lock, set .FCStd file to readonly
            make_readonly "$FCStd_file_path"
            # echo "DEBUG: Set '$FCStd_file_path' readonly." >&2
        else
            # User has lock, set .FCStd file to writable
            make_writable "$FCStd_file_path"
            # echo "DEBUG: Set '$FCStd_file_path' writable." >&2
        fi
    fi
done

exit $SUCCESS