#!/bin/bash
echo "DEBUG: git-stash-and-sync-FCStd-files trap-card triggered!" >&2
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Wrapper script to handle Git stash operations for .FCStd files. Ensures .FCStd files remain synchronized with their uncompressed directories.
# For stash pop/apply, checks that the user owns locks for associated `.lockfile`s. Imports .FCStd files after pop/apply.
# For stashing, re-imports .FCStd files after stashing to keep them synchronized to with the working directory.

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Note: PWD for all scripts called via git aliases is the root of the git repository

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

# Note: Controlled by "FreeCAD_Automation/activate.sh" and "FreeCAD_Automation/git"
if [ -n "$GITCAD_ACTIVATED" ]; then
    git_path="$REAL_GIT"
else
    git_path="git"
fi

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
    CURRENT_USER=$("$git_path" config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        exit $FAIL
    }

    CURRENT_LOCKS=$("$git_path" lfs locks | awk '$2 == "'$CURRENT_USER'" {print $1}') || {
        echo "Error: failed to list of active lock info." >&2
        exit $FAIL
    }
fi

# ==============================================================================================
#                                          Parse Args
# ==============================================================================================
# CALLER_SUBDIR=${GIT_PREFIX}:
    # If caller's pwd is $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller's pwd is $GIT_ROOT, $(GIT_PREFIX) = ""
CALLER_SUBDIR=$1
shift

stash_args=("$@")

# Note: Stash Types: list, show, drop, pop, apply, branch, push, save, clear, create, store, export, import

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_file_path_args=()
stash_command_args=()
POP_OR_APPLY_FLAG=$FALSE
STASH_COMMAND=""
STASH_INDEX=""
FILE_SEPARATOR_FLAG=$FALSE
while [ $# -gt 0 ]; do
    echo "DEBUG: parsing '$1'..." >&2
    case $1 in
        # Set boolean flag if arg is a valid flag
        pop|apply)
            POP_OR_APPLY_FLAG=$TRUE
            STASH_COMMAND="$1"
            stash_command_args+=("$1")
            
            if [ "$2" != "--" ]; then
                shift
                STASH_INDEX="$1"
                stash_command_args+=("$1")
            fi
            echo "DEBUG: POP_OR_APPLY_FLAG set for '$STASH_COMMAND' at index '$STASH_INDEX'" >&2
            ;;
        
        "--")
            FILE_SEPARATOR_FLAG=$TRUE
            echo "DEBUG: FILE_SEPARATOR_FLAG set" >&2
            ;;
        
        "-*")
            echo "DEBUG: '$1' flag is not recognized, skipping..." >&2
            if [ "$FILE_SEPARATOR_FLAG" = "$FALSE" ]; then
                stash_command_args+=("$1")
            fi
            ;;
        
        # Assume arg is path. Fix path to be relative to root of the git repo instead of user's terminal pwd.
        *)
            if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                if [ -n "$CALLER_SUBDIR" ]; then
                    case $1 in
                        ".")
                            echo "DEBUG: '$1' -> '$CALLER_SUBDIR'" >&2
                            parsed_file_path_args+=("$CALLER_SUBDIR")
                            ;;
                        *)
                            echo "DEBUG: prepend '$1'" >&2
                            parsed_file_path_args+=("${CALLER_SUBDIR}${1}")
                            ;;
                    esac
                else
                    echo "DEBUG: Don't prepend '$1'" >&2
                    parsed_file_path_args+=("$1")
                fi
            
            else
                stash_command_args+=("$1")
                echo "DEBUG: '$1' not recognized, skipping..." >&2
            fi
            ;;
    esac
    shift
done

