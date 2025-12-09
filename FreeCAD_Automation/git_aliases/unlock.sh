#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to unlock a previously locked .FCStd file. Unlocks the associated .lockfile using Git LFS and makes the .FCStd file readonly.
# Checks for unpushed changes and warns if unlocking before changes are pushed. Supports force unlocking.

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
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
# `$(GIT_PREFIX:-.)`:
    # If caller is in $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller is in $GIT_ROOT, $(GIT_PREFIX) = ""
CALLER_SUBDIR=$1
shift

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_args=()
FORCE_FLAG=$FALSE
for arg in "$@"; do
    # echo "DEBUG: parsing '$arg'..." >&2
    if [[ "$arg" == -* ]]; then
        if [ "$arg" == "--force" ]; then
            FORCE_FLAG=$TRUE
            # echo "DEBUG: FORCE_FLAG set" >&2
        fi
    
    else
        if [ "$CALLER_SUBDIR" != "" ]; then
            if [ "$arg" = "." ]; then
                # echo "DEBUG: '$arg' -> '$CALLER_SUBDIR'" >&2
                parsed_args+=("$CALLER_SUBDIR")
            else
                # echo "DEBUG: prepend '$arg'" >&2
                parsed_args+=("$CALLER_SUBDIR$arg")
            fi
        
        else
            # echo "DEBUG: Don't prepend '$arg'" >&2
            parsed_args+=("$arg")
        fi
    fi
done
# echo "DEBUG: Args='$parsed_args'" >&2

# ==============================================================================================
#                                          Unlock File
# ==============================================================================================
# Ensure valid args
if [ ${#parsed_args[@]} != 1 ]; then
    echo "Error: Invalid arguments. Usage: unlock.sh path/to/file.FCStd [--force]" >&2
    exit $FAIL
fi

FCStd_file_path="${parsed_args[0]}"
if [ -z "$FCStd_file_path" ]; then
    echo "Error: No file path provided" >&2
    exit $FAIL
fi

FCStd_dir_path=$(get_FCStd_dir "$FCStd_file_path") || exit $FAIL
lockfile_path="$FCStd_dir_path/.lockfile"

# Check for unpushed changes if not force
if [ "$FORCE_FLAG" == "$FALSE" ]; then
    # ToDo? Consider bringing back using upstream branch as reference first if it exists?
        # UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
        # if [ -n "$UPSTREAM" ]; then; REFERENCE_BRANCH="$UPSTREAM"; fi;

    # echo "DEBUG: Looking for closest reference branch..." >&2

    # Reference the remote branch with the closest merge-base (fewest commits)
    mapfile -t REMOTE_BRANCHES < <(git branch -r 2>/dev/null | sed -e 's/ -> /\n/g' -e 's/^[[:space:]]*//')
    FIRST_MERGE_BASE=$(git merge-base "${REMOTE_BRANCHES[0]}" HEAD 2>/dev/null)
    
    REFERENCE_BRANCH=${REMOTE_BRANCHES[0]}
    smallest_num_commits_to_merge_base=$(git rev-list --count "$FIRST_MERGE_BASE..HEAD" 2>/dev/null)
    # echo "DEBUG: Initial guess: '$REFERENCE_BRANCH' @ '$smallest_num_commits_to_merge_base' commits away" >&2
    
    # echo "DEBUG: List to try='${REMOTE_BRANCHES[@]}'" >&2
    for remote_branch in ${REMOTE_BRANCHES[@]}; do
        MERGE_BASE=$(git merge-base "$remote_branch" HEAD 2>/dev/null)
        # echo "DEBUG: Trying '$remote_branch' @ hash '$MERGE_BASE'" >&2
        
        if [ -n "$MERGE_BASE" ]; then
            num_commits_to_merge_base=$(git rev-list --count "$MERGE_BASE..HEAD" 2>/dev/null)
            
            if [ "$num_commits_to_merge_base" -lt "$smallest_num_commits_to_merge_base" ]; then
                smallest_num_commits_to_merge_base="$num_commits_to_merge_base"
                REFERENCE_BRANCH="$remote_branch"
                # echo "DEBUG: $smallest_num_commits_to_merge_base commits away is '$REFERENCE_BRANCH'" >&2
            fi
        fi
    done
    # echo "DEBUG: Closest reference='$REFERENCE_BRANCH'" >&2

    if [ -n "$REFERENCE_BRANCH" ]; then
        DIR_HAS_CHANGES=$(dir_has_changes "$FCStd_dir_path" "$REFERENCE_BRANCH" "HEAD") || exit $FAIL

        if [ "$DIR_HAS_CHANGES" == "$TRUE" ]; then
            echo "Error: Cannot unlock file with unpushed changes. Use --force to override." >&2
            exit $FAIL
        fi
    fi

    # Check for stashed changes
    STASH_COUNT=$(git stash list | wc -l)
    for i in $(seq 0 $((STASH_COUNT - 1))); do
        # echo "DEBUG: checking stash '$i'...." >&2
        
        if git stash show --name-only "stash@{$i}" 2>/dev/null | grep -q "^$FCStd_dir_path/"; then
            echo "Error: Cannot unlock file with stashed changes. Use --force to override." >&2
            exit $FAIL
            break
        fi
    done
    # echo "DEBUG: No uncommitted changes to '$FCStd_dir_path', clear to unlock!" >&2
fi

if [ "$FORCE_FLAG" == "$TRUE" ]; then
    git lfs unlock --force "$lockfile_path" || exit $FAIL
    
else
    git lfs unlock "$lockfile_path" || exit $FAIL
fi

make_readonly "$FCStd_file_path" || exit $FAIL
# echo "DEBUG: '$FCStd_file_path' now readonly" >&2

exit $SUCCESS