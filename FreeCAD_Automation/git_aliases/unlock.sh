#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to unlock a previously locked .FCStd file. Unlocks the associated .lockfile using Git LFS and makes the .FCStd file readonly.
# Checks for unpushed changes and warns if unlocking before changes are pushed. Supports force unlocking.

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Note: PWD for all scripts called via git aliases is the root of the git repository

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ]; then
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
    echo "Error: No valid .FCStd files found. Usage: unlock.sh [path/to/file.FCStd ...] [--force]" >&2
    exit $FAIL
fi

# echo "DEBUG: matched '${#MATCHED_FCStd_file_paths[@]}' .FCStd files: '${MATCHED_FCStd_file_paths[@]}'" >&2

# ==============================================================================================
#                                   Find Closest Remote Branch                                  
# ==============================================================================================
if [ "$FORCE_FLAG" = "$FALSE" ]; then
    # ToDo? Consider bringing back using upstream branch as reference first if it exists?
        # UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)"
        # if [ -n "$UPSTREAM" ]; then; REFERENCE_BRANCH="$UPSTREAM"; fi;

    # echo "DEBUG: Looking for closest reference branch..." >&2

    # Reference the remote branch with the closest merge-base (fewest commits)
    mapfile -t REMOTE_BRANCHES < <(GIT_COMMAND="branch" git branch -r 2>/dev/null | sed -e 's/ -> /\n/g' -e 's/^[[:space:]]*//') # Convert line 'origin/HEAD -> origin/main' to 'origin/HEAD' and 'origin/main' lines
    FIRST_MERGE_BASE="$(GIT_COMMAND="merge-base" git merge-base "${REMOTE_BRANCHES[0]}" HEAD 2>/dev/null)"
    
    REFERENCE_BRANCH="${REMOTE_BRANCHES[0]}"
    smallest_num_commits_to_merge_base="$(GIT_COMMAND="rev-list" git rev-list --count "$FIRST_MERGE_BASE..HEAD" 2>/dev/null)"
    # echo "DEBUG: Initial guess: '$REFERENCE_BRANCH' @ '$smallest_num_commits_to_merge_base' commits away" >&2
    
    # echo "DEBUG: List to try='${REMOTE_BRANCHES[@]}'" >&2
    for remote_branch in "${REMOTE_BRANCHES[@]}"; do
        MERGE_BASE="$(GIT_COMMAND="merge-base" git merge-base "$remote_branch" HEAD 2>/dev/null)"
        # echo "DEBUG: Trying '$remote_branch' @ hash '$MERGE_BASE'" >&2
        
        if [ -n "$MERGE_BASE" ]; then
            num_commits_to_merge_base="$(GIT_COMMAND="rev-list" git rev-list --count "$MERGE_BASE..HEAD" 2>/dev/null)"
            
            if [ "$num_commits_to_merge_base" -lt "$smallest_num_commits_to_merge_base" ]; then
                smallest_num_commits_to_merge_base="$num_commits_to_merge_base"
                REFERENCE_BRANCH="$remote_branch"
                # echo "DEBUG: $smallest_num_commits_to_merge_base commits away is '$REFERENCE_BRANCH'" >&2
            fi
        fi
    done
    
    # echo "DEBUG: Closest reference='$REFERENCE_BRANCH'" >&2
    if [ -z "$REFERENCE_BRANCH" ]; then
        echo "Error: Couldn't find remote reference branch to diff unpushed changes!" >&2
        exit $FAIL
    fi
fi

# ==============================================================================================
#                                          Unlock Files
# ==============================================================================================
for FCStd_file_path in "${MATCHED_FCStd_file_paths[@]}"; do
    # echo "DEBUG: Processing FCStd file: '$FCStd_file_path'" >&2

    FCStd_dir_path="$(get_FCStd_dir "$FCStd_file_path")" || continue
    lockfile_path="$FCStd_dir_path/.lockfile"

    # Check for unpushed changes if not force
    if [ "$FORCE_FLAG" = "$FALSE" ]; then
        DIR_HAS_CHANGES="$(dir_has_changes "$FCStd_dir_path" "$REFERENCE_BRANCH" "HEAD")" || continue

        if [ "$DIR_HAS_CHANGES" = "$TRUE" ]; then
            echo "Error: Cannot unlock '$FCStd_file_path' with unpushed changes. Use --force to override." >&2
            if [ ${#MATCHED_FCStd_file_paths[@]} -eq 1 ]; then
                exit $FAIL
            
            else
                continue
            fi
        fi

        # Check for stashed changes
        STASH_COUNT="$(GIT_COMMAND="stash" git stash list | wc -l)"
        stashed_changes_found=$FALSE
        for i in $(seq 0 $((STASH_COUNT - 1))); do
            # echo "DEBUG: checking stash '$i'...." >&2
            
            stashed_files="$(GIT_COMMAND="stash" git stash show --name-only "stash@{$i}" 2>/dev/null)"

            if printf '%s\n' "$stashed_files" | grep -q -- "^$FCStd_dir_path/" || \
               printf '%s\n' "$stashed_files" | grep -Fxq -- "$FCStd_file_path"; then
                echo "Error: Cannot unlock '$FCStd_file_path' with stashed changes. Use --force to override." >&2
                stashed_changes_found=$TRUE
                break
            fi
        done

        if [ "$stashed_changes_found" = "$TRUE" ]; then
            if [ ${#MATCHED_FCStd_file_paths[@]} -eq 1 ]; then
                exit $FAIL
            
            else
                continue
            fi
        fi
        # echo "DEBUG: No uncommitted changes to '$FCStd_dir_path', clear to unlock!" >&2
    fi

    echo -n "UNLOCKING: '$FCStd_file_path'...." >&2
    if [ "$FORCE_FLAG" = "$TRUE" ]; then
        unlock_output="$(GIT_COMMAND="lfs" git lfs unlock --force "$lockfile_path" 2>&1)"
        
    else
        unlock_output="$(GIT_COMMAND="lfs" git lfs unlock "$lockfile_path" 2>&1)"
    fi

    if [ $? -eq $SUCCESS ]; then
        echo "SUCCESS" >&2
    else
        echo "Error: '$unlock_output'" >&2
        if [ ${#MATCHED_FCStd_file_paths[@]} -eq 1 ]; then
            exit $FAIL
        
        else
            continue
        fi
    fi

    make_readonly "$FCStd_file_path" || continue
    # echo "DEBUG: '$FCStd_file_path' now readonly" >&2
done

exit $SUCCESS