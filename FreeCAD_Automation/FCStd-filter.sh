#!/bin/bash
echo "DEBUG: Clean filter trap-card triggered!" >&2
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
#                           Early Exits Before Exporting .FCStd file
# ==============================================================================================
# Note: cat /dev/null is printed to stdout, makes git think the .FCStd file is empty

# print all args to stderr
# echo "DEBUG: All args: '$@'" >&2

# Note: when running `git status` sometimes this clean filter will be called. Read more here: https://stackoverflow.com/questions/41934945/why-does-git-status-run-filters
    # If the user uses the alias `git stat` the the STATUS_CALL env variable will be set during the git status call.
    # If the environment variable is detected then exit early without exporting FCStd files

    # $RESET_MOD is an environment variable set by the alias `git clearFCStdMod``
if [[ -n "$STATUS_CALL" || -n "$RESET_MOD" ]]; then
    echo "DEBUG: Status or reset mod call, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS
fi

# Note: When checking out a file the clean filter will parse the current file in the working dir (even if git shows no changes)
    # EG:
        # git checkout test_binaries -- ./FreeCAD_Automation/tests/*.FCStd
        # Parses empty .FCStd files with this script before importing the full binary file from test_binaries tag

    # Solution: If file is empty don't export and exit early with success
if [ ! -s "$1" ]; then
    echo "DEBUG: '$1' is empty, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS
fi

# ==============================================================================================
#                         Check if user allowed to modify .FCStd file
# ==============================================================================================
if [[ "$BYPASS_LOCK" == "1" ]]; then
    echo "DEBUG: BYPASS_LOCK=1, bypassing lock check." >&2
else
    FCSTD_FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$1") || exit $FAIL

    # echo "DEBUG: FCSTD_FILE_HAS_VALID_LOCK='$FCSTD_FILE_HAS_VALID_LOCK'" >&2

    # ToDo?: Figure out WTF I'm doing here.. aborting or just not exporting?
    if [ "$FCSTD_FILE_HAS_VALID_LOCK" == "$FALSE" ]; then
        echo "ERROR: User doesn't have lock for '$1'... Aborting add operation..." >&2
        exit $FAIL
    fi
fi

# ==============================================================================================
#                                       Export the .FCStd file
# ==============================================================================================
# Note: cat /dev/null is printed to stdout, makes git think the .FCStd file is empty

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