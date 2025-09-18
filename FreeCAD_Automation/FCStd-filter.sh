#!/bin/bash
# ==============================================================================================
#                                     Verify Dependencies
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
PYTHON_PATH=$(get_json_value "$CONFIG_FILE" "freecad-python-instance-path") || {
    echo "Error: get_json_value failed" >&2
    exit 1
}

if [ -z "$PYTHON_PATH" ]; then
    echo "Error: Python path is empty" >&2
    exit 1
fi

# Check if Python runs correctly
if ! "$PYTHON_PATH" --version > /dev/null; then
    echo "Error: Python does not run or path is invalid" >&2
    exit 1
fi

# Check if the import works
if ! "$PYTHON_PATH" -c "from freecad import project_utility as PU; print('Import successful')" > /dev/null; then
    echo "Error: Import 'from freecad import project_utility as PU' failed" >&2
    exit 1
fi
# ==============================================================================================
#                         Check if user allowed to modify .FCStd file
# ==============================================================================================
# Check if file is tracked and user has lock on the .lockfile
if git ls-files --error-unmatch "$1" > /dev/null; then
    # File is tracked, get the .lockfile path
    lockfile_path=$("$PYTHON_PATH" "$FCStdFileTool" --CONFIG-FILE --lockfile "$1") || {
        echo "lockfile path not returned for '$1'" >&2
        exit 1
    }

    # Check if .lockfile is tracked
    if git ls-files --error-unmatch "$lockfile_path" > /dev/null; then
        # .lockfile is tracked, check if user has lock
        LOCK_INFO=$(git lfs locks --path="$lockfile_path")
        
        CURRENT_USER=$(git config --get user.name) || {
            echo "git config user.name not set!" >&2
            exit 1
        }

        if ! echo "$LOCK_INFO" | grep -q "$CURRENT_USER"; then
            echo "Error: User doesn't have lock for $1" >&2
            exit 1
        fi
    fi
fi

# ==============================================================================================
#                                       Export the .FCStd file
# ==============================================================================================
# Export the .FCStd file
if ! "$PYTHON_PATH" "$FCStdFileTool" --SILENT --CONFIG-FILE --export "$1" > /dev/null; then
    echo "Error: Failed to export $1" >&2
    exit 1
fi

# ==============================================================================================
#                                     Show file as empty to git
# ==============================================================================================
cat /dev/null