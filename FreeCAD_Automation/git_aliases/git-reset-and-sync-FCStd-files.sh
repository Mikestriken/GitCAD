#!/bin/bash
# echo "DEBUG: ============== git-reset-and-sync-FCStd-files.sh trap-card triggered! ==============" >&2
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Wrapper script to handle Git reset operations for .FCStd files. Ensures .FCStd files remain synchronized with their uncompressed directories after reset.
# Observes files before and after reset, imports data into .FCStd files that were affected, and sets readonly/writable based on locks.

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Note: PWD for all scripts called via git aliases is the root of the git repository

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

# Note: Controlled by "FreeCAD_Automation/activate.sh" and "FreeCAD_Automation/git"
if [ "$GITCAD_ACTIVATED" = "$TRUE" ]; then
    git_path="$REAL_GIT"
else
    git_path="git"
fi

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                                      Execute Git Reset
# ==============================================================================================
# Get modified .FCStd files before reset
GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1
BEFORE_RESET_MODIFIED_FCSTD="$(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.fcstd$' | sort)"

# Get modified `.changefile`s before reset
GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1
BEFORE_RESET_MODIFIED_CHANGEFILES="$(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.changefile$' | sort)"

# Get original HEAD before reset
ORIGINAL_HEAD="$(GIT_COMMAND="rev-parse" "$git_path" rev-parse HEAD)" || {
    echo "Error: Failed to get original HEAD" >&2
    exit $FAIL
}

# Execute git reset with all arguments
    # Note: Sometimes calls clean filter on linux os.
GIT_COMMAND="reset" "$git_path" reset "$@"
RESET_RESULT=$?

if [ $RESET_RESULT -ne 0 ]; then
    echo "git reset failed" >&2
    exit $RESET_RESULT
fi

# Get new HEAD after reset
NEW_HEAD="$(GIT_COMMAND="rev-parse" "$git_path" rev-parse HEAD)" || {
    echo "Error: Failed to get new HEAD" >&2
    exit $FAIL
}

# ==============================================================================================
#                           Update .FCStd files with uncompressed files
# ==============================================================================================
if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
    CURRENT_USER="$(GIT_COMMAND="config" "$git_path" config --get user.name)" || {
        echo "Error: git config user.name not set!" >&2
        exit $FAIL
    }

    mapfile -t CURRENT_LOCKS < <(
        GIT_COMMAND="lfs" "$git_path" lfs locks |
        awk -v user="$CURRENT_USER" '
            match($0, /^(.*)[[:space:]]+([^[:space:]]+)[[:space:]]+ID:[0-9]+$/, m) &&
            m[2] == user {
                gsub(/[[:space:]]+$/, "", m[1])
                print m[1]
            }
        '
    ) || {
        echo "Error: failed to list of active lock info." >&2
        exit $FAIL
    }
fi

# Append files changed between commits to BEFORE_RESET lists
files_changed_files_between_commits="$(GIT_COMMAND="diff-tree" "$git_path" diff-tree --no-commit-id --name-only -r "$ORIGINAL_HEAD" "$NEW_HEAD")"

FCStd_files_changed_between_commits="$(printf '%s\n' "$files_changed_files_between_commits" | grep -i -- '\.fcstd$')"
changefiles_changed_between_commits="$(printf '%s\n' "$files_changed_files_between_commits" | grep -i -- '\.changefile$')"

BEFORE_RESET_MODIFIED_FCSTD="$(echo -e "$BEFORE_RESET_MODIFIED_FCSTD\n$FCStd_files_changed_between_commits" | sort | uniq)"
BEFORE_RESET_MODIFIED_CHANGEFILES="$(echo -e "$BEFORE_RESET_MODIFIED_CHANGEFILES\n$changefiles_changed_between_commits" | sort | uniq)"

# Filter to list of valid files to process
GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1
AFTER_RESET_MODIFIED_FCSTD="$(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.fcstd$' | sort)"

previously_modified_FCStd_files_currently_shows_no_modification="$(comm -23 <(echo "$BEFORE_RESET_MODIFIED_FCSTD") <(echo "$AFTER_RESET_MODIFIED_FCSTD"))"
# echo "DEBUG: FULL FCStd files to import: '$(echo "$previously_modified_FCStd_files_currently_shows_no_modification" | xargs)'" >&2

GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1
AFTER_RESET_MODIFIED_CHANGEFILES="$(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.changefile$' | sort)"
previously_modified_changefiles_currently_shows_no_modification="$(comm -23 <(echo "$BEFORE_RESET_MODIFIED_CHANGEFILES") <(echo "$AFTER_RESET_MODIFIED_CHANGEFILES"))"
# echo "DEBUG: FULL .changefile files to import: '$(echo "$previously_modified_changefiles_currently_shows_no_modification" | xargs)'" >&2

