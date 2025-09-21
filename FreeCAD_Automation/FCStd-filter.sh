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

# print all args to stderr
# echo "DEBUG: All args: '$@'" >&2


# ==============================================================================================
#                         Check if user allowed to modify .FCStd file
# ==============================================================================================
FCSTD_FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$1") || exit 1

# echo "DEBUG: FCSTD_FILE_HAS_VALID_LOCK='$FCSTD_FILE_HAS_VALID_LOCK'" >&2

if [ $FCSTD_FILE_HAS_VALID_LOCK == 0 ]; then
    # echo "DEBUG: '$1' has INVALID lock.... EXIT FAIL (Clean Filter)" >&2
    exit $FAIL
fi

# ==============================================================================================
#                                       Export the .FCStd file
# ==============================================================================================
# Note: cat /dev/null is printed to stdout, makes git think the .FCStd file is empty

# Note: When checking out a file the clean filter will parse the current file in the working dir (even if git shows no changes)
    # EG:
        # git checkout test_binaries -- ./FreeCAD_Automation/tests/*.FCStd
        # Parses empty .FCStd files with this script before importing the full binary file from test_binaries tag

# Note: when running `git status` sometimes this clean filter will be called
# ToDo: if a git status calls this script don't perform extract operations

echo "STATUS_CALL is set to: '$STATUS_CALL'" >&2

# If file is empty exit don't export and early (success)
if [ ! -s "$1" ]; then
    # echo "DEBUG: '$1' is empty, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS
fi

# Export the .FCStd file
echo -n "EXPORTING: '$1'...." >&2
if "$PYTHON_PATH" "$FCStdFileTool" --SILENT --CONFIG-FILE --export "$1" > /dev/null; then
    echo "SUCCESS" >&2
    cat /dev/null
    exit $SUCCESS
    
else
    echo "FAIL, Rolling back git operation" >&2
    exit $FAIL
fi