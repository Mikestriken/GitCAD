#!/bin/bash
# echo "DEBUG: ============== clear-FCStd-modification.sh trap-card triggered! ==============" >&2
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Script to create .fcmod files with current timestamp to mark when .FCStd file modifications were cleared.
# First it makes sure there are no added .FCStd files, then creates/updates .fcmod files for specified .FCStd files.

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
#                                   Restore Staged FCStd files
# ==============================================================================================
# Get staged `.FCStd` files
# Diff Filter => (A)dded / (C)opied / (D)eleted / (M)odified / (R)enamed / (T)ype changed / (U)nmerged / (X) unknown / (B)roken pairing
GIT_COMMAND="update-index" "$git_path" update-index --refresh -q >/dev/null 2>&1
STAGED_FCSTD_FILES="$(GIT_COMMAND="diff-index" git diff-index --cached --name-only --diff-filter=CDMRTUXB HEAD | grep -i -- '\.fcstd$')"

if [ -n "$STAGED_FCSTD_FILES" ]; then
    mapfile -t STAGED_FCSTD_FILES <<<"$STAGED_FCSTD_FILES"
    GIT_COMMAND="restore" "$git_path" restore --staged "${STAGED_FCSTD_FILES[@]}"
fi

# ==============================================================================================
#                                          Parse Args
# ==============================================================================================
# CALLER_SUBDIR=${GIT_PREFIX}:
    # If caller's pwd is $GIT_ROOT/subdir, $(GIT_PREFIX) = "subdir/"
    # If caller's pwd is $GIT_ROOT, $(GIT_PREFIX) = ""
CALLER_SUBDIR="$1"
shift

# Parse remaining args: prepend CALLER_SUBDIR to paths (skip args containing '-')
parsed_file_path_args=()
# echo "DEBUG: parsing '$@'" >&2
while [ $# -gt 0 ]; do
    # echo "DEBUG: parsing '$1'..." >&2
    case $1 in
        # Set boolean flag if arg is a valid flag
        -*)
            echo "Error: '$1' flag is not recognized, skipping..." >&2
            ;;
        
        # Assume arg is path. Fix path to be relative to root of the git repo instead of user's terminal pwd.
        *)
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
            ;;
    esac
    shift
done

# ==============================================================================================
#                                   Match Args to FCStd Files
# ==============================================================================================
MATCHED_FCStd_file_paths=()
for file_path in "${parsed_file_path_args[@]}"; do
    # echo "DEBUG: Matching file_path: '$file_path'...." >&2

    if [[ -d "$file_path" || "$file_path" == *"*"* || "$file_path" == *"?"* ]]; then
        # echo "DEBUG: file_path contains wildcards or is a directory" >&2
        
        mapfile -t modified_files_matching_pattern < <(GIT_COMMAND="ls-files" "$git_path" ls-files -m -- "$file_path")
        for file in "${modified_files_matching_pattern[@]}"; do
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
fi

# echo "DEBUG: matched '${#MATCHED_FCStd_file_paths[@]}' .FCStd files: '${MATCHED_FCStd_file_paths[@]}'" >&2

# ==============================================================================================
#                              Create .fcmod Files For Matched FCStd Files
# ==============================================================================================
current_timestamp="$(date -u +"%Y-%m-%dT%H:%M:%S.%6N%:z")"

for FCStd_file_path in "${MATCHED_FCStd_file_paths[@]}"; do
    # echo "DEBUG: Processing FCStd file: '$FCStd_file_path'" >&2

    FCStd_dir_path="$(get_FCStd_dir "$FCStd_file_path")" || continue
    fcmod_path="$FCStd_dir_path/.fcmod"

    mkdir -p "$(dirname "$fcmod_path")"
    echo "$current_timestamp" > "$fcmod_path"
    # echo "DEBUG: Created/updated .fcmod for '$FCStd_file_path' with timestamp '$current_timestamp'" >&2
    
    echo "Cleared modification for '$FCStd_file_path'" >&2
done

# ==============================================================================================
#                              Clear Modifications For Specified Files
# ==============================================================================================
GIT_COMMAND="fcmod" "$git_path" add "${parsed_file_path_args[@]}"