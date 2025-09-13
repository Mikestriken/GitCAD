#!/bin/bash
# ==============================================================================================
#                                           Functions
# ==============================================================================================

# Function to extract JSON value by key (handles strings, numbers, booleans, null; basic arrays/objects as strings)
get_json_value() {
    local file=$1
    local key=$2
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
    echo "$value"
}