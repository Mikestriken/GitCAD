#!/bin/bash
echo "DEBUG: FCStdReset.sh trap-card triggered!" >&2
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
BEFORE_RESET_FCSTD=$(git diff-index --name-only HEAD | grep -i '\.fcstd$' | sort)

# Get modified .lockfiles before reset
BEFORE_RESET_LOCKFILES=$(git diff-index --name-only HEAD | grep -i '\.lockfile$' | sort)

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

# Determine files to process based on whether HEAD changed
if [ "$ORIGINAL_HEAD" = "$NEW_HEAD" ]; then
    echo "DEBUG: Reset HEAD detected" >&2
    # HEAD didn't change, use before and after lists
    AFTER_RESET_FCSTD=$(git diff-index --name-only HEAD | grep -i '\.fcstd$' | sort)
    previously_modified_FCStd_files_currently_shows_no_modification=$(comm -23 <(echo "$BEFORE_RESET_FCSTD") <(echo "$AFTER_RESET_FCSTD"))
    echo "DEBUG: FULL FCStd files to import: '$(echo $previously_modified_FCStd_files_currently_shows_no_modification | xargs)'" >&2

    AFTER_RESET_LOCKFILES=$(git diff-index --name-only HEAD | grep -i '\.lockfile$' | sort)
    previously_modified_lockfiles_currently_shows_no_modification=$(comm -23 <(echo "$BEFORE_RESET_LOCKFILES") <(echo "$AFTER_RESET_LOCKFILES"))
    echo "DEBUG: FULL .lockfile files to import: '$(echo $previously_modified_lockfiles_currently_shows_no_modification | xargs)'" >&2

    # Deconflict: skip FCStd if corresponding lockfile is being processed
    FCStd_files_to_process=""
    for FCStd_file_path in $previously_modified_FCStd_files_currently_shows_no_modification; do
        echo -n "DECONFLICTING: '$FCStd_file_path'...." >&2
        lockfile_path=$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$("$PYTHON_PATH" "$FCStdFileTool" --CONFIG-FILE --lockfile "$FCStd_file_path")") || continue
        if echo "$previously_modified_lockfiles_currently_shows_no_modification" | grep -q "^$lockfile_path$"; then
            echo "REMOVED" >&2
            continue  # Skip, lockfile will handle it
        fi
        echo "ADDED" >&2
        FCStd_files_to_process="$FCStd_files_to_process $fcstd"
    done


    lockfiles_to_process="$previously_modified_lockfiles_currently_shows_no_modification"
else
    echo "DEBUG: New commit reset detected" >&2
    # HEAD did change, use git diff-tree
    changed_files=$(git diff-tree --no-commit-id --name-only -r "$ORIGINAL_HEAD" "$NEW_HEAD")

    changed_fcstd=$(echo "$changed_files" | grep -i '\.fcstd$')
    changed_lockfiles=$(echo "$changed_files" | grep -i '\.lockfile$')

    after_reset_modified_lockfiles=$(git diff-index --name-only HEAD | grep -i '\.lockfile$' | sort)
    changed_lockfiles_sorted=$(echo "$changed_lockfiles" | sort)
    lockfiles_changed_between_commits_currently_shows_no_modification=$(comm -23 <(echo "$changed_lockfiles_sorted") <(echo "$after_reset_modified_lockfiles"))
    echo "DEBUG: .lockfile files to import: '$(echo $lockfiles_changed_between_commits_currently_shows_no_modification | xargs)'" >&2

    after_reset_fcstd=$(git diff-index --name-only HEAD | grep -i '\.fcstd$' | sort)
    changed_fcstd_sorted=$(echo "$changed_fcstd" | sort)
    fcstd_changed_between_commits_currently_shows_no_modification=$(comm -23 <(echo "$changed_fcstd_sorted") <(echo "$after_reset_fcstd"))
    echo "DEBUG: FCStd files to import: '$(echo $fcstd_changed_between_commits_currently_shows_no_modification | xargs)'" >&2

    # Deconflict: skip FCStd if corresponding lockfile is being processed
    FCStd_files_to_process=""
    for FCStd_file_path in $fcstd_changed_between_commits_currently_shows_no_modification; do
        echo -n "DECONFLICTING: '$FCStd_file_path'...." >&2
        lockfile_path=$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$("$PYTHON_PATH" "$FCStdFileTool" --CONFIG-FILE --lockfile "$FCStd_file_path")") || continue
        if echo "$lockfiles_changed_between_commits_currently_shows_no_modification" | grep -q "^$lockfile_path$"; then
            echo "REMOVED" >&2
            continue  # Skip, lockfile will handle it
        fi
        echo "ADDED" >&2
        FCStd_files_to_process="$FCStd_files_to_process $fcstd"
    done

    lockfiles_to_process="$lockfiles_changed_between_commits_currently_shows_no_modification"
fi
echo "DEBUG: MERGED FCStd files to import: '$(echo $FCStd_files_to_process | xargs)'" >&2
echo "DEBUG: MERGED .lockfile files to import: '$(echo $lockfiles_to_process | xargs)'" >&2

# Process FCStd files
for FCStd_file_path in $FCStd_files_to_process; do
    echo -e "\nDEBUG: processing FCStd '$FCStd_file_path'...." >&2

    # Get lockfile path
    lockfile_path=$("$PYTHON_PATH" "$FCStdFileTool" --CONFIG-FILE --lockfile "$FCStd_file_path") || {
        echo "Error: Failed to get lockfile path for '$FCStd_file_path'" >&2
        continue
    }

    echo -n "IMPORTING: '$FCStd_file_path'...." >&2

    # Import data to FCStd file
    "$PYTHON_PATH" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
        echo "Error: Failed to import $FCStd_file_path, skipping..." >&2
        continue
    }

    echo "SUCCESS" >&2

    git clearFCStdMod "$FCStd_file_path"

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

# Process lockfiles
for lockfile in $lockfiles_to_process; do
    echo -e "\nDEBUG: processing lockfile '$lockfile'...." >&2

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