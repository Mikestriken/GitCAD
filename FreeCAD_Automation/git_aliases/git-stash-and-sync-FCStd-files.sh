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
# ToDo TEST: git unlocking with a stashed .FCStd file change
# ToDo TEST: git checkout stash@{0} -- path/to/file
if [ "$STASH_COMMAND_DOES_NOT_MODIFY_WORKING_DIR_OR_CREATE_STASHES" = "$TRUE" ]; then
    echo "DEBUG: stash command does not modify working directory or create stashes. Passing command directly to git stash." >&2
    echo "DEBUG: '$git_path stash ${stash_args[@]}'" >&2
    "$git_path" stash "${stash_args[@]}"

# ===== Called stash command involves applying stash to working directory =====
elif [ "$STASH_COMMAND" = "pop" ] || [ "$STASH_COMMAND" = "apply" ] || [ "$STASH_COMMAND" = "branch" ]; then
    echo "DEBUG: Stash pop/apply/branch detected" >&2

    # Check that user has valid lock
    # ToDo: Add git ls-files logic to handle wildcards in parsed_file_path_args (when checking for valid locks)
    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        if [ -z "$STASH_REF" ]; then
            STASH_REF="stash@{0}"
        fi
        
        STASHED_CHANGEFILES=$("$git_path" stash show --name-only "$STASH_REF" 2>/dev/null | grep -i '\.changefile$' || true)
        STASHED_FCSTD_FILES=$("$git_path" stash show --name-only "$STASH_REF" 2>/dev/null | grep -i '\.fcstd$' || true)

        # echo -e "\nDEBUG: checking stashed changefiles: '$(echo $STASHED_CHANGEFILES | xargs)'" >&2
        # echo -e "\nDEBUG: checking stashed FCStd files: '$(echo $STASHED_FCSTD_FILES | xargs)'" >&2

        # Note: It is impossible for the user to stash both a .FCStd file and its associated .changefile at same time (otherwise stash application logic would overwrite said .FCStd file with .changefile data)
        FCStd_file_paths_derived_from_stashed_changefiles=()
        for changefile in $STASHED_CHANGEFILES; do
            # echo -e "\nDEBUG: checking '$changefile'....$(grep 'File Last Exported On:' "$changefile")" >&2

            # Note: code mostly copied from utils `get_FCStd_file_from_changefile()` except we check the stashed .changefile instead of the working dir .changefile
                if ! git cat-file -e "$STASH_REF":"$changefile" > /dev/null 2>&1; then
                    echo "Error: changefile '$changefile' does not exist" >&2
                    return $FAIL
                fi

                # Read the line with FCStd_file_relpath
                FCStd_file_relpath_line_in_changefile=$(git cat-file -p "$STASH_REF":"$changefile" | grep "FCStd_file_relpath=")
                if [ -z "$FCStd_file_relpath_line_in_changefile" ]; then
                    echo "Error: FCStd_file_relpath not found in '$changefile'" >&2
                    exit_fstash $FAIL
                fi

                # Extract the FCStd_file_relpath value
                FCStd_file_relpath=$(echo "$FCStd_file_relpath_line_in_changefile" | sed "s/FCStd_file_relpath='\([^']*\)'/\1/")

                # Derive the FCStd_file_path from the FCStd_file_relpath
                FCStd_dir_path=$(dirname "$changefile")
                
                FCStd_file_path=$(realpath "$FCStd_dir_path/$FCStd_file_relpath")

                if [ "$OSTYPE" = "msys" ] || [ "$OSTYPE" = "win32" ]; then
                    FCStd_file_path="$(echo "${FCStd_file_path#/}" | sed -E 's#^([a-zA-Z])/#\U\1:/#')" # Note: Convert drive letters IE `/d/` to `D:/` 
                fi

                FCStd_file_path="$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$FCStd_file_path")"

                FCStd_file_paths_derived_from_stashed_changefiles+=("$FCStd_file_path")

            FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$FCStd_file_path") || exit $FAIL

            if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                exit_fstash $FAIL
            fi
        done

        for FCStd_file_path in $STASHED_FCSTD_FILES; do
            # echo -e -n "\nDEBUG: checking '$FCStd_file_path'...." >&2
            FCStd_dir_path=$(get_FCStd_dir "$FCStd_file_path") || continue
            # echo -e "$(grep 'File Last Exported On:' "$FCStd_dir_path/.changefile")" >&2

            FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$FCStd_file_path") || exit $FAIL

            if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
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
    for FCStd_file_path in "${FCStd_file_paths_derived_from_stashed_changefiles[@]}"; do
        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo "Failed to import $FCStd_file_path" >&2
        }
        echo "SUCCESS" >&2
    done

