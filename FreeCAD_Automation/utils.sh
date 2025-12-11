#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Utility functions for the FreeCAD Git automation scripts.

# ==============================================================================================
#                                       Constant Globals
# ==============================================================================================
SUCCESS=0
FAIL=1
TRUE=0
FALSE=1

CONFIG_FILE="FreeCAD_Automation/config.json"
FCStdFileTool="FreeCAD_Automation/FCStdFileTool.py"
PYTHON_EXEC="FreeCAD_Automation/python.sh"

# ==============================================================================================
#                                           Functions
# ==============================================================================================

# DESCRIPTION: Function to extract FreeCAD Python path from config file
    # USAGE: `KEY_VALUE=$(get_json_value_from_key "$JSON_FILE" "$KEY") || exit $FAIL`
get_json_value_from_key() {
    local json_file=$1
    local key=$2
    
    # Find the line containing the key
    local line=$(grep "\"$key\"" "$json_file")
    if [ -z "$line" ]; then
        echo "Error: Key '$key' not found in $json_file" >&2
        return $FAIL
    fi

    # Extract value after : (stops at , or } for simple cases)
    local value=$(echo "$line" | sed 's/.*"'"$key"'": \([^,}]*\).*/\1/')
    
    # Strip surrounding quotes if it's a string
    if [[ $value =~ ^\".*\"$ ]]; then
        value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    fi
    
    echo "$value"
    return $SUCCESS
}

# DESCRIPTION: Function to extract FreeCAD Python path from config file
    # USAGE: `PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || exit $FAIL`
get_freecad_python_path() {
    local config_file="$1"
    local key="freecad-python-instance-path"

    # Get python_path from config file
    local python_path=$(get_json_value_from_key "$config_file" "$key") || return $FAIL
    
    if [ -z "$python_path" ]; then
        echo "Error: Python path is empty" >&2
        return $FAIL
    fi
    
    echo "$python_path"
    return $SUCCESS
}

# DESCRIPTION: Function to extract require-lock-to-modify-FreeCAD-files boolean from config file
# USAGE:
    # `REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || exit $FAIL`
    # `if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then echo "Locks required"; elif [ "$REQUIRE_LOCKS" = "$FALSE" ]; then echo "Locks not required"; fi`
get_require_locks_bool() {
    local config_file=$1
    local key="require-lock-to-modify-FreeCAD-files"
    
    # Get require_locks value from config file
    local require_locks_value=$(get_json_value_from_key "$config_file" "$key") || return $FAIL
    
    if [ -z "$require_locks_value" ]; then
        echo "Error: Require locks value is empty" >&2
        return $FAIL
    fi
    
    # Check if value matches JSON boolean syntax
    if [ "$require_locks_value" = "true" ]; then
        # echo "DEBUG: REQUIRE LOCKS = TRUE" >&2
        echo $TRUE
        return $SUCCESS

    elif [ "$require_locks_value" = "false" ]; then
        # echo "DEBUG: REQUIRE LOCKS = FALSE" >&2
        echo $FALSE
        return $SUCCESS
        
    else
        echo "Error: Value '$require_locks_value' does not match JSON boolean syntax 'true' or 'false'" >&2
        return $FAIL
    fi
}

# DESCRIPTION: Function to extract require-GitCAD-activation boolean from config file
# USAGE:
    # `REQUIRE_GITCAD=$(get_require_gitcad_activation_bool "$CONFIG_FILE") || exit $FAIL`
    # `if [ "$REQUIRE_GITCAD" = "$TRUE" ]; then echo "GitCAD activation required"; elif [ "$REQUIRE_GITCAD" = "$FALSE" ]; then echo "GitCAD activation not required"; fi`
get_require_gitcad_activation_bool() {
    local config_file=$1
    local key="require-GitCAD-activation"
    
    # Get require_activation_value value from config file
    local require_activation_value=$(get_json_value_from_key "$config_file" "$key") || return $FAIL
    
    if [ -z "$require_activation_value" ]; then
        echo "Error: Require GitCAD activation value is empty" >&2
        return $FAIL
    fi
    
    # Check if value matches JSON boolean syntax
    if [ "$require_activation_value" = "true" ]; then
        echo $TRUE
        return $SUCCESS

    elif [ "$require_activation_value" = "false" ]; then
        echo $FALSE
        return $SUCCESS
        
    else
        echo "Error: Value '$require_activation_value' does not match JSON boolean syntax 'true' or 'false'" >&2
        return $FAIL
    fi
}

# DESCRIPTION: Function to make a file readonly on both Linux and Windows (via MSYS/Git Bash)
# USAGE: `make_readonly "path/to/file.ext"`
make_readonly() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "Error: File '$file' does not exist"  >&2
        return $FAIL
    fi

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        chmod 444 "$file"
    
    elif [ "$OSTYPE" = "msys" ] || [ "$OSTYPE" = "win32" ]; then
        attrib +r "$file"
    
    else
        echo "Error: Unsupported operating system: $OSTYPE"  >&2
        return $FAIL
    fi

    return $SUCCESS
}

# DESCRIPTION: Function to make a file writable on both Linux and Windows (via MSYS/Git Bash)
# USAGE: `make_writable "path/to/file.ext"`
make_writable() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "Error: File '$file' does not exist"  >&2
        return $FAIL
    fi

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        chmod 644 "$file"
    
    elif [ "$OSTYPE" = "msys" ] || [ "$OSTYPE" = "win32" ]; then
        attrib -r "$file"
    
    else
        echo "Error: Unsupported operating system: $OSTYPE"  >&2
        return $FAIL
    fi

    return $SUCCESS
}

