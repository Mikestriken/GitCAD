#!/bin/bash
echo "DEBUG: FCStdReset.sh trap-card triggered!" >&2
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Wrapper script to handle Git reset operations for .FCStd files. Ensures .FCStd files remain synchronized with their uncompressed directories after reset.
# Observes files before and after reset, imports data into .FCStd files that were affected, and sets readonly/writable based on locks.

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
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
# Get modified .FCStd files before reset
BEFORE_RESET_MODIFIED_FCSTD=$(git diff-index --name-only HEAD | grep -i '\.fcstd$' | sort)

# Get modified `.changefile`s before reset
BEFORE_RESET_MODIFIED_CHANGEFILES=$(git diff-index --name-only HEAD | grep -i '\.changefile$' | sort)

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

echo "DEBUG: >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 1" >&2

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

echo "DEBUG: >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 2" >&2

# Append files changed between commits to BEFORE_RESET lists
files_changed_files_between_commits=$(git diff-tree --no-commit-id --name-only -r "$ORIGINAL_HEAD" "$NEW_HEAD")

echo "DEBUG: >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 3" >&2

FCStd_files_changed_between_commits=$(echo "$files_changed_files_between_commits" | grep -i '\.fcstd$')
changefiles_changed_between_commits=$(echo "$files_changed_files_between_commits" | grep -i '\.changefile$')

BEFORE_RESET_MODIFIED_FCSTD=$(echo -e "$BEFORE_RESET_MODIFIED_FCSTD\n$FCStd_files_changed_between_commits" | sort | uniq)
BEFORE_RESET_MODIFIED_CHANGEFILES=$(echo -e "$BEFORE_RESET_MODIFIED_CHANGEFILES\n$changefiles_changed_between_commits" | sort | uniq)

echo "DEBUG: >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 4" >&2

# Filter to list of valid files to process
AFTER_RESET_MODIFIED_FCSTD=$(git diff-index --name-only HEAD | grep -i '\.fcstd$' | sort)

echo "DEBUG: >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 5" >&2

previously_modified_FCStd_files_currently_shows_no_modification=$(comm -23 <(echo "$BEFORE_RESET_MODIFIED_FCSTD") <(echo "$AFTER_RESET_MODIFIED_FCSTD"))
echo "DEBUG: FULL FCStd files to import: '$(echo $previously_modified_FCStd_files_currently_shows_no_modification | xargs)'" >&2

AFTER_RESET_MODIFIED_CHANGEFILES=$(git diff-index --name-only HEAD | grep -i '\.changefile$' | sort)
previously_modified_changefiles_currently_shows_no_modification=$(comm -23 <(echo "$BEFORE_RESET_MODIFIED_CHANGEFILES") <(echo "$AFTER_RESET_MODIFIED_CHANGEFILES"))
echo "DEBUG: FULL .changefile files to import: '$(echo $previously_modified_changefiles_currently_shows_no_modification | xargs)'" >&2

# Deconflict: skip FCStd if corresponding changefile is being processed
FCStd_files_to_process=""
for FCStd_file_path in $previously_modified_FCStd_files_currently_shows_no_modification; do
    echo -n "DECONFLICTING: '$FCStd_file_path'...." >&2
    FCStd_dir_path=$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$("$PYTHON_EXEC" "$FCStdFileTool" --CONFIG-FILE --dir "$FCStd_file_path")") || continue
    if echo "$previously_modified_changefiles_currently_shows_no_modification" | grep -q "^$FCStd_dir_path/.changefile$"; then
        echo "REMOVED" >&2
        continue  # Skip, changefile will handle it
    fi
    echo "ADDED" >&2
    FCStd_files_to_process="$FCStd_files_to_process $FCStd_file_path"
done
changefiles_to_process="$previously_modified_changefiles_currently_shows_no_modification"

echo "DEBUG: MERGED FCStd files to import: '$(echo $FCStd_files_to_process | xargs)'" >&2
echo "DEBUG: MERGED .changefile files to import: '$(echo $changefiles_to_process | xargs)'" >&2

# Process FCStd files
for FCStd_file_path in $FCStd_files_to_process; do
    echo -e "\nDEBUG: processing FCStd '$FCStd_file_path'...." >&2

    # Get lockfile path
    FCStd_dir_path=$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$("$PYTHON_EXEC" "$FCStdFileTool" --CONFIG-FILE --dir "$FCStd_file_path")") || {
        echo "Error: Failed to get dir path for '$FCStd_file_path'" >&2
        continue
    }
    lockfile_path="$FCStd_dir_path/.lockfile"

    echo -n "IMPORTING: '$FCStd_file_path'...." >&2

    # Import data to FCStd file
    "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
        echo "Error: Failed to import $FCStd_file_path, skipping..." >&2
        continue
    }

    echo "SUCCESS" >&2

    git fcmod "$FCStd_file_path"

    if [ "$REQUIRE_LOCKS" == "$TRUE" ]; then
        if echo "$CURRENT_LOCKS" | grep -q "$lockfile_path"; then
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

# Process changefiles
for changefile in $changefiles_to_process; do
    echo -e "\nDEBUG: processing changefile '$changefile'...." >&2

    FCStd_file_path=$(get_FCStd_file_from_changefile "$changefile") || continue

    echo -n "IMPORTING: '$FCStd_file_path'...." >&2

    # Import data to FCStd file
    "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
        echo "Error: Failed to import $FCStd_file_path, skipping..." >&2
        continue
    }

    echo "SUCCESS" >&2

    git fcmod "$FCStd_file_path"

    FCStd_dir_path=$(dirname "$changefile")
    lockfile="$FCStd_dir_path/.lockfile"

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