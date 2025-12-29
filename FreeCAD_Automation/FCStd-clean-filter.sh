#!/bin/bash
echo "DEBUG: ============== Clean filter trap-card triggered! ==============" >&2
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
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                           Early Exits Before Exporting .FCStd file
# ==============================================================================================
# Note: cat /dev/null is printed to stdout, makes git think the .FCStd file is empty

# print all args to stderr
echo "DEBUG: All args: '$@'" >&2

# $RESET_MOD is an environment variable set by the alias `git fcmod`
if [ "$RESET_MOD" = "$TRUE" ]; then
    echo "DEBUG: Reset modification call from fcmod alias, showing empty .FCStd file and skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS

# $GIT_COMMAND is an environment variable set by the GitCAD wrapper script (FreeCAD_Automation/git) when activated via `source FreeCAD_Automation/activate.sh`
    # It is also set by the fstash script to "stash" when the GitCAD wrapper script is not active
    # It is also set by the fadd alias to "add" to specify the user's intention to export added .FCStd files
    # It is also set by the stat alias to "status" to specify the user's intention to see what files git thinks are modified and aren't (don't make .FCStd files appear unmodified if git thinks they're modified)
# Note: Calling `git stash` sometimes calls the clean filter, for stash operations we don't want to clear modifications or export .FCStd files for this case
elif [ "$GIT_COMMAND" = "stash" ]; then
    echo "DEBUG: stash call from fstash alias or git wrapper, showing modified .FCStd file and skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat
    exit $SUCCESS

elif [ "$GIT_COMMAND" = "status" ]; then
    echo "DEBUG: status call from stat alias or git wrapper, showing modified .FCStd file and skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat
    exit $SUCCESS

# Note: When doing a file checkout the clean filter will parse the current file in the working dir (even if git shows no changes)
    # Solution: If file is empty don't export and exit early with success
elif [ ! -s "$1" ]; then
    echo "DEBUG: '$1' is empty, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
    cat /dev/null
    exit $SUCCESS
fi

# Check if this `.FCStd` file has been modified since last export by comparing OS modification timestamps between it and the `.changefile`
    # If `.changefile` is newer, don't export.
    # If `.changefile` is older, then export.
    # If `.changefile` doesn't exist then export.
FCStd_dir_path=$(get_FCStd_dir "$1") || exit $FAIL
changefile_path="$FCStd_dir_path/.changefile"

if [ -f "$changefile_path" ]; then
    FCStd_file_modification_time=$(date -u -d @"$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" '+%Y-%m-%dT%H:%M:%S.%6N%:z')
    changefile_modification_time=$(date -u -d @"$(stat -c %Y "$changefile_path" 2>/dev/null || stat -f %m "$changefile_path" 2>/dev/null)" '+%Y-%m-%dT%H:%M:%S.%6N%:z')
    
    if [[ "$changefile_modification_time" > "$FCStd_file_modification_time" || "$changefile_modification_time" == "$FCStd_file_modification_time" ]]; then
        echo "DEBUG: \`$1\` already exported, skipping export.... EXIT SUCCESS (Clean Filter)" >&2
        cat /dev/null
        exit $SUCCESS
    fi
fi

# Note: Cannot move this conditional logic up as we needed to first check if the file had already been exported prior
# $GIT_COMMAND is an environment variable set by the GitCAD wrapper script (FreeCAD_Automation/git) when activated via `source FreeCAD_Automation/activate.sh`
    # It is also set by the fstash alias script to "stash" when the GitCAD wrapper script is not active
    # It is also set by the fadd alias to "add" to specify the user's intention to export added .FCStd files
if [ "$GIT_COMMAND" = "add" ]; then
    :

# If GitCAD is not activated then the clean filter cannot be sure of what git command triggered this filter unless the user use aliases.
    # As a default response to an unknown git command, the clean filter should be disabled and simply show the file as empty.
elif [ -z "$GITCAD_ACTIVATED" ]; then
    echo "============================================================ WARNING ============================================================" >&2
    echo "Export flag not set. Removed Modification (git POV only) for '$1'." >&2
    echo >&2
    echo "If you didn't run \`git add\` then ignore this warning." >&2
    echo "The following git commands are known to erroneously trigger this warning on Linux: checkout, freset, fstash, fco, unlock, pull" >&2
    echo >&2
    echo "If you DID run \`git add\` Run \`git fexport\` to manually export the file." >&2
    echo "Use \`git fadd\` instead of \`git add\` next time to set the export flag." >&2
    echo >&2
    echo "ALTERNATIVELY: Activate GitCAD with \`source FreeCAD_Automation/activate.sh\` to use standard git commands" >&2
    echo "=================================================================================================================================" >&2
    
    cat /dev/null
    exit $SUCCESS

# Note: The following git commands are known to also trigger this clean filter: checkout, reset, stash, unlock, pull
    # In the above scenarios (that aren't `git add`), we disable the clean filter and make the .FCStd file show up as having no modification (git POV)
else
    cat /dev/null
    exit $SUCCESS
fi

# ==============================================================================================
#                         Check if user allowed to modify .FCStd file
# ==============================================================================================
if [ "$BYPASS_LOCK" = "$TRUE" ]; then
    echo "DEBUG: BYPASS_LOCK=$TRUE, bypassing lock check." >&2
    :

else
    FCSTD_FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$1") || exit $FAIL

    echo "DEBUG: FCSTD_FILE_HAS_VALID_LOCK='$FCSTD_FILE_HAS_VALID_LOCK'" >&2

    if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
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

    echo "DEBUG: $(grep 'File Last Exported On:' "$changefile_path")" >&2

    cat /dev/null
    exit $SUCCESS
    
else
    echo "FAIL, Rolling back git operation" >&2
    exit $FAIL
fi