# DESCRIPTION: Function to get the uncompressed directory path for a .FCStd file
# USAGE: `FCStd_dir_path=$(get_FCStd_dir "path/to/file.FCStd") || exit $FAIL`
get_FCStd_dir() {
    local FCStd_file_path="$1"

    # Get the lockfile path (which gives us the directory structure)
    local FCStd_dir_path
    FCStd_dir_path=$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$("$PYTHON_EXEC" "$FCStdFileTool" --CONFIG-FILE --dir "$FCStd_file_path")") || {
        echo "Error: Failed to get dir path for '$FCStd_file_path'" >&2
        return $FAIL
    }

    # Return the directory path (parent of lockfile)
    echo "$FCStd_dir_path" || return $FAIL

    return $SUCCESS
}

# DESCRIPTION: Function to check if FCStd file has valid lock. Returns $TRUE (0) if valid (no lock required or lock held), $FALSE (1) if invalid (lock required but not held)
# USAGE:
    # `FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "path/to/file.FCStd") || exit $FAIL`
    # `if [ "$FILE_HAS_VALID_LOCK" = "$TRUE" ]; then echo "File has valid lock"; elif [ $FILE_HAS_VALID_LOCK = $FALSE ]; then echo "File has invalid lock"; fi`
FCStd_file_has_valid_lock() {
    local FCStd_file_path="$1"

    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || return $FAIL

    # If locks not required, return valid
    if [ "$REQUIRE_LOCKS" = "$FALSE" ]; then
        # echo "DEBUG: Locks not required, '$FCStd_file_path' lock is valid." >&2
        echo $TRUE
        return $SUCCESS
    fi

    # File not tracked by git (new file), no lock needed (valid lock)
    if ! git cat-file -e HEAD:"$FCStd_file_path" > /dev/null 2>&1; then
        # echo "DEBUG: New .FCStd file, '$FCStd_file_path' lock is valid." >&2
        echo $TRUE
        return $SUCCESS
    fi

    # File is tracked, get the .lockfile path
    local FCStd_dir_path
    local lockfile_path
    FCStd_dir_path=$(get_FCStd_dir "$FCStd_file_path") || exit $FAIL
    lockfile_path="$FCStd_dir_path/.lockfile"

    # Lockfile not tracked by git (new export), no lock needed (valid lock)
    if ! git cat-file -e HEAD:"$lockfile_path" > /dev/null 2>&1; then
        # echo "DEBUG: New .FCStd file export, '$FCStd_file_path' lock is valid." >&2
        echo $TRUE
        return $SUCCESS
    fi

    # Check if user has lock
    local LOCK_INFO
    LOCK_INFO=$(git lfs locks --path="$lockfile_path") || {
        echo "Error: failed to get lock info for '$lockfile_path'" >&2
        return $FAIL
    }

    local CURRENT_USER
    CURRENT_USER=$(git config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        return $FAIL
    }

    if ! echo "$LOCK_INFO" | grep -q "$CURRENT_USER"; then
        # echo "DEBUG: '$FCStd_file_path' lock is INVALID." >&2
        echo $FALSE
        return $SUCCESS
    else
        # echo "DEBUG: '$FCStd_file_path' lock is valid." >&2
        echo $TRUE
        return $SUCCESS
    fi
}

