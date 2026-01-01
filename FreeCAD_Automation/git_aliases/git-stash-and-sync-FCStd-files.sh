#!/bin/bash
# echo "DEBUG: ============== git-stash-and-sync-FCStd-files trap-card triggered! ==============" >&2
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
if [ "$GITCAD_ACTIVATED" = "$TRUE" ]; then
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
    trap - EXIT
    
    if [ "$GIT_COMMAND_ALREADY_SET" = "$FALSE" ]; then 
        unset GIT_COMMAND
    fi
    
    case $1 in
        "")
            echo "Error: No exit code provided, exiting with fail!" >&2
            exit $FAIL
            ;;
        *)
            # echo "DEBUG: exiting with code '$1'..." >&2
            exit $1
            ;;
    esac
}
trap "exit_fstash $FAIL" EXIT

if [ -z "$PYTHON_PATH" ] || [ -z "$REQUIRE_LOCKS" ]; then
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit_fstash $FAIL
fi

if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
    CURRENT_USER="$(GIT_COMMAND="config" "$git_path" config --get user.name)" || {
        echo "Error: git config user.name not set!" >&2
        exit_fstash $FAIL
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

# ==============================================================================================
#                                          Parse Args
# ==============================================================================================
# CALLER_SUBDIR=${GIT_PREFIX}:
    # If caller's pwd is $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller's pwd is $GIT_ROOT, $(GIT_PREFIX) = ""

CALLER_SUBDIR="$1"
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

if [ $# -eq 0 ]; then
    STASH_COMMAND="push"
fi

while [ $# -gt 0 ]; do
    # echo "DEBUG: parsing '$1'..." >&2
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
            # echo "DEBUG: POP_OR_APPLY_FLAG set for '$STASH_COMMAND'" >&2
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
            if [ -z "$STASH_COMMAND" ]; then
                STASH_COMMAND="push"
            fi

            FILE_SEPARATOR_FLAG=$TRUE
            # echo "DEBUG: FILE_SEPARATOR_FLAG set" >&2
            ;;
        
        # ===== Capture `git stash` Flags =====
        -*)
            if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
                echo "Error: '$1' flag is invalid after '--' file separator" >&2
                exit_fstash $FAIL
            fi

            # echo "DEBUG: '$1' flag is not recognized, skipping..." >&2
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
                            # echo "DEBUG: '$1' -> '$CALLER_SUBDIR'" >&2
                            parsed_file_path_args+=("$CALLER_SUBDIR")
                            ;;
                        *)
                            # echo "DEBUG: prepend '$1'" >&2
                            parsed_file_path_args+=("${CALLER_SUBDIR}${1}")
                            ;;
                    esac
                else
                    # echo "DEBUG: Don't prepend '$1'" >&2
                    parsed_file_path_args+=("$1")
                fi
            
            else
                stash_command_args+=("$1")
                # echo "DEBUG: '$1' not recognized, skipping..." >&2
            fi
            ;;
    esac
    shift
done

# ==============================================================================================
#                                   Execute Stash n' Import
# ==============================================================================================
if [ "$STASH_COMMAND_DOES_NOT_MODIFY_WORKING_DIR_OR_CREATE_STASHES" = "$TRUE" ]; then
    # echo "DEBUG: stash command does not modify working directory or create stashes. Passing command directly to git stash." >&2
    # echo "DEBUG: '$git_path stash ${stash_args[@]}'" >&2
    GIT_COMMAND="stash" "$git_path" stash "${stash_args[@]}"





# ============= Called stash command involves applying stash to working directory ==============
elif [ "$STASH_COMMAND" = "pop" ] || [ "$STASH_COMMAND" = "apply" ] || [ "$STASH_COMMAND" = "branch" ]; then
    # echo "DEBUG: Stash pop/apply/branch detected" >&2

    if [ -z "$STASH_REF" ]; then
        STASH_REF="stash@{0}"
    fi

    # Check that user has valid lock
    # Note: This should never be true, as of git v2.52.0, the FILE_SEPARATOR is only valid for the "push" STASH_COMMAND
    CHANGEFILES_IN_STASH_BEING_APPLIED=()
    FCSTD_FILES_IN_STASH_BEING_APPLIED=()
    if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
        for index in "${!parsed_file_path_args[@]}"; do
            file_path="${parsed_file_path_args[index]}"
            
            # echo "DEBUG: Matching file_path: '$file_path'...." >&2
            # Match pattern to stashed FCStd and changefiles and ensure user has lock
            if [[ -d "$file_path" || "$file_path" == *"*"* || "$file_path" == *"?"* ]]; then
                # echo "DEBUG: file_path contains wildcards or is a directory" >&2
        
                mapfile -t stashed_files_matching_pattern < <(GIT_COMMAND="stash" "$git_path" stash show --name-only "$STASH_REF" 2>/dev/null | grep -F -- "$file_path")
                for file in "${stashed_files_matching_pattern[@]}"; do
                    if [[ "$file" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                        FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$file")" || exit_fstash $FAIL

                        if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                            echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                            exit_fstash $FAIL
                        fi

                        FCSTD_FILES_IN_STASH_BEING_APPLIED+=("$file")
                    
                    elif [[ "$file" =~ \.changefile$ ]]; then
                        # echo "DEBUG: Matched '$file'" >&2
                        FCStd_file_path="$(get_FCStd_file_from_changefile "$file")" || exit_fstash $FAIL
                        
                        FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || exit_fstash $FAIL

                        if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                            echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                            exit_fstash $FAIL
                        fi

                        CHANGEFILES_IN_STASH_BEING_APPLIED+=("$file")

                    fi
                done
            
            # Check for (exit early if true)
                # If specified FCStd file is modified
                # If specified FCStd file has invalid lock
            # If valid, change file_path in parsed_file_path_args to the FCStd_dir_path
            elif [[ "$file_path" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                # echo "DEBUG: file_path is an FCStd file" >&2
                FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$file_path")" || exit_fstash $FAIL

                if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                    echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                    exit_fstash $FAIL
                fi

                FCSTD_FILES_IN_STASH_BEING_APPLIED+=("$file_path")
                
            # Check user has lock for changefile being stashed
            elif [[ "$file_path" =~ \.changefile$ ]]; then
                # echo "DEBUG: file_path is a changefile" >&2
                FCStd_file_path="$(get_FCStd_file_from_changefile "$file_path")" || exit_fstash $FAIL
                
                FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || exit_fstash $FAIL

                if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                    echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                    exit_fstash $FAIL
                fi

                CHANGEFILES_IN_STASH_BEING_APPLIED+=("$file_path")
            
            else
                # echo "DEBUG: file_path '$file_path' is not an FCStd file, changefile, directory, or wildcard..... skipping" >&2
                :
            fi
        done
    else
        mapfile -t CHANGEFILES_IN_STASH_BEING_APPLIED < <(GIT_COMMAND="stash" "$git_path" stash show --name-only "$STASH_REF" 2>/dev/null | grep -i -- '\.changefile$' || true)
        mapfile -t FCSTD_FILES_IN_STASH_BEING_APPLIED < <(GIT_COMMAND="stash" "$git_path" stash show --name-only "$STASH_REF" 2>/dev/null | grep -i -- '\.fcstd$' || true)
        
        # echo -e "\nDEBUG: checking stashed changefiles: '$(echo "${CHANGEFILES_IN_STASH_BEING_APPLIED[@]}")'" >&2
        # echo -e "\nDEBUG: checking stashed FCStd files: '$(echo "${FCSTD_FILES_IN_STASH_BEING_APPLIED[@]}")'" >&2

        # Note 1: If a user stashes both a .FCStd file and its associated .changefile at the same time, the .FCStd file will be overwritten with .changefile data during the import stage later.
        # Note 2: User is prevented from stashing .FCStd files using this script.
        for changefile_path in "${CHANGEFILES_IN_STASH_BEING_APPLIED[@]}"; do
            # echo -e "\nDEBUG: checking '$changefile_path'....$(grep 'File Last Exported On:' "$changefile_path")" >&2

            # Note: code mostly copied from utils `get_FCStd_file_from_changefile()` except we check the stashed .changefile instead of the working dir .changefile
                # Read the line with FCStd_file_relpath
                FCStd_file_relpath_line_in_changefile="$(GIT_COMMAND="cat-file" git cat-file -p "$STASH_REF":"$changefile_path" | grep -F -- "FCStd_file_relpath=")"
                if [ -z "$FCStd_file_relpath_line_in_changefile" ]; then
                    echo "Error: FCStd_file_relpath not found in '$changefile_path'" >&2
                    exit_fstash $FAIL
                fi

                # Extract the FCStd_file_relpath value
                FCStd_file_relpath="$(echo "$FCStd_file_relpath_line_in_changefile" | sed "s/FCStd_file_relpath='\([^']*\)'/\1/")"

                # Derive the FCStd_file_path from the FCStd_file_relpath
                FCStd_dir_path="$(dirname "$changefile_path")"
                
                FCStd_file_path="$(realpath "$FCStd_dir_path/$FCStd_file_relpath")"

                if [[ "${OSTYPE^^}" == "CYGWIN"* || "${OSTYPE^^}" == "MSYS"* || "${OSTYPE^^}" == "MINGW"* ]]; then
                    FCStd_file_path="$(echo "${FCStd_file_path#/}" | sed -E 's#^([a-zA-Z])/#\U\1:/#')" # Note: Convert drive letters IE `/d/` to `D:/` 
                fi

                FCStd_file_path="$(realpath --canonicalize-missing --relative-to="$(GIT_COMMAND="rev-parse" git rev-parse --show-toplevel)" "$FCStd_file_path")"

                FCStd_file_paths_derived_from_stashed_changefiles+=("$FCStd_file_path")

            FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || exit_fstash $FAIL

            if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                exit_fstash $FAIL
            fi
        done
        
        for FCStd_file_path in "${FCSTD_FILES_IN_STASH_BEING_APPLIED[@]}"; do
            # echo -e -n "\nDEBUG: checking '$FCStd_file_path'...." >&2
            FCStd_dir_path="$(get_FCStd_dir "$FCStd_file_path")" || continue
            # echo -e "$(grep 'File Last Exported On:' "$FCStd_dir_path/.changefile")" >&2

            FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || exit_fstash $FAIL

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
        GIT_COMMAND="stash" "$git_path" stash "${stash_command_args[@]}" -- "${parsed_file_path_args[@]}"
    else
        GIT_COMMAND="stash" "$git_path" stash "${stash_args[@]}"
    fi
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne $SUCCESS ]; then
        echo "Error: git stash $STASH_COMMAND failed" >&2
        exit_fstash $STASH_RESULT
    fi

    # Synchronize .FCStd files with applied changes
    for changefile_path in "${CHANGEFILES_IN_STASH_BEING_APPLIED[@]}"; do
        # echo -e "\nDEBUG: checking '$changefile_path'....$(grep -F -- 'File Last Exported On:' "$changefile_path")" >&2
        
        FCStd_file_path="$(get_FCStd_file_from_changefile "$changefile_path")" || continue
        
        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo >&2
            echo "ERROR: Failed to import '$FCStd_file_path', skipping..." >&2
            continue
        }
        echo "SUCCESS" >&2

        GIT_COMMAND="fcmod" "$git_path" fcmod "$FCStd_file_path"
    done







# ===== Called stash command involves stashing away working directory changes (creating stashes) =====
elif [ "$STASH_COMMAND" = "push" ] || [ "$STASH_COMMAND" = "save" ] || [ "$STASH_COMMAND" = "create" ]; then
    # echo "DEBUG: Stash push/save/create detected" >&2
    
    GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1
    mapfile -t MODIFIED_FCSTD_FILES < <(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.fcstd$' || true)
    mapfile -t MODIFIED_CHANGEFILES < <(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.changefile$' || true)
    
    # Check that:
        # User is not trying to stash any .FCStd files
            # Note: The reason I'm not allowing the user to stash away .FCStd files is because .FCStd files can hide changes whenever `git fcmod` gets called on them (I think it's bad practice).
        # User has lock for files being stashed
    # For File Separator Case:
        # Redirect FCStd_file_paths to their FCStd_dir_paths
    if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
        
        for index in "${!parsed_file_path_args[@]}"; do
            file_path="${parsed_file_path_args[index]}"
            
            # echo "DEBUG: Matching file_path: '$file_path'...." >&2
            # Match pattern to modified FCStd and changefiles
                # If pattern matches FCStd file, exit early
            # Ensure user has lock for changefiles being stashed
            if [[ -d "$file_path" || "$file_path" == *"*"* || "$file_path" == *"?"* ]]; then
                # echo "DEBUG: file_path contains wildcards or is a directory" >&2
        
                mapfile -t modified_files_matching_pattern < <(GIT_COMMAND="ls-files" "$git_path" ls-files -m "$file_path")
                for file in "${modified_files_matching_pattern[@]}"; do
                    if [[ "$file" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                        echo "Error: Cannot stash '$file', export it first with \`git fadd\` or \`git add\` with GitCAD activated." >&2
                        exit_fstash $FAIL
                    
                    elif [[ "$file" =~ \.changefile$ ]]; then
                        # echo "DEBUG: Matched '$file'" >&2
                        FCStd_file_path="$(get_FCStd_file_from_changefile "$file")" || exit_fstash $FAIL
                        
                        FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || exit_fstash $FAIL

                        if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                            echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                            exit_fstash $FAIL
                        fi
                    fi
                done
            
            # Check for (exit early if true)
                # If specified FCStd file is modified
                # If specified FCStd file has invalid lock
            # If valid, change file_path in parsed_file_path_args to the FCStd_dir_path
            elif [[ "$file_path" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                # echo "DEBUG: file_path is an FCStd file" >&2
                
                if printf '%s\n' "${MODIFIED_FCSTD_FILES[@]}" | grep -Fxq -- "$file_path"; then
                    echo "Error: Cannot stash '$file_path', export it first with \`git fadd\` or \`git add\` with GitCAD activated." >&2
                    exit_fstash $FAIL
                fi

                FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$file_path")" || exit_fstash $FAIL

                if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                    echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                    exit_fstash $FAIL
                fi

                FCStd_dir_path="$(get_FCStd_dir "$file_path")" || exit_fstash $FAIL
                parsed_file_path_args[index]="$FCStd_dir_path"
                
            # Check user has lock for changefile being stashed
            elif [[ "$file_path" =~ \.changefile$ ]]; then
                # echo "DEBUG: file_path is a changefile" >&2
                FCStd_file_path="$(get_FCStd_file_from_changefile "$file_path")" || exit_fstash $FAIL
                
                FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || exit_fstash $FAIL

                if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                    echo "Error: User does not have valid lock for '$FCStd_file_path' in stash" >&2
                    exit_fstash $FAIL
                fi
            else
                # echo "DEBUG: file_path '$file_path' is not an FCStd file, changefile, directory, or wildcard..... skipping" >&2
                :
            fi
        done
    
    
    else # IF Stashing all modified files
        
        # Check for FCStd files being stashed
        if [ ! ${#MODIFIED_FCSTD_FILES[@]} -eq 0 ]; then
            echo "Error: Cannot stash the following .FCStd files, export them first with \`git fadd\` or \`git add\` with GitCAD activated:" >&2
            printf '%s\n' "       ${MODIFIED_FCSTD_FILES[@]}" >&2
            exit_fstash $FAIL
        fi

        # Check locks for changefiles being stashed
        for changefile_path in "${MODIFIED_CHANGEFILES[@]}"; do
            FCStd_file_path="$(get_FCStd_file_from_changefile "$changefile_path")" || exit_fstash $FAIL
            
            FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || exit_fstash $FAIL
            
            if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                echo "Error: User does not have valid lock for '$FCStd_file_path'" >&2
                exit_fstash $FAIL
            fi
        done
    fi
    
    # Get modified changefiles before stash
    GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1
    mapfile -t BEFORE_STASH_CHANGEFILES < <(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.changefile$' | sort)
    
    # echo "DEBUG: retrieved before stash changefiles..." >&2

    # Execute git stash
        # Note: `git stash` sometimes calls clean filter...
        # Note: As of git v2.52.0, the FILE_SEPARATOR is only valid for the "push" STASH_COMMAND
    if [ "$FILE_SEPARATOR_FLAG" = "$TRUE" ]; then
        # echo "DEBUG: '$git_path stash "${stash_command_args[@]}" -- "${parsed_file_path_args[@]}"'" >&2
        GIT_COMMAND="stash" "$git_path" stash "${stash_command_args[@]}" -- "${parsed_file_path_args[@]}"
    else
        # echo "DEBUG: '$git_path stash ${stash_args[@]}'" >&2
        GIT_COMMAND="stash" "$git_path" stash "${stash_args[@]}"
    fi
    STASH_RESULT=$?

    if [ $STASH_RESULT -ne $SUCCESS ]; then
        echo "Error: git stash $STASH_COMMAND failed" >&2
        exit_fstash $STASH_RESULT
    fi

    # Get modified lockfiles after stash
    GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1
    mapfile -t AFTER_STASH_CHANGEFILE < <(GIT_COMMAND="diff-index" "$git_path" diff-index --name-only HEAD | grep -i -- '\.changefile$' | sort)

    # Find files present before stash but not after stash (files that were stashed)
    STASHED_CHANGEFILES="$(comm -23 <(printf '%s\n' "${BEFORE_STASH_CHANGEFILES[@]}") <(printf '%s\n' "${AFTER_STASH_CHANGEFILE[@]}"))"

    # echo -e "\nDEBUG: Importing stashed changefiles: '${STASHED_CHANGEFILES[@]}'" >&2

    # Import the files that are no longer modified (those that were stashed)
    for changefile_path in "${STASHED_CHANGEFILES[@]}"; do
        # echo -e "\nDEBUG: checking '$changefile_path'....$(grep -F -- 'File Last Exported On:' "$changefile_path")" >&2
        
        FCStd_file_path="$(get_FCStd_file_from_changefile "$changefile_path")" || continue
        
        echo -n "IMPORTING: '$FCStd_file_path'...." >&2
        "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
            echo >&2
            echo "ERROR: Failed to import '$FCStd_file_path', skipping..." >&2
            continue
        }
        echo "SUCCESS" >&2
        
        GIT_COMMAND="fcmod" "$git_path" fcmod "$FCStd_file_path"
    done

else
    echo "Error: Impossible logic branch reached in git-stash-and-sync-FCStd-files.sh" >&2
    exit_fstash $FAIL
fi

exit_fstash $SUCCESS