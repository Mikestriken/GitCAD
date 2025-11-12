#!/bin/bash
echo "DEBUG: Clean filter trap-card triggered!" >&2
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Git clean filter for .FCStd files. Makes .FCStd files appear empty to Git by outputting empty content to stdout.
# Checks if the user has a valid lock if locking is required, and exports the .FCStd file contents to the uncompressed directory.

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

# $RESET_MOD is an environment variable set by the alias `git fcmod`
if [ -n "$RESET_MOD" ]; then
    echo "DEBUG: Reset modification call from fcmod alias, showing empty file and skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS

# Note: When doing a file checkout the clean filter will parse the current file in the working dir (even if git shows no changes)
    # Solution: If file is empty don't export and exit early with success
elif [ ! -s "$1" ]; then
    echo "DEBUG: '$1' is empty, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS

# Check if this `.FCStd` file is already staged
# Note: This prevents issue #11 where previously, newly added (empty from git POV) `.FCStd` files still in the staging area get recleaned and exported a 2nd time.
# Diff Filter => (A)dded / (C)opied / (D)eleted / (M)odified / (R)enamed / (T)ype changed / (U)nmerged / (X) unknown / (B)roken pairing
elif git diff-index --cached --name-only --diff-filter=ACMRTUXB HEAD | grep -q "$1"; then
    echo "WARNING: \`$1\` already exported, skipping export..." >&2
    cat /dev/null
    exit $SUCCESS

# Check if this `.FCStd` shows as not modified, implying the modification has previously been exported
# Note: This prevents issue #11 where previously added (empty from git POV) `.FCStd` files get recleaned and exported a 2nd time.
# Diff Filter => (A)dded / (C)opied / (D)eleted / (M)odified / (R)enamed / (T)ype changed / (U)nmerged / (X) unknown / (B)roken pairing
elif ! git diff-index --name-only --diff-filter=ACMRTUXB HEAD | grep -q "$1"; then
    echo "WARNING: \`$1\` already exported, skipping export..." >&2
    cat /dev/null
    exit $SUCCESS

# $EXPORT_ENABLED is an environment variable set by the alias `git fadd`
elif [ -n "$EXPORT_ENABLED" ]; then
    :

# If none of the above, the clean filter should be disabled and simply show the file as empty.
else
    echo "WARNING: Export flag not set, use \`git fadd\` instead of \`git add\` to set the flag." >&2
    cat /dev/null
    exit $SUCCESS
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