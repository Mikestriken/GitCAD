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
            fi
        else
            parsed_args+=("$CALLER_SUBDIR$arg")
        fi
    done
else
    parsed_args=("$@")
fi

# ==============================================================================================
#                                          Lock File
# ==============================================================================================
# Ensure num args shouldn't exceed 2 and if 2, 1 arg must be --force flag, the other the path, else if just 1 arg it should just be the path.
if [ ${#parsed_args[@]} != 1 ]; then
    echo "Error: Invalid arguments. Usage: lock.sh path/to/file.FCStd [--force]" >&2
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

if [ "$FORCE_FLAG" == 1 ]; then
    # Check if locked by someone else
    LOCK_INFO=$(git lfs locks --path="$lockfile_path")
    CURRENT_USER=$(git config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        exit 1
    }
    if echo "$LOCK_INFO" | grep -q "$CURRENT_USER"; then
        # Already locked by us, no need to force_FLAG
        :
    elif [ -n "$LOCK_INFO" ]; then
        # Locked by someone else, force_FLAG unlock
        git lfs unlock --force "$lockfile_path" || {
            echo "Error: Failed to force unlock $lockfile_path" >&2
            exit 1
        }
    fi
fi

git lfs lock "$lockfile_path" || {
    echo "Error: Failed to lock $lockfile_path" >&2
    exit 1
}

make_writable "$FCStd_file_path" || exit 1