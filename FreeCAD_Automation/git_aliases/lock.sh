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
CALLER_SUBDIR=$1
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
#                                          Lock File
# ==============================================================================================
# Ensure num args shouldn't exceed 2 and if 2, 1 arg must be --force flag, the other the path, else if just 1 arg it should just be the path.
if [ ${#parsed_file_path_args[@]} != 1 ]; then
    echo "Error: Invalid arguments. Usage: lock.sh path/to/file.FCStd [--force]" >&2
    exit $FAIL
fi

FCStd_file_path="${parsed_file_path_args[0]}"
if [ -z "$FCStd_file_path" ]; then
    echo "Error: No file path provided" >&2
    exit $FAIL
fi

FCStd_dir_path=$(get_FCStd_dir "$FCStd_file_path") || exit $FAIL
lockfile_path="$FCStd_dir_path/.lockfile"

if [ "$FORCE_FLAG" = "$TRUE" ]; then
    # Check if locked by someone else
    LOCK_INFO=$(git lfs locks --path="$lockfile_path")
    CURRENT_USER=$(git config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        exit $FAIL
    }

    # echo "DEBUG: Stealing..." >&2
    
    if printf '%s\n' "$LOCK_INFO" | grep -Fq -- "$CURRENT_USER"; then
        # echo "DEBUG: lock already owned, no need to steal." >&2
        :
    
    elif [ -n "$LOCK_INFO" ]; then
        # echo "DEBUG: Forcefully unlocking..." >&2
        git lfs unlock --force "$lockfile_path" || exit $FAIL
    fi
fi

git lfs lock "$lockfile_path" || exit $FAIL

make_writable "$FCStd_file_path" || exit $FAIL
# echo "DEBUG: '$FCStd_file_path' now writable and locked" >&2

exit $SUCCESS