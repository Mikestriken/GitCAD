#!/bin/bash
# ==============================================================================================
#                     Utils.sh Code (duplicated to limit repeated calls)
# ==============================================================================================
# Logic Constants
SUCCESS=0
FAIL=1
TRUE=0
FALSE=1

# Config file path
CONFIG_FILE="FreeCAD_Automation/config.json"

# DESCRIPTION: Function to extract FreeCAD Python path from config file
    # USAGE: `PYTHON_PATH="$(get_freecad_python_path "$CONFIG_FILE")" || exit $FAIL`
get_freecad_python_path() {
    local file="$1"
    local key="freecad-python-instance-path"
    
    # Find the line containing the key
    local line="$(grep -F -- "\"$key\"" "$file")"
    if [ -z "$line" ]; then
        echo "Error: Key '$key' not found in $file" >&2
        return $FAIL
    fi

    # Extract value after : (stops at , or } for simple cases)
    local value="$(echo "$line" | sed 's/.*"'"$key"'": \([^,}]*\).*/\1/')"
    
    # Strip surrounding quotes if it's a string
    if [[ $value =~ ^\".*\"$ ]]; then
        value="$(echo "$value" | sed 's/^"//' | sed 's/"$//')"
    fi
    
    if [ -z "$value" ]; then
        echo "Error: Python path is empty" >&2
        return $FAIL
    fi
    
    echo "$value"
    return $SUCCESS
}

# Only set if the config file exists
if [ -f "$CONFIG_FILE" ]; then
    PYTHON_PATH="$(get_freecad_python_path "$CONFIG_FILE")" || exit $FAIL
fi

if [ -z "$PYTHON_PATH" ]; then
    echo "Error: Config file missing or invalid; cannot proceed." >&2
    exit $FAIL
fi

# ==============================================================================================
#                                     Export Python Path
# ==============================================================================================
FREECAD_ROOT="$(dirname "$PYTHON_PATH")"
FREECAD_ROOT="$(realpath "$FREECAD_ROOT/..")"

export FREECAD_ROOT="$FREECAD_ROOT"
export PYTHONPATH="$FREECAD_ROOT/lib/python3.11/site-packages:$FREECAD_ROOT/lib:$PYTHONPATH"

# ==============================================================================================
#                                       Execute Python
# ==============================================================================================
exec "$PYTHON_PATH" "$@"