# ===== Called stash command involves stashing away working directory changes (creating stashes) =====
elif [ "$STASH_COMMAND" = "push" ] || [ "$STASH_COMMAND" = "save" ] || [ "$STASH_COMMAND" = "create" ]; then
    echo "DEBUG: Stash push/save/create detected" >&2
    
    # Get list of currently modified files
    "$git_path" update-index --refresh -q >/dev/null 2>&1
    MODIFIED_FCSTD_FILES=$("$git_path" diff-index --name-only HEAD | grep -i '\.fcstd$' || true)
    MODIFIED_CHANGEFILES=$("$git_path" diff-index --name-only HEAD | grep -i '\.changefile$' || true)
    
    # Check that user is not trying to stash both .FCStd file and its associated .changefile at same time
    # This would cause issues because stash application logic will overwrite the .FCStd file with .changefile changes
    if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
        # Build list of FCStd files and changefiles that will be stashed
        FCStd_file_paths_to_stash=()
        FCStd_dir_paths_to_stash=()
        
        for file_path in "${parsed_file_path_args[@]}"; do
            echo "DEBUG: Matching file_path: '$file_path'...." >&2
            
            if [[ -d "$file_path" || "$file_path" == *"*"* || "$file_path" == *"?"* ]]; then
                echo "DEBUG: file_path contains wildcards or is a directory" >&2
                while IFS= read -r file; do
                    if [[ "$file" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                        echo "DEBUG: Matched '$file'" >&2
                        FCStd_file_paths_to_stash+=("$file")
                    
                    elif [[ "$file" =~ \.changefile$ ]]; then
                        echo "DEBUG: Matched '$(dirname "$file")'" >&2
                        FCStd_dir_paths_to_stash+=("$(dirname "$file")")
                    fi
                done < <("$git_path" ls-files "$file_path")
            
            elif [[ "$file_path" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                echo "DEBUG: file_path is an FCStd file" >&2
                FCStd_file_paths_to_stash+=("$file_path")
                
            elif [[ "$file_path" =~ \.changefile$ ]]; then
                echo "DEBUG: file_path is a changefile" >&2
                FCStd_dir_paths_to_stash+=("$(dirname "$file_path")")
            fi
        done
        
        # Remove duplicates
        FCStd_file_paths_to_stash=($(printf '%s\n' "${FCStd_file_paths_to_stash[@]}" | sort -u))
        FCStd_dir_paths_to_stash=($(printf '%s\n' "${FCStd_dir_paths_to_stash[@]}" | sort -u))
        
        echo "DEBUG: matched FCStd files: ${FCStd_file_paths_to_stash[@]}" >&2
        echo "DEBUG: matched changefiles: ${FCStd_dir_paths_to_stash[@]}" >&2

        if [ ${#FCStd_file_paths_to_stash[@]} -eq 0 ] && [ ${#FCStd_dir_paths_to_stash[@]} -eq 0 ]; then
            # ToDo: This means the command can be directly passed through.
            echo "DEBUG: No FCStd files or changefiles matched the patterns" >&2
        fi
        
        # If specified FCStd file is not modified, redirect stash to its directory instead
        for FCStd_file_path in "${FCStd_file_paths_to_stash[@]}"; do
            if ! echo "$MODIFIED_FCSTD_FILES" | grep -q "^$FCStd_file_path$"; then
                echo "DEBUG: '$FCStd_file_path' is not modified, redirecting stash to its directory '$FCStd_dir_path'" >&2
                
                # Remove FCStd file from list and add its directory to list
                # ToDo: Check redirection is handled correctly later during the git stash call
                FCStd_file_paths_to_stash=($(printf '%s\n' "${FCStd_file_paths_to_stash[@]}" | grep -v "^$FCStd_file_path$"))
                FCStd_dir_paths_to_stash+=("$FCStd_dir_path")
            fi
        done

        # Check for conflicts: FCStd file and its changefile both being stashed
        associated_FCStd_dir_paths_of_FCStd_files_paths_to_stash=($(for FCStd_file_path in "${FCStd_file_paths_to_stash[@]}"; do get_FCStd_dir "$FCStd_file_path" 2>/dev/null || true; done | sort -u))
        
        conflicting_FCStd_dir_paths_stashed_by_both_changefile_and_FCStd_file=$(comm -12 <(printf '%s\n' "${associated_FCStd_dir_paths_of_FCStd_files_paths_to_stash[@]}") <(printf '%s\n' "${FCStd_dir_paths_to_stash[@]}"))
        
        if [ -n "$conflicting_FCStd_dir_paths_stashed_by_both_changefile_and_FCStd_file" ]; then
            echo "Error: Cannot stash both .FCStd file and its associated changefile directory at the same time." >&2
            echo "       Conflicting directories: $conflicting_FCStd_dir_paths_stashed_by_both_changefile_and_FCStd_file" >&2
            echo "       Export the .FCStd file first with \`git fadd\` or \`git add\` with GitCAD activated." >&2
            exit_fstash $FAIL
        fi
        
        # Check locks for FCStd files being stashed
        for FCStd_file_path in "${FCStd_file_paths_to_stash[@]}"; do
            FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$FCStd_file_path") || exit_fstash $FAIL
            
            if [ "$FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                echo "Error: User does not have valid lock for '$FCStd_file_path'" >&2
                exit_fstash $FAIL
            fi
        done
        
        # Check locks for changefiles being stashed
        for FCStd_dir_path in "${FCStd_dir_paths_to_stash[@]}"; do
            changefile_path="$FCStd_dir_path/.changefile"
            
            FCStd_file_path=$(get_FCStd_file_from_changefile "$changefile_path") || exit_fstash $FAIL
            
            FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "$FCStd_file_path") || exit_fstash $FAIL
            
            if [ "$FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                echo "Error: User does not have valid lock for '$FCStd_file_path'" >&2
                exit_fstash $FAIL
            fi
        done
    
    else # IF Stashing all modified files
        # Check for conflicts: FCStd file and its changefile both being stashed
        associated_FCStd_dir_paths_of_modified_FCStd_files_paths=($(for FCStd_file_path in $MODIFIED_FCSTD_FILES; do get_FCStd_dir "$FCStd_file_path" 2>/dev/null || true; done | sort -u))
        associated_FCStd_dir_paths_of_modified_changefile_paths=($(for changefile_path in $MODIFIED_CHANGEFILES; do dirname "$changefile_path" 2>/dev/null || true; done | sort -u))
        
        conflicting_FCStd_dir_paths_stashed_by_both_changefile_and_FCStd_file=$(comm -12 <(printf '%s\n' "${associated_FCStd_dir_paths_of_modified_FCStd_files_paths[@]}") <(printf '%s\n' "${associated_FCStd_dir_paths_of_modified_changefile_paths[@]}"))
        
        if [ -n "$conflicting_FCStd_dir_paths_stashed_by_both_changefile_and_FCStd_file" ]; then
            echo "Error: Cannot stash both .FCStd file and its associated changefile directory at the same time." >&2
            echo "       Conflicting directories: $conflicting_FCStd_dir_paths_stashed_by_both_changefile_and_FCStd_file" >&2
            echo "       Export the .FCStd file first with \`git fadd\` or \`git add\` with GitCAD activated." >&2
            exit_fstash $FAIL
        fi

        for FCStd_file_path in $MODIFIED_FCSTD_FILES; do
            FCStd_dir_path=$(get_FCStd_dir "$FCStd_file_path") || continue
            changefile_path="$FCStd_dir_path/.changefile"
            
            # Check if both FCStd file and its changefile are modified
            if echo "$MODIFIED_CHANGEFILES" | grep -q "^$changefile_path$"; then
                echo "Error: Both '$FCStd_file_path' and its associated changefile '$changefile_path' are modified." >&2
                echo "       Export the .FCStd file first with \`git fadd\` or \`git add\` with GitCAD activated before stashing." >&2
                exit_fstash $FAIL
            fi
        done
        # ToDo: Check locks for FCStd files being stashed
        # ToDo: Check locks for changefiles being stashed
    fi
    
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