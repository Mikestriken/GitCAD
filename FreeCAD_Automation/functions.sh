#!/bin/bash
# ==============================================================================================
#                                           Functions
# ==============================================================================================

# DESCRIPTION: Function to extract FreeCAD Python path from config file
    # USAGE: `PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || exit 1`
get_freecad_python_path() {
    local file=$1
    local key="freecad-python-instance-path"
    # Find the line containing the key
    local line=$(grep "\"$key\"" "$file")
    if [ -z "$line" ]; then
        echo "Error: Key '$key' not found in $file" >&2
        return 1
    fi
    # Extract value after : (stops at , or } for simple cases)
    local value=$(echo "$line" | sed 's/.*"'"$key"'": \([^,}]*\).*/\1/')
    # Strip surrounding quotes if it's a string
    if [[ $value =~ ^\".*\"$ ]]; then
        value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    fi
    if [ -z "$value" ]; then
        echo "Error: Python path is empty" >&2
        return 1
    fi
    echo "$value"
}

# DESCRIPTION: Function to extract require-lock-to-modify-FreeCAD-files boolean from config file
# USAGE: 
    # `REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || exit 1`
    # `if [ $REQUIRE_LOCKS == 1 ]; then echo "Locks required"; elif [ $REQUIRE_LOCKS == 0 ]; then echo "Locks not required"; fi`
get_require_locks_bool() {
    local file=$1
    local key="require-lock-to-modify-FreeCAD-files"
    # Find the line containing the key
    local line=$(grep "\"$key\"" "$file")
    if [ -z "$line" ]; then
        echo "Error: Key '$key' not found in $file" >&2
        return 1
    fi
    # Extract value after : (stops at , or } for simple cases)
    local value=$(echo "$line" | sed 's/.*"'"$key"'": \([^,}]*\).*/\1/')
    # Strip surrounding quotes if it's a string (though booleans shouldn't have quotes)
    if [[ $value =~ ^\".*\"$ ]]; then
        value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    fi
    if [ -z "$value" ]; then
        echo "Error: Require locks value is empty" >&2
        return 1
    fi
    # Check if value matches JSON boolean syntax
    if [ "$value" = "true" ]; then
        echo 1
    elif [ "$value" = "false" ]; then
        echo 0
    else
        echo "Error: Value '$value' does not match JSON boolean syntax 'true' or 'false'" >&2
        return 1
    fi
}

# DESCRIPTION: Function to make a file readonly on both Linux and Windows (via MSYS/Git Bash)
# USAGE: `make_readonly "path/to/file.ext"`
make_readonly() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "Error: File '$file' does not exist"
        return 1
    fi

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        chmod 444 "$file"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        attrib +r "$file"
    else
        echo "Error: Unsupported operating system: $OSTYPE"
        return 1
    fi
}

# DESCRIPTION: Function to check if FCStd file has valid lock. Returns 1 if valid (no lock required or lock held), 0 if invalid (lock required but not held)
# USAGE: 
    # `FILE_HAS_VALID_LOCK=$(FCStd_file_has_valid_lock "path/to/file.FCStd") || exit 1`
    # `if [ $FILE_HAS_VALID_LOCK == 1 ]; then echo "File has valid lock"; elif [ $FILE_HAS_VALID_LOCK == 0 ]; then echo "File has invalid lock"; fi`
FCStd_file_has_valid_lock() {
    local FCStd_file_path="$1"
    local CONFIG_FILE="FreeCAD_Automation/git-freecad-config.json"
    local FCStdFileTool="FreeCAD_Automation/FCStdFileTool.py"

    # Get required variables
    local PYTHON_PATH
    PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || return 1

    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || return 1

    # If locks not required, return valid
    if [ "$REQUIRE_LOCKS" == 0 ]; then
        echo 1
    fi

    # File not tracked by git (new file), no lock needed (valid lock)
    if ! git ls-files --error-unmatch "$FCStd_file_path" > /dev/null 2>&1; then
        echo 1
    fi

    # File is tracked, get the .lockfile path
    local lockfile_path
    lockfile_path=$("$PYTHON_PATH" "$FCStdFileTool" --CONFIG-FILE "$CONFIG_FILE" --lockfile "$FCStd_file_path") || {
        echo "Error: Failed to get lockfile path for '$FCStd_file_path'" >&2
        return 1
    }

    # Lockfile not tracked by git (new export), no lock needed (valid lock)
    if ! git ls-files --error-unmatch "$lockfile_path" > /dev/null 2>&1; then
        echo 1
    fi

    # Check if user has lock
    local LOCK_INFO
    LOCK_INFO=$(git lfs locks --path="$lockfile_path")

    local CURRENT_USER
    CURRENT_USER=$(git config --get user.name) || {
        echo "Error: git config user.name not set!" >&2
        return 1
    }

    if ! echo "$LOCK_INFO" | grep -q "$CURRENT_USER"; then
        echo 0
    else
        echo 1
    fi
}