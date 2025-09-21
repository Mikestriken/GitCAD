#!/bin/bash
# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Check if inside a Git repository and ensure working dir is the root of the repo
if ! git rev-parse --git-dir > /dev/null; then
    echo "Error: Not inside a Git repository" >&2
    exit 1
fi

GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/functions.sh"
source "$FUNCTIONS_FILE"

CONFIG_FILE="FreeCAD_Automation/git-freecad-config.json"
FCStdFileTool="FreeCAD_Automation/FCStdFileTool.py"

# Extract Python path
PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || exit 1

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
FORCE_FLAG=0
if [ "$CALLER_SUBDIR" != "" ]; then
    for arg in "$@"; do
        if [[ "$arg" == -* ]]; then
            if [ "$arg" == "--force" ]; then
                FORCE_FLAG=1
                echo "DEBUG: FORCE_FLAG set" >&2
            fi
        else
            parsed_args+=("$CALLER_SUBDIR$arg")
        fi
    done
else
    parsed_args=("$@")
fi
echo "DEBUG: Args='$parsed_args'" >&2

# ==============================================================================================
#                                          Unlock File
# ==============================================================================================
# Ensure valid args
if [ ${#parsed_args[@]} != 1 ]; then
    echo "Error: Invalid arguments. Usage: unlock.sh path/to/file.FCStd [--force]" >&2
    exit 1
fi

FCStd_file_path="${parsed_args[0]}"
if [ -z "$FCStd_file_path" ]; then
    echo "Error: No file path provided" >&2
    exit 1
fi

lockfile_path=$("$PYTHON_PATH" "$FCStdFileTool" --CONFIG-FILE --lockfile "$FCStd_file_path") || {
    echo "Error: Failed to get lockfile path for '$FCStd_file_path'" >&2
    exit 1
}

FCStd_dir_path=$(dirname "$lockfile_path")

# Check for unpushed changes if not force
if [ "$FORCE_FLAG" == 0 ]; then
    # ToDo: Failsafe is user is in detached head mode.
    BRANCH=$(git branch --show-current)
    UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
    REFERENCE_BRANCH=""

    if [ -n "$UPSTREAM" ]; then
        # Use upstream if it exists
        REFERENCE_BRANCH="$UPSTREAM"
        echo "DEBUG: Found upstream reference='$REFERENCE_BRANCH'" >&2
    else
        # Find the remote branch with the closest merge-base (fewest commits)
        smallest_num_commits_to_merge_base=999999
        REMOTE_BRANCHES=$(git branch -r 2>/dev/null | xargs)
        for remote_branch in $REMOTE_BRANCHES; do
            MERGE_BASE=$(git merge-base "$remote_branch" HEAD 2>/dev/null)
            if [ -n "$MERGE_BASE" ]; then
                num_commits_to_merge_base=$(git rev-list --count "$MERGE_BASE..HEAD" 2>/dev/null)
                if [ "$num_commits_to_merge_base" -lt "$smallest_num_commits_to_merge_base" ]; then
                    smallest_num_commits_to_merge_base="$num_commits_to_merge_base"
                    REFERENCE_BRANCH="$remote_branch"
                    echo "DEBUG: $smallest_num_commits_to_merge_base commits away is '$REFERENCE_BRANCH'" >&2
                fi
            fi
        done
        echo "DEBUG: Closest reference='$REFERENCE_BRANCH'" >&2
    fi

    if [ -n "$REFERENCE_BRANCH" ]; then
        DIR_HAS_CHANGES=$(dir_has_changes "$FCStd_dir_path" "$REFERENCE_BRANCH" "HEAD") || exit 1
        if [ "$DIR_HAS_CHANGES" == 1 ]; then
            echo "Error: Cannot unlock file with unpushed changes. Use --force to override." >&2
            exit 1
        fi
    fi

    # Check for stashed changes
    STASH_COUNT=$(git stash list | wc -l)
    for i in $(seq 0 $((STASH_COUNT - 1))); do
        echo "DEBUG: checking stash '$i'...." >&2
        if git stash show --name-only "stash@{$i}" 2>/dev/null | grep -q "^$FCStd_dir_path/"; then
            echo "Error: Cannot unlock file with stashed changes. Use --force to override." >&2
            exit 1
            break
        fi
    done
    echo "DEBUG: No uncommitted changes, clear to unlock!" >&2
fi


git lfs unlock "$lockfile_path" || {
    echo "Error: Failed to unlock $lockfile_path" >&2
    exit 1
}

make_readonly "$FCStd_file_path" || exit 1
echo "DEBUG: '$FCStd_file_path' now readonly" >&2