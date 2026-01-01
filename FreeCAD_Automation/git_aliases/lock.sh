#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to lock a .FCStd file for editing. Locks the associated .lockfile using Git LFS and makes the .FCStd file writable.
# Supports force locking to steal existing locks if user has perms to do so.

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
CALLER_SUBDIR="$1"
shift

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_file_path_args=()
FORCE_FLAG=$FALSE
while [ $# -gt 0 ]; do
    # echo "DEBUG: parsing '$1'..." >&2
    case $1 in
        # Set boolean flag if arg is a valid flag
        "--force")
            FORCE_FLAG=$TRUE
            # echo "DEBUG: FORCE_FLAG set" >&2
            ;;
        
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
# echo "DEBUG: Args='$parsed_file_path_args'" >&2

# ==============================================================================================
#                                   Match Args to FCStd Files
# ==============================================================================================
MATCHED_FCStd_file_paths=()
for file_path in "${parsed_file_path_args[@]}"; do
    # echo "DEBUG: Matching file_path: '$file_path'...." >&2

    if [[ -d "$file_path" || "$file_path" == *"*"* || "$file_path" == *"?"* ]]; then
        # echo "DEBUG: file_path contains wildcards or is a directory" >&2
        
        mapfile -t FCStd_files_matching_pattern < <(GIT_COMMAND="ls-files" git ls-files -- "$file_path")
        for file in "${FCStd_files_matching_pattern[@]}"; do
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

else
    echo "Error: No valid .FCStd files found. Usage: lock.sh [path/to/file.FCStd ...] [--force]" >&2
    exit $FAIL
fi

# echo "DEBUG: matched '${#MATCHED_FCStd_file_paths[@]}' .FCStd files: '${MATCHED_FCStd_file_paths[@]}'" >&2

# ==============================================================================================
#                                          Lock Files
# ==============================================================================================
for FCStd_file_path in "${MATCHED_FCStd_file_paths[@]}"; do
    # echo "DEBUG: Processing FCStd file: '$FCStd_file_path'" >&2

    FCStd_dir_path="$(get_FCStd_dir "$FCStd_file_path")" || continue
    lockfile_path="$FCStd_dir_path/.lockfile"

    if [ "$FORCE_FLAG" = "$TRUE" ]; then
        # Check if locked by someone else
        LOCK_INFO="$(GIT_COMMAND="lfs" git lfs locks --path="$lockfile_path")"
        CURRENT_USER="$(GIT_COMMAND="config" git config --get user.name)" || {
            echo "Error: git config user.name not set!" >&2
            exit $FAIL
        }

        # echo "DEBUG: Stealing..." >&2
        
        if printf '%s\n' "$LOCK_INFO" | grep -Fq -- "$CURRENT_USER"; then
            # echo "DEBUG: lock already owned, no need to steal." >&2
            :
        
        elif [ -n "$LOCK_INFO" ]; then
            # echo "DEBUG: Forcefully unlocking..." >&2
            GIT_COMMAND="lfs" git lfs unlock --force "$lockfile_path" || continue
        fi
    fi

    echo -n "LOCKING: '$FCStd_file_path'...." >&2

    lock_output="$(GIT_COMMAND="lfs" git lfs lock "$lockfile_path" 2>&1)"

    if [ $? -eq $SUCCESS ]; then
        echo "SUCCESS" >&2
    else
        echo "Error: '$lock_output'" >&2
        if [ ${#MATCHED_FCStd_file_paths[@]} -eq 1 ]; then
            exit $FAIL
        
        else
            continue
        fi
    fi

    make_writable "$FCStd_file_path" || continue
    # echo "DEBUG: '$FCStd_file_path' now writable and locked" >&2
done

exit $SUCCESS