# DESCRIPTION: Function to get the .FCStd file path from its uncompressed directory's .changefile, relative to repo root
# USAGE: `FCStd_file_path=$(get_FCStd_file_from_changefile "path/to/.changefile") || exit $FAIL`
get_FCStd_file_from_changefile() {
    local changefile_path="$1"

    if [ ! -f "$changefile_path" ]; then
        echo "Error: Lockfile '$changefile_path' does not exist" >&2
        return $FAIL
    fi

    # Read the line with FCStd_file_relpath
    local FCStd_file_relpath_line_in_changefile=$(grep "FCStd_file_relpath=" "$changefile_path")
    if [ -z "$FCStd_file_relpath_line_in_changefile" ]; then
        echo "Error: FCStd_file_relpath not found in '$changefile_path'" >&2
        return $FAIL
    fi

    # Extract the FCStd_file_relpath value
    local FCStd_file_relpath=$(echo "$FCStd_file_relpath_line_in_changefile" | sed "s/FCStd_file_relpath='\([^']*\)'/\1/")

    # Derive the FCStd_file_path from the FCStd_file_relpath
    local FCStd_dir_path=$(dirname "$changefile_path")
    
    local FCStd_file_path=$(realpath "$FCStd_dir_path/$FCStd_file_relpath")

    if [ "$OSTYPE" = "msys" ] || [ "$OSTYPE" = "win32" ]; then
        FCStd_file_path="$(echo "${FCStd_file_path#/}" | sed -E 's#^([a-zA-Z])/#\U\1:/#')" # Note: Convert drive letters IE `/d/` to `D:/` 
    fi

    FCStd_file_path="$(realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$FCStd_file_path")"

    echo "$FCStd_file_path"
    return $SUCCESS
}

# DESCRIPTION: Function to check if a directory has changes between two commits
# USAGE:
    # `DIR_HAS_CHANGES=$(dir_has_changes "path/to/dir") || exit $FAIL`
    # `if [ "$DIR_HAS_CHANGES" = "$TRUE" ]; then echo "dir has changed files"; elif [ $DIR_HAS_CHANGES = $FALSE ]; then echo "No changed files in dir"; fi`
dir_has_changes() {
    local dir_path="$1"
    local old_sha="$2"
    local new_sha="$3"
    
    if git diff-tree --no-commit-id --name-only -r "$old_sha" "$new_sha" | grep -q "^$dir_path/"; then
        # echo "DEBUG: '$dir_path/' HAS changes" >&2
        echo $TRUE
        return $SUCCESS

    else
        # echo "DEBUG: '$dir_path/' has NO changes" >&2
        echo $FALSE
        return $SUCCESS
    fi
}

# ==============================================================================================
#                                   Global Config Variables
# ==============================================================================================
# Only set if the config file exists
if [ -f "$CONFIG_FILE" ]; then
    PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || exit $FAIL
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || exit $FAIL
    REQUIRE_GITCAD_ACTIVATION=$(get_require_gitcad_activation_bool "$CONFIG_FILE") || exit $FAIL

    if [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ]; then
        if [ -z "$GITCAD_ACTIVATED" ]; then
            echo "Error: GitCAD activation is required but not active." >&2
            echo "Please activate GitCAD by running: source FreeCAD_Automation/activate.sh" >&2
            exit $FAIL
        fi
    fi
fi