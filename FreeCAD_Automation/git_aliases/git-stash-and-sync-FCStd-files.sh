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

GIT_COMMAND_ALREADY_SET=$TRUE
if [ -z "$GIT_COMMAND" ]; then
    GIT_COMMAND_ALREADY_SET=$FALSE
    export GIT_COMMAND="stash"
fi

exit_fstash() {
    if [ "$GIT_COMMAND_ALREADY_SET" = "$FALSE" ]; then 
        unset GIT_COMMAND
    fi
    
    case $1 in
        "")
            echo "Error: No exit code provided, exiting with fail!" >&2
            exit $FAIL
            ;;
        *)
            exit $1
            ;;
    esac
}
trap "exit_fstash $FAIL 2>/dev/null" EXIT

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit_fstash $FAIL
fi

if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
    CURRENT_USER=$("$git_path" config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        exit_fstash $FAIL
    }

    CURRENT_LOCKS=$("$git_path" lfs locks | awk '$2 == "'$CURRENT_USER'" {print $1}') || {
        echo "Error: failed to list of active lock info." >&2
        exit_fstash $FAIL
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

# Note, Stash sub-commands as of git v2.52.0: list, show, drop, pop, apply, branch, push, -p (push -p), save, clear, create, store, export, import

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_file_path_args=()
stash_command_args=()
STASH_COMMAND_DOES_NOT_MODIFY_WORKING_DIR_OR_CREATE_STASHES=$FALSE
STASH_COMMAND=""
BRANCH_NAME=""
STASH_REF=""
FILE_SEPARATOR_FLAG=$FALSE
while [ $# -gt 0 ]; do
    echo "DEBUG: parsing '$1'..." >&2
    case $1 in
        # ===== Capture Explicit STASH_COMMANDs that apply stashed changes =====
        pop|apply)
            if [ -n "$STASH_COMMAND" ]; then
                echo "Error: Stash command already provided, yet command '$1' was specified afterwards" >&2
                exit_fstash $FAIL
            
            elif [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: stash command '$1' is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi

            STASH_COMMAND="$1"
            stash_command_args+=("$1")
            echo "DEBUG: POP_OR_APPLY_FLAG set for '$STASH_COMMAND'" >&2
            ;;

        "branch")
            if [ -n "$STASH_COMMAND" ]; then
                echo "Error: Stash command already provided, yet command '$1' was specified afterwards" >&2
                exit_fstash $FAIL
            
            elif [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: stash command '$1' is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi

            STASH_COMMAND="$1"
            stash_command_args+=("$1")
            
            shift
            BRANCH_NAME="$1"
            stash_command_args+=("$1")
            ;;

        # ===== Capture Explicit STASH_COMMANDs that stashes away changes =====
        push|save)
            if [ -n "$STASH_COMMAND" ]; then
                echo "Error: Stash command already provided, yet command '$1' was specified afterwards" >&2
                exit_fstash $FAIL
            
            elif [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: stash command '$1' is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi

            STASH_COMMAND="$1"
            stash_command_args+=("$1")
            ;;
        
        "-p")
            # Note: `git stash -p` is short for `git stash push -p` 
            if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: stash command '$1' is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi
            
            if [ -z "$STASH_COMMAND" ]; then
                STASH_COMMAND="push"
            fi

            stash_command_args+=("$1")
            ;;

        "create")
            # Note: For the purposes of this script, create behaves like `git stash push` and `git stash apply` in one command. (There is more to it than that)
            if [ -n "$STASH_COMMAND" ]; then
                echo "Error: Stash command already provided, yet command '$1' was specified afterwards" >&2
                exit_fstash $FAIL
            
            elif [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: stash command '$1' is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi
            
            STASH_COMMAND="$1"
            stash_command_args+=("$1")
            ;;
        
        # ===== Capture passthrough STASH_COMMANDs that DO NOT modify the working directory or create stashes =====
        list|show|drop|clear|store|import|export)
            if [ -n "$STASH_COMMAND" ]; then
                echo "Error: Stash command already provided, yet command '$1' was specified afterwards" >&2
                exit_fstash $FAIL
            
            elif [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: stash command '$1' is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi
            
            STASH_COMMAND_DOES_NOT_MODIFY_WORKING_DIR_OR_CREATE_STASHES=$TRUE
            break
            ;;
        
        # ===== Capture STASH_REF =====
        stash@\{[0-9]*\})
            if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: '$1' assumed to be stash index is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi

            STASH_REF="$1"
            stash_command_args+=("$1")
            ;;
        
        [0-9]*)
            if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: '$1' assumed to be stash index is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi

            # Ensure arg is only numbers
            if [[ $1 =~ ^[0-9]+$ ]]; then
                STASH_REF="stash@{$1}"
                stash_command_args+=("$1")
            else
                echo "Error: '$1' assumed to be stash index contains non-numeric characters." >&2
                exit_fstash $FAIL
            fi
            ;;
        
        # ===== Capture FILE_SEPARATOR =====
        # Note: As of git v2.52.0, the FILE_SEPARATOR is only valid for the "push" STASH_COMMAND
        "--")
            FILE_SEPARATOR_FLAG=$TRUE
            echo "DEBUG: FILE_SEPARATOR_FLAG set" >&2
            ;;
        
        # ===== Capture `git stash` Flags =====
        -*)
            if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: '$1' flag is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi

            echo "DEBUG: '$1' flag is not recognized, skipping..." >&2
            stash_command_args+=("$1")
            ;;
        
        # ===== Capture files paths and other flags =====
        *)
            # If command not specified, assume command is `git stash push`
            if [ -z "$STASH_COMMAND" ] && [ "$FILE_SEPARATOR_FLAG" = "$FALSE" ]; then
                # ! WARNING: This WILL cause a bug if git adds a new git stash command not accounted for and that command is called.
                    # Simple fix for this would be to add that command to the `list|show|drop|clear|store|import|export)` case
                STASH_COMMAND="push"

            elif [ -z "$STASH_COMMAND" ] && [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: Something is wrong with these args: '${stash_args[@]}'" >&2
                exit_fstash $FAIL
            
            elif [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
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
# ToDo: When checking for valid lock, check .FCStd files as well for stash application and creation (instead of just .changefiles)
    # ToDo: Use git ls-files to handle wildcards when matching
# ToDo: when stashing away, user cannot be allowed to store changes to both the .FCStd file and its associated .changefile at same time (stash application logic will overwrite said .FCStd file with .changefile changes)
# ToDo TEST: git unlocking with a stashed .FCStd file change
# ToDo TEST: git checkout stash@{0} -- path/to/file
if [ "$STASH_COMMAND_DOES_NOT_MODIFY_WORKING_DIR_OR_CREATE_STASHES" = "$TRUE" ]; then
    echo "DEBUG: stash command does not modify working directory or create stashes. Passing command directly to git stash." >&2
    echo "DEBUG: '$git_path stash ${stash_args[@]}'" >&2
    "$git_path" stash "${stash_args[@]}"

# ===== Called stash command involves applying stash to working directory =====
elif [ "$STASH_COMMAND" = "pop" ] || [ "$STASH_COMMAND" = "apply" ] || [ "$STASH_COMMAND" = "branch" ]; then
    echo "DEBUG: Stash pop/apply/branch detected" >&2

    # Check that user has locks for lockfile in same dir as stashed changefile
    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        if [ -z "$STASH_REF" ]; then
            STASH_REF="stash@{0}"
        fi
        
        STASHED_CHANGEFILES=$("$git_path" stash show --name-only "$STASH_REF" 2>/dev/null | grep -i '\.changefile$' || true)

        # echo -e "\nDEBUG: checking stashed changefiles: '$(echo $STASHED_CHANGEFILES | xargs)'" >&2

        for changefile in $STASHED_CHANGEFILES; do
            # echo -e "\nDEBUG: checking '$changefile'....$(grep 'File Last Exported On:' "$changefile")" >&2
            FCStd_dir_path=$(dirname $changefile)
            lockfile="$FCStd_dir_path/.lockfile"

            if ! echo "$CURRENT_LOCKS" | grep -q "$lockfile"; then
                echo "Error: User does not have lock for $lockfile in stash" >&2
                exit_fstash $FAIL
            fi
        done
    fi

    # Execute git stash pop/apply/branch
        # Note: `git stash` sometimes calls clean filter...
        # Note: As of git v2.52.0, the FILE_SEPARATOR is only valid for the "push" STASH_COMMAND
    if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
        "$git_path" stash "${stash_command_args[@]}" -- "${parsed_file_path_args[@]}"
    else
        "$git_path" stash "${stash_args[@]}"
    fi
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne 0 ]; then
        echo "git stash $STASH_COMMAND failed" >&2
        exit_fstash $STASH_RESULT
    fi

    # Synchronize .FCStd files with popped changes
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

# ===== Called stash command involves stashing away working directory changes (creating stashes) =====
elif [ "$STASH_COMMAND" = "push" ] || [ "$STASH_COMMAND" = "save" ] || [ "$STASH_COMMAND" = "create" ]; then
    echo "DEBUG: Stash push/save/create detected" >&2
    
    # # Check for uncommitted .FCStd files
    # #     Note: The reason I'm not allowing the user to stash away .FCStd without exporting them first is because unlock.sh needs to check for .changefiles in stash to prevent stash
    # "$git_path" update-index --refresh -q >/dev/null 2>&1
    # UNCOMMITTED_FCSTD_FILES=$("$git_path" diff-index --name-only HEAD | grep -i '\.fcstd$' || true)
    # if [ -n "$UNCOMMITTED_FCSTD_FILES" ]; then
    #     if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
    #         FCStd_files_in_args=$(printf '%s\n' "${parsed_file_path_args[@]}" | grep -i '\.fcstd$' || true)
    #         if [ -n "$FCStd_files_in_args" ]; then
    #             echo "Error: Cannot stash .FCStd files, export them first with \`git fadd\` or \`git add\` with GitCAD activated." >&2
    #             exit_fstash $FAIL
    #         fi
    #     else
    #         echo "Error: Cannot stash .FCStd files, export them first with \`git fadd\` or \`git add\` with GitCAD activated." >&2
    #         exit_fstash $FAIL
    #     fi
    # fi
    
    # Get modified changefiles before stash
    "$git_path" update-index --refresh -q >/dev/null 2>&1
    BEFORE_STASH_CHANGEFILES=$("$git_path" diff-index --name-only HEAD | grep -i '\.changefile$' | sort)
    
    echo "DEBUG: retrieved before stash changefiles..." >&2

    # Execute git stash
        # Note: `git stash` sometimes calls clean filter...
        # Note: As of git v2.52.0, the FILE_SEPARATOR is only valid for the "push" STASH_COMMAND
    echo "DEBUG: '$git_path stash ${stash_args[@]}'" >&2
    if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
        "$git_path" stash "${stash_command_args[@]}" -- "${parsed_file_path_args[@]}"
    else
        "$git_path" stash "${stash_args[@]}"
    fi
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne 0 ]; then
        echo "git stash failed" >&2
        exit_fstash $STASH_RESULT
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

else
    echo "Error: Impossible logic branch reached in git-stash-and-sync-FCStd-files.sh" >&2
    exit_fstash $FAIL
fi

exit_fstash $SUCCESS