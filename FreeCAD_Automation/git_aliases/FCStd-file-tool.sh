#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to run the FCStdFileTool.py script manually via `git ftool`, git `fimport`, `git fexport` aliases

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Note: PWD for all scripts called via git aliases is the root of the git repository

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

if [ -z "$PYTHON_PATH" ]; then
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                                          Parse Args
# ==============================================================================================
# CALLER_SUBDIR=${GIT_PREFIX}:
    # If caller's pwd is $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller's pwd is $GIT_ROOT, $(GIT_PREFIX) = ""
CALLER_SUBDIR="$1"
shift

ALIAS_MODE=""
case $1 in
    "--fimport")
        ALIAS_MODE="$1"
        shift
        ;;

    "--fexport")
        ALIAS_MODE="$1"
        shift
        ;;
esac

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_args=()
if [ "$CALLER_SUBDIR" != "" ]; then
    for arg in "$@"; do
        case $arg in
            -*)
                parsed_args+=("$arg")
                ;;
            ".")
                parsed_args+=("$CALLER_SUBDIR")
                ;;
            *)
                parsed_args+=("${CALLER_SUBDIR}${arg}")
                ;;
        esac
    done
else
    parsed_args=("$@")
fi

# ==============================================================================================
#                                   Match Args to FCStd Files
# ==============================================================================================
MATCHED_FCStd_file_paths=()
if [ -n "$ALIAS_MODE" ]; then
    for file_path in "${parsed_args[@]}"; do
        # echo "DEBUG: Matching file_path: '$file_path'...." >&2

        if [[ -d "$file_path" || "$file_path" == *"*"* || "$file_path" == *"?"* ]]; then
            # echo "DEBUG: file_path contains wildcards or is a directory" >&2
            
            mapfile -t FCStd_files_matching_pattern < <(GIT_COMMAND="ls-files" git ls-files -- "$file_path" && GIT_COMMAND="ls-files" git ls-files --others --exclude-standard -- "$file_path")
            for file in "${FCStd_files_matching_pattern[@]}"; do
                if [[ "$file" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
                    # echo "DEBUG: Matched '$file'" >&2
                    MATCHED_FCStd_file_paths+=("$file")
                fi
            done

        elif [[ "$file_path" =~ \.[fF][cC][sS][tT][dD]$ ]]; then
            # echo "DEBUG: file_path is an FCStd file" >&2
            MATCHED_FCStd_file_paths+=("$file_path")
        else
            # echo "DEBUG: file_path '$file_path' is not an FCStd file, directory, or wildcard..... skipping" >&2
            :
        fi
    done

    if [ ${#MATCHED_FCStd_file_paths[@]} -gt 0 ]; then
        mapfile -t MATCHED_FCStd_file_paths < <(printf '%s\n' "${MATCHED_FCStd_file_paths[@]}" | sort -u) # Remove duplicates (creates an empty element if no elements)

    else
        echo "Error: No valid .FCStd files found. Usage: git fimport [path/to/file.FCStd ...] or git fexport [path/to/file.FCStd ...]" >&2
        exit $FAIL
    fi
fi

# ==============================================================================================
#                                    Call FCStdFileTool.py
# ==============================================================================================
case $ALIAS_MODE in
    "--fimport")
        for FCStd_file_path in "${MATCHED_FCStd_file_paths[@]}"; do
            echo -n "IMPORTING: '$FCStd_file_path'...." >&2
            
            # Import data to FCStd file
            "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --import "$FCStd_file_path" || {
                echo >&2
                echo "ERROR: Failed to import '$FCStd_file_path', skipping..." >&2
                continue
            }
            
            echo "SUCCESS" >&2
            
            # Handle locks
            if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
                FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || continue

                if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                    # User doesn't have lock, set .FCStd file to readonly
                    make_readonly "$FCStd_file_path"
                    # echo "DEBUG: Set '$FCStd_file_path' readonly." >&2
                else
                    # User has lock, set .FCStd file to writable
                    make_writable "$FCStd_file_path"
                    # echo "DEBUG: Set '$FCStd_file_path' writable." >&2
                fi
            fi
        done
        ;;

    "--fexport")
        for FCStd_file_path in "${MATCHED_FCStd_file_paths[@]}"; do
            echo -n "EXPORTING: '$FCStd_file_path'...." >&2
            
            if [ ! -s "$1" ]; then
                echo >&2
                echo "ERROR: '$FCStd_file_path' is empty, skipping..." >&2
                continue
            fi

            # Import data to FCStd file
            "$PYTHON_EXEC" "$FCStdFileTool" --SILENT --CONFIG-FILE --export "$FCStd_file_path" || {
                echo >&2
                echo "ERROR: Failed to export '$FCStd_file_path', skipping..." >&2
                continue
            }
            
            echo "SUCCESS" >&2
            
            # Handle locks
            if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
                FCSTD_FILE_HAS_VALID_LOCK="$(FCStd_file_has_valid_lock "$FCStd_file_path")" || continue

                if [ "$FCSTD_FILE_HAS_VALID_LOCK" = "$FALSE" ]; then
                    # User doesn't have lock, set .FCStd file to readonly
                    make_readonly "$FCStd_file_path"
                    # echo "DEBUG: Set '$FCStd_file_path' readonly." >&2
                else
                    # User has lock, set .FCStd file to writable
                    make_writable "$FCStd_file_path"
                    # echo "DEBUG: Set '$FCStd_file_path' writable." >&2
                fi
            fi
        done
        ;;

    *)
        exec "$PYTHON_EXEC" "$FCStdFileTool" "${parsed_args[@]}"
        ;;
esac

exit $SUCCESS