# Deconflict: skip FCStd if corresponding changefile is being processed
FCStd_files_to_process=()
mapfile -t previously_modified_FCStd_files_currently_shows_no_modification <<<"$previously_modified_FCStd_files_currently_shows_no_modification"
for FCStd_file_path in "${previously_modified_FCStd_files_currently_shows_no_modification[@]}"; do
    [ -z "$FCStd_file_path" ] && continue
    
    echo -n "DECONFLICTING: '$FCStd_file_path'...." >&2
    FCStd_dir_path="$(realpath --canonicalize-missing --relative-to="$(GIT_COMMAND="rev-parse" "$git_path" rev-parse --show-toplevel)" "$("$PYTHON_EXEC" "$FCStdFileTool" --CONFIG-FILE --dir "$FCStd_file_path")")" || continue
    
    if printf '%s\n' "$previously_modified_changefiles_currently_shows_no_modification" | grep -Fxq -- "$FCStd_dir_path/.changefile"; then
        echo "REMOVED" >&2
        continue  # Skip, changefile will handle it
    fi
    
    echo "ADDED" >&2
    FCStd_files_to_process+=("$FCStd_file_path")
done
changefiles_to_process=("${previously_modified_changefiles_currently_shows_no_modification[@]}")

# echo "DEBUG: MERGED FCStd files to import: '$(echo "${FCStd_files_to_process[@]}")'" >&2
# echo "DEBUG: MERGED .changefile files to import: '$(echo "${changefiles_to_process[@]}")'" >&2

# Process FCStd files
for FCStd_file_path in "${FCStd_files_to_process[@]}"; do
    [ -z "$FCStd_file_path" ] && continue
    # echo -e "\nDEBUG: processing FCStd '$FCStd_file_path'...." >&2

    # Get lockfile path
    FCStd_dir_path="$(realpath --canonicalize-missing --relative-to="$(GIT_COMMAND="rev-parse" "$git_path" rev-parse --show-toplevel)" "$("$PYTHON_EXEC" "$FCStdFileTool" --CONFIG-FILE --dir "$FCStd_file_path")")" || {
        echo "Error: Failed to get dir path for '$FCStd_file_path'" >&2
        continue
    }
    lockfile_path="$FCStd_dir_path/.lockfile"

    echo -n "IMPORTING: '$FCStd_file_path'...." >&2

    # Import data to FCStd file
    "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
        echo >&2
        echo "ERROR: Failed to import '$FCStd_file_path', skipping..." >&2
        continue
    }

    echo "SUCCESS" >&2

    GIT_COMMAND="fcmod" "$git_path" fcmod "$FCStd_file_path"

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        if printf '%s\n' "${CURRENT_LOCKS[@]}" | grep -Fxq -- "$lockfile_path"; then
            # User has lock, set .FCStd file to writable
            make_writable "$FCStd_file_path"
            # echo "DEBUG: set '$FCStd_file_path' writable." >&2
        else
            # User doesn't have lock, set .FCStd file to readonly
            make_readonly "$FCStd_file_path"
            # echo "DEBUG: set '$FCStd_file_path' readonly." >&2
        fi
    fi
done

# Process changefiles
for changefile in "${changefiles_to_process[@]}"; do
    # Skip empty entries
    [ -z "$changefile" ] && continue
    # echo -e "\nDEBUG: processing changefile '$changefile'....$(grep 'File Last Exported On:' "$changefile")" >&2

    FCStd_file_path="$(get_FCStd_file_from_changefile "$changefile")" || continue

    echo -n "IMPORTING: '$FCStd_file_path'...." >&2

    # Import data to FCStd file
    "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
        echo >&2
        echo "ERROR: Failed to import '$FCStd_file_path', skipping..." >&2
        continue
    }

    echo "SUCCESS" >&2

    GIT_COMMAND="fcmod" "$git_path" fcmod "$FCStd_file_path"

    FCStd_dir_path="$(dirname "$changefile")"
    lockfile="$FCStd_dir_path/.lockfile"

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        if printf '%s\n' "${CURRENT_LOCKS[@]}" | grep -Fxq -- "$lockfile"; then
            # User has lock, set .FCStd file to writable
            make_writable "$FCStd_file_path"
            # echo "DEBUG: set '$FCStd_file_path' writable." >&2
        else
            # User doesn't have lock, set .FCStd file to readonly
            make_readonly "$FCStd_file_path"
            # echo "DEBUG: set '$FCStd_file_path' readonly." >&2
        fi
    fi
done

exit $SUCCESS