# ==============================================================================================
#                                   Execute Stash n' Import
# ==============================================================================================
# Called stash command involves applying changes to working directory
if [ "$POP_OR_APPLY_FLAG" = "$TRUE" ]; then
    echo "DEBUG: Stash application detected" >&2

    # Check that user has locks for lockfile in same dir as stashed changefile
    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        if [ -n "$STASH_INDEX" ]; then
            STASH_REF="stash@{$STASH_INDEX}"
        else
            STASH_REF="stash@{0}"
        fi
        
        STASHED_CHANGEFILES=$(GIT_COMMAND="stash" "$git_path" stash show --name-only "$STASH_REF" 2>/dev/null | grep -i '\.changefile$' || true)

        # echo -e "\nDEBUG: checking stashed changefiles: '$(echo $STASHED_CHANGEFILES | xargs)'" >&2

        for changefile in $STASHED_CHANGEFILES; do
            # echo -e "\nDEBUG: checking '$changefile'....$(grep 'File Last Exported On:' "$changefile")" >&2
            FCStd_dir_path=$(dirname $changefile)
            lockfile="$FCStd_dir_path/.lockfile"

            if ! echo "$CURRENT_LOCKS" | grep -q "$lockfile"; then
                echo "Error: User does not have lock for $lockfile in stash" >&2
                exit $FAIL
            fi
        done
    fi

    # Execute git stash pop/apply
        # Note: `git stash` sometimes calls clean filter... other times not... really weird....
    if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
        GIT_COMMAND="stash" "$git_path" stash "${stash_command_args[@]}" -- "${parsed_file_path_args[@]}"
    else
        GIT_COMMAND="stash" "$git_path" stash "${stash_args[@]}"
    fi
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne 0 ]; then
        echo "git stash $STASH_COMMAND failed" >&2
        exit $STASH_RESULT
    fi

    # Check for changed lockfiles in the working dir (similar to post-checkout)
    "$git_path" update-index --refresh -q >/dev/null 2>&1
    for changefile in $("$git_path" diff-index --name-only HEAD | grep -i '\.changefile$'); do
        # echo -e "\nDEBUG: checking '$changefile'....$(grep 'File Last Exported On:' "$changefile")" >&2
        FCStd_file_path=$(get_FCStd_file_from_changefile "$changefile") || continue

        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo "Failed to import $FCStd_file_path" >&2
        }
        echo "SUCCESS" >&2
    done

# Called stash command involves stashing away changes to working directory or calling some other command
else
    echo "DEBUG: Stashing away or something else..." >&2
    
    # # Check for uncommitted .FCStd files
    # #     Note: The reason I'm not allowing the user to stash away .FCStd without exporting them first is because unlock.sh needs to check for .changefiles in stash to prevent stash
    # "$git_path" update-index --refresh -q >/dev/null 2>&1
    # UNCOMMITTED_FCSTD_FILES=$("$git_path" diff-index --name-only HEAD | grep -i '\.fcstd$' || true)
    # if [ -n "$UNCOMMITTED_FCSTD_FILES" ]; then
    #     if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
    #         FCStd_files_in_args=$(printf '%s\n' "${parsed_file_path_args[@]}" | grep -i '\.fcstd$' || true)
    #         if [ -n "$FCStd_files_in_args" ]; then
    #             echo "Error: Cannot stash .FCStd files, export them first with \`git fadd\` or \`git add\` with GitCAD activated." >&2
    #             exit $FAIL
    #         fi
    #     else
    #         echo "Error: Cannot stash .FCStd files, export them first with \`git fadd\` or \`git add\` with GitCAD activated." >&2
    #         exit $FAIL
    #     fi
    # fi
    
    # Get modified changefiles before stash
    "$git_path" update-index --refresh -q >/dev/null 2>&1
    BEFORE_STASH_CHANGEFILES=$("$git_path" diff-index --name-only HEAD | grep -i '\.changefile$' | sort)
    
    echo "DEBUG: retrieved before stash changefiles..." >&2

    # Execute git stash
        # Note: `git stash` sometimes calls clean filter... other times not... really weird....
    echo "DEBUG: '$git_path stash ${stash_args[@]}'" >&2
    if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
        GIT_COMMAND="stash" "$git_path" stash "${stash_command_args[@]}" -- "${parsed_file_path_args[@]}"
    else
        GIT_COMMAND="stash" "$git_path" stash "${stash_args[@]}"
    fi
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne 0 ]; then
        echo "git stash failed" >&2
        exit $STASH_RESULT
    fi

    # Get modified lockfiles after stash
    "$git_path" update-index --refresh -q >/dev/null 2>&1
    AFTER_STASH_CHANGEFILE=$("$git_path" diff-index --name-only HEAD | grep -i '\.changefile$' | sort)

    # Find files present before stash but not after stash (files that were stashed)
    STASHED_CHANGEFILES=$(comm -23 <(echo "$BEFORE_STASH_CHANGEFILES") <(echo "$AFTER_STASH_CHANGEFILE"))

    echo -e "\nDEBUG: Importing stashed changefiles: '$(echo $STASHED_CHANGEFILES | xargs)'" >&2

    # Import the files that are no longer modified (those that were stashed)
    for changefile in $STASHED_CHANGEFILES; do
        echo -e "\nDEBUG: checking '$changefile'....$(grep 'File Last Exported On:' "$changefile")" >&2
        FCStd_file_path=$(get_FCStd_file_from_changefile "$changefile") || continue
        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo "Failed to import $FCStd_file_path" >&2
        }
        echo "SUCCESS" >&2
        
        "$git_path" fcmod "$FCStd_file_path"
    done
fi

exit $SUCCESS