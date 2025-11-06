#!/bin/bash
echo "DEBUG: Clean filter trap-card triggered!" >&2

# === TEMPORARY DEBUG LOGGING ===

# some git commands trigger this clean filter script silently (Stderr doesn't get printed), namely `git checkout` (see issue #8).

# This commented out log file printing can be used to help debug those cases.

# Note: I only tested this commented out logging code on linux, not windows.
# {
#     echo "=========================================="
#     echo "FILTER CALLED: $(date '+%Y-%m-%d %H:%M:%S.%N')"
#     echo "FILE: $1"
#     echo "PWD: $(pwd)"
#     echo "PPID: $PPID"
#     echo "Parent process: $(ps -p $PPID -o comm= 2>/dev/null || echo 'unknown')"
#     echo "Parent command: $(ps -p $PPID -o args= 2>/dev/null || echo 'unknown')"
#     echo "Environment variables:"
#     echo "  STATUS_CALL=$STATUS_CALL"
#     echo "  RESET_CALL=$RESET_CALL"
#     echo "  RESET_MOD=$RESET_MOD"
#     echo "  STASH_CALL=$STASH_CALL"
#     echo "  FILE_CHECKOUT=$FILE_CHECKOUT"
#     echo "Active git directories:"
#     echo "  CHECKOUT_HEAD=$([ -f "$(git rev-parse --git-path CHECKOUT_HEAD)" ] && echo 1)"
#     if [ -f "$1" ]; then
#         echo "File size: $(stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo "N/A")"
#         echo "File empty: $([ -s "$1" ] && echo "NO" || echo "YES")"
#     fi
#     echo "Call stack:"
#     pstree -p $PPID 2>/dev/null || echo "pstree not available"
# } >> /tmp/fcstd_filter_debug.log 2>&1
# === END TEMPORARY DEBUG LOGGING ===

# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Git clean filter for .FCStd files. Makes .FCStd files appear empty to Git by outputting empty content to stdout.
# Checks if the user has a valid lock if locking is required, and exports the .FCStd file contents to the uncompressed directory.
# Handles special cases like git status calls, reset mod calls, stash calls, and file checkout calls to avoid unnecessary exports.

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
echo "DEBUG: All args: '$@'" >&2

# $STATUS_CALL is an environment variable set by the alias `git stat`
    # Note: when running `git status` sometimes this clean filter will be called. Read more here: https://stackoverflow.com/questions/41934945/why-does-git-status-run-filters
    # If the user uses the alias `git stat` the the STATUS_CALL env variable will be set during the git status call.
    # If the environment variable is detected then exit early without exporting FCStd files
if [ -n "$STATUS_CALL" ]; then
    echo "DEBUG: git status call, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS

# $DIFF_INDEX is an environment variable manually set for `git diff-index` calls
elif [ -n "$DIFF_INDEX" ]; then
    echo "DEBUG: git diff-index call, outputting original file contents.... EXIT SUCCESS (Clean Filter)" >&2
    cat
    exit $SUCCESS

# $RESET_CALL is an environment variable set by the alias `git freset`
elif [ -n "$RESET_CALL" ]; then
    echo "DEBUG: git reset call from freset alias, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS

# $RESET_MOD is an environment variable set by the alias `git fcmod`
elif [ -n "$RESET_MOD" ]; then
    echo "DEBUG: Reset modification call from fcmod alias, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS

# $STASH_CALL is an environment variable set by the alias `git fstash`
elif [ -n "$STASH_CALL" ]; then
    echo "DEBUG: git stash call, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS

# $FILE_CHECKOUT is an environment variable set by the alias `git fco`
elif [ -n "$FILE_CHECKOUT" ]; then
    echo "DEBUG: file checkout -- file call from fco alias, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
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

# $EXPORT_ENABLED is an environment variable set by the alias `git fadd`
if [ -z "$EXPORT_ENABLED" ]; then
    echo "ERR: Export flag not set, use \`git fadd\` instead of \`git add\` to set the flag." >&2
    exit $FAIL
fi

# ==============================================================================================
#                         Check if user allowed to modify .FCStd file
# ==============================================================================================
if [[ "$BYPASS_LOCK" == "1" ]]; then
    echo "DEBUG: BYPASS_LOCK=1, bypassing lock check." >&2
    :
else
    FCSTD_FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$1") || exit $FAIL

    echo "DEBUG: FCSTD_FILE_HAS_VALID_LOCK='$FCSTD_FILE_HAS_VALID_LOCK'" >&2

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
echo "DEBUG: START@'$(date +"%Y-%m-%dT%H:%M:%S.%6N")'" >&2
echo -n "EXPORTING: '$1'...." >&2
if "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --export "$1" > /dev/null; then
    echo "SUCCESS" >&2
    echo "DEBUG: END@'$(date +"%Y-%m-%dT%H:%M:%S.%6N")'" >&2

    FCStd_dir_path=$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$("$PYTHON_EXEC" "$FCStdFileTool" --CONFIG-FILE --dir "$1")") || {
        echo "Error: Failed to get dir path for '$FCStd_file_path'" >&2
        exit $FAIL
    }
    changefile_path="$FCStd_dir_path/.changefile"

    echo "DEBUG: $(grep 'File Last Exported On:' "$changefile_path")" >&2

    cat /dev/null
    exit $SUCCESS
    
else
    echo "FAIL, Rolling back git operation" >&2
    exit $FAIL
fi