#!/bin/bash
echo "DEBUG: FCStdReset.sh triggered!" >&2
# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Ensure working dir is the root of the repo
# GIT_ROOT=$(git rev-parse --show-toplevel)
# cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
    echo "Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                                      Execute Git Reset
# ==============================================================================================
# Get original HEAD before reset
ORIGINAL_HEAD=$(git rev-parse HEAD) || {
    echo "Error: Failed to get original HEAD" >&2
    exit $FAIL
}

# Execute git reset with all arguments
git reset "$@"
RESET_RESULT=$?

if [ $RESET_RESULT -ne 0 ]; then
    echo "git reset failed" >&2
    exit $RESET_RESULT
fi

# Get new HEAD after reset
NEW_HEAD=$(git rev-parse HEAD) || {
    echo "Error: Failed to get new HEAD" >&2
    exit $FAIL
}

# ==============================================================================================
#                                        Pull LFS files
# ==============================================================================================
git lfs pull
echo "DEBUG: Pulled lfs files" >&2

# ==============================================================================================
#                           Update .FCStd files with uncompressed files
# ==============================================================================================
if [ "$REQUIRE_LOCKS" == "$TRUE" ]; then
    CURRENT_USER=$(git config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        exit $FAIL
    }

    CURRENT_LOCKS=$(git lfs locks | awk '$2 == "'$CURRENT_USER'" {print $1}') || {
        echo "Error: failed to list of active lock info." >&2
        exit $FAIL
    }
fi

echo "DEBUG: diffing <original head>='$ORIGINAL_HEAD'..'$NEW_HEAD'=<new head>" >&2
changed_files=$(git diff-tree --no-commit-id --name-only -r "$ORIGINAL_HEAD" "$NEW_HEAD")

# Get changed .lockfiles
changed_lockfiles=$(echo "$changed_files" | grep -i '\.lockfile$')

echo -e "\nDEBUG: checking changed lockfiles: '$(echo $changed_lockfiles | xargs)'" >&2

# Get modified lockfiles after reset
after_reset_modified_lockfiles=$(git diff-index --name-only HEAD | grep -i '\.lockfile$' | sort)

# Sort changed lockfiles
changed_lockfiles_sorted=$(echo "$changed_lockfiles" | sort)

# Find lockfiles that were changed but are no longer modified after reset
lockfiles_changed_between_commits_currently_shows_no_modification=$(comm -23 <(echo "$changed_lockfiles_sorted") <(echo "$after_reset_modified_lockfiles"))

echo -e "\nDEBUG: Importing lockfiles that are no longer modified: '$(echo $lockfiles_changed_between_commits_currently_shows_no_modification | xargs)'" >&2

for lockfile in $lockfiles_changed_between_commits_currently_shows_no_modification; do
    echo -e "\nDEBUG: processing '$lockfile'...." >&2

    FCStd_file_path=$(get_FCStd_file_from_lockfile "$lockfile") || continue

    echo -n "IMPORTING: '$FCStd_file_path'...." >&2

    # Import data to FCStd file
    "$PYTHON_PATH" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
        echo "Error: Failed to import $FCStd_file_path, skipping..." >&2
        continue
    }

    echo "SUCCESS" >&2

    git clearFCStdMod "$FCStd_file_path"

    if [ "$REQUIRE_LOCKS" == "$TRUE" ]; then
        if echo "$CURRENT_LOCKS" | grep -q "$lockfile"; then
            # User has lock, set .FCStd file to writable
            make_writable "$FCStd_file_path"
            echo "DEBUG: set '$FCStd_file_path' writable." >&2
        else
            # User doesn't have lock, set .FCStd file to readonly
            make_readonly "$FCStd_file_path"
            echo "DEBUG: set '$FCStd_file_path' readonly." >&2
        fi
    fi
done

exit $SUCCESS