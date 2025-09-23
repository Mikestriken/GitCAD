#!/bin/bash
# ==============================================================================================
#                                       Constant Globals
# ==============================================================================================
SUCCESS=0
FAIL=1
TRUE=0
FALSE=1

CONFIG_FILE="FreeCAD_Automation/config.json"
FCStdFileTool="FreeCAD_Automation/FCStdFileTool.py"

# ==============================================================================================
#                                           Functions
# ==============================================================================================

# DESCRIPTION: Function to extract FreeCAD Python path from config file
    # USAGE: `PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || exit $FAIL`
get_freecad_python_path() {
    local file=$1
    local key="freecad-python-instance-path"
    
    # Find the line containing the key
    local line=$(grep "\"$key\"" "$file")
    if [ -z "$line" ]; then
        echo "Error: Key '$key' not found in $file" >&2
        return $FAIL
    fi

    # Extract value after : (stops at , or } for simple cases)
    local value=$(echo "$line" | sed 's/.*"'"$key"'": \([^,}]*\).*/\1/')
    
    # Strip surrounding quotes if it's a string
    if [[ $value =~ ^\".*\"$ ]]; then
        value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    fi
    
    if [ -z "$value" ]; then
        echo "Error: Python path is empty" >&2
        return $FAIL
    fi
    
    echo "$value"
    return $SUCCESS
}

# DESCRIPTION: Function to extract require-lock-to-modify-FreeCAD-files boolean from config file
# USAGE: 
    # `REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || exit $FAIL`
    # `if [ $REQUIRE_LOCKS == 1 ]; then echo "Locks required"; elif [ $REQUIRE_LOCKS == 0 ]; then echo "Locks not required"; fi`
get_require_locks_bool() {
    local file=$1
    local key="require-lock-to-modify-FreeCAD-files"
    
    # Find the line containing the key
    local line=$(grep "\"$key\"" "$file")
    if [ -z "$line" ]; then
        echo "Error: Key '$key' not found in $file" >&2
        return $FAIL
    fi
    
    # Extract value after : (stops at , or } for simple cases)
    local value=$(echo "$line" | sed 's/.*"'"$key"'": \([^,}]*\).*/\1/')
    
    # Strip surrounding quotes if it's a string (though booleans shouldn't have quotes)
    if [[ $value =~ ^\".*\"$ ]]; then
        value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    fi
    
    if [ -z "$value" ]; then
        echo "Error: Require locks value is empty" >&2
        return $FAIL
    fi
    
    # Check if value matches JSON boolean syntax
    if [ "$value" = "true" ]; then
        # echo "DEBUG: REQUIRE LOCKS = TRUE" >&2
        echo 1
        return $SUCCESS

    elif [ "$value" = "false" ]; then
        # echo "DEBUG: REQUIRE LOCKS = FALSE" >&2
        echo 0
        return $SUCCESS
        
    else
        echo "Error: Value '$value' does not match JSON boolean syntax 'true' or 'false'" >&2
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
    
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
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
    
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        attrib -r "$file"
    
    else
        echo "Error: Unsupported operating system: $OSTYPE"  >&2
        return $FAIL
    fi

    return $SUCCESS
}

# DESCRIPTION: Function to check if FCStd file has valid lock. Returns 1 if valid (no lock required or lock held), 0 if invalid (lock required but not held)
# USAGE: 
    # `FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "path/to/file.FCStd") || exit $FAIL`
    # `if [ $FILE_HAS_VALID_LOCK == 1 ]; then echo "File has valid lock"; elif [ $FILE_HAS_VALID_LOCK == 0 ]; then echo "File has invalid lock"; fi`
FCStd_file_has_valid_lock() {
    local FCStd_file_path="$1"

    # Get required variables
    local PYTHON_PATH
    PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || return $FAIL

    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || return $FAIL

    # If locks not required, return valid
    if [ "$REQUIRE_LOCKS" == 0 ]; then
        # echo "DEBUG: Locks not required, '$FCStd_file_path' lock is valid." >&2
        echo 1
        return $SUCCESS
    fi

    # File not tracked by git (new file), no lock needed (valid lock)
    if ! git ls-files --error-unmatch "$FCStd_file_path" > /dev/null 2>&1; then
        # echo "DEBUG: New .FCStd file, '$FCStd_file_path' lock is valid." >&2
        echo 1
        return $SUCCESS
    fi

    # File is tracked, get the .lockfile path
    local lockfile_path # 
    lockfile_path=$(realpath --relative-to="$(git rev-parse --show-toplevel)" "$("$PYTHON_PATH" "$FCStdFileTool" --CONFIG-FILE --lockfile "$FCStd_file_path")") || {
        echo "Error: Failed to get lockfile path for '$FCStd_file_path'" >&2
        return $FAIL
    }

    # Lockfile not tracked by git (new export), no lock needed (valid lock)
    if ! git ls-files --error-unmatch "$lockfile_path" > /dev/null 2>&1; then
        # echo "DEBUG: New .FCStd file export, '$FCStd_file_path' lock is valid." >&2
        echo 1
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
        # echo "DEBUG: New .FCStd file export, '$FCStd_file_path' lock is INVALID." >&2
        echo 0
        return $SUCCESS
    else
        # echo "DEBUG: New .FCStd file export, '$FCStd_file_path' lock is valid." >&2
        echo 1
        return $SUCCESS
    fi
}

# DESCRIPTION: Function to get the uncompressed directory path for a .FCStd file
# USAGE: `FCStd_dir_path=$(get_FCStd_dir "path/to/file.FCStd") || exit $FAIL`
get_FCStd_dir() {
    local FCStd_file_path="$1"

    # Get Python path
    local PYTHON_PATH
    PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || return $FAIL

    # Get the lockfile path (which gives us the directory structure)
    local lockfile_path
    lockfile_path=$("$PYTHON_PATH" "$FCStdFileTool" --CONFIG-FILE --lockfile "$FCStd_file_path") || {
        echo "Error: Failed to get lockfile path for '$FCStd_file_path'" >&2
        return $FAIL
    }

    # Return the directory path (parent of lockfile)
    realpath --canonicalize-missing --relative-to="$(git rev-parse --show-toplevel)" "$(dirname "$lockfile_path")" || return $FAIL

    return $SUCCESS
}

# DESCRIPTION: Function to check if a directory has changes between two commits
# USAGE:
    # `DIR_HAS_CHANGES=$(dir_has_changes "path/to/dir") || exit $FAIL`
    # `if [ $DIR_HAS_CHANGES == 1 ]; then echo "dir has changed files"; elif [ $DIR_HAS_CHANGES == 0 ]; then echo "No changed files in dir"; fi`
dir_has_changes() {
    local dir_path="$1"
    local old_sha="$2"
    local new_sha="$3"

    if git diff --name-only "$old_sha..$new_sha" | grep -q "^$dir_path/"; then
        # echo "DEBUG: '$$dir_path/' HAS changes" >&2
        echo 1
        return $SUCCESS
    
    else
        # echo "DEBUG: '$$dir_path/' has NO changes" >&2
        echo 0
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
fi