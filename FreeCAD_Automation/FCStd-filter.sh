#!/bin/bash
# echo "DEBUG: Clean filter trap-card triggered!" >&2
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
# echo "DEBUG: All args: '$@'" >&2

# $RESET_MOD is an environment variable set by the alias `git fcmod`
if [ -n "$RESET_MOD" ]; then
    # echo "DEBUG: Reset modification call from fcmod alias, showing empty file and skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS

# Note: When doing a file checkout the clean filter will parse the current file in the working dir (even if git shows no changes)
    # Solution: If file is empty don't export and exit early with success
elif [ ! -s "$1" ]; then
    # echo "DEBUG: '$1' is empty, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS
fi

# Check if this `.FCStd` file has been modified since last export by comparing OS modification timestamps between it and the `.changefile`
    # If `.changefile` is newer, don't export.
    # If `.changefile` is older, then export.
    # If `.changefile` doesn't exist then export.
FCStd_dir_path=$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$("$PYTHON_EXEC" "$FCStdFileTool" --CONFIG-FILE --dir "$1")") || {
    echo "Error: Failed to get dir path for '$FCStd_file_path'" >&2
    exit $FAIL
}
changefile_path="$FCStd_dir_path/.changefile"

if [ -f "$changefile_path" ]; then
    FCStd_file_modification_time=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)
    changefile_modification_time=$(stat -c %Y "$changefile_path" 2>/dev/null || stat -f %m "$changefile_path" 2>/dev/null)
    
    if [ "$changefile_modification_time" -ge "$FCStd_file_modification_time" ]; then
        # echo "WARNING: \`$1\` already exported, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
        cat /dev/null
        exit $SUCCESS
    fi
fi

if [ -n "$GITCAD_ACTIVATED" ]; then
    # $GIT_COMMAND is an environment variable set by the GitCAD wrapper script (FreeCAD_Automation/git) when activated via `source FreeCAD_Automation/activate.sh`
    if [ "$GIT_COMMAND" = "add" ]; then
        :
    
    elif [ "$GIT_COMMAND" = "checkout" ]; then
        :
        cat /dev/null
        exit $SUCCESS
    fi

# If GitCAD is not activated the user must then use the git aliases.
else
    # $EXPORT_ENABLED is an environment variable set by the alias `git fadd`
    if [ -n "$EXPORT_ENABLED" ]; then
        :
    
    # If none of the above, the clean filter should be disabled and simply show the file as empty.
    else
        echo "WARNING: Export flag not set. Modification for '$1' cleared. Run \`git fexport\` to manually export the file if that was your intention. Use \`git fadd\` instead of \`git add\` next time to set the export flag (or activate GitCAD with \`source FreeCAD_Automation/activate.sh\` to use standard git commands)" >&2
        cat /dev/null
        exit $SUCCESS
    fi
fi


# ==============================================================================================
#                         Check if user allowed to modify .FCStd file
# ==============================================================================================
if [[ "$BYPASS_LOCK" == "$TRUE" ]]; then
    # echo "DEBUG: BYPASS_LOCK=0, bypassing lock check." >&2
    :
else
    FCSTD_FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$1") || exit $FAIL

    # echo "DEBUG: FCSTD_FILE_HAS_VALID_LOCK='$FCSTD_FILE_HAS_VALID_LOCK'" >&2

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
# echo "DEBUG: START@'$(date +"%Y-%m-%dT%H:%M:%S.%6N")'" >&2
echo -n "EXPORTING: '$1'...." >&2
if "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --export "$1" > /dev/null; then
    echo "SUCCESS" >&2
    # echo "DEBUG: END@'$(date +"%Y-%m-%dT%H:%M:%S.%6N")'" >&2

    # echo "DEBUG: $(grep 'File Last Exported On:' "$changefile_path")" >&2

    cat /dev/null
    exit $SUCCESS
    
else
    echo "FAIL, Rolling back git operation" >&2
    exit $FAIL
fi