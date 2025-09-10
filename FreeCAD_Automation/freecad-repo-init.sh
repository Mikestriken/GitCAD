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


# ==============================================================================================
#                                     Verify Dependencies
# ==============================================================================================
echo "=============================================================================================="
echo "                                     Verifying Dependencies"
echo "=============================================================================================="
# Check if inside a Git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not inside a Git repository" >&2
    exit 1
fi

GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

CONFIG_FILE="FreeCAD_Automation/git-freecad-config.json"

# Extract Python path
PYTHON_PATH=$(get_json_value "$CONFIG_FILE" "python")
if [ $? -ne 0 ] || [ -z "$PYTHON_PATH" ]; then
    echo "Error: Could not extract Python path"
    exit 1
fi

echo "Extracted Python path: $PYTHON_PATH"

# Check if Python runs correctly
if "$PYTHON_PATH" --version > /dev/null 2>&1; then
    echo "Python runs correctly"
else
    echo "Error: Python does not run or path is invalid"
    exit 1
fi

# Check if the import works
if "$PYTHON_PATH" -c "from freecad import project_utility as PU; print('Import successful')" > /dev/null 2>&1; then
    echo "FreeCAD Python library import successful"
else
    echo "Error: Import 'from freecad import project_utility as PU' failed"
    exit 1
fi

echo "All checks passed"

# ==============================================================================================
#                                     Initialize Repository
# ==============================================================================================

echo "=============================================================================================="
echo "                                     Setup Git Hooks"
echo "=============================================================================================="

# Setup Git hooks
HOOKS_DIR=".git/hooks"
if [ ! -d "$HOOKS_DIR" ]; then
    echo "Error: .git/hooks directory not found"
    exit 1
fi

if [ ! -d "FreeCAD_Automation/hooks" ]; then
    echo "Error: FreeCAD_Automation/hooks directory not found"
    exit 1
fi

HOOKS=("post-checkout" "pre-commit" "pre-push")
for hook in "${HOOKS[@]}"; do
    if [ -f "$HOOKS_DIR/$hook" ]; then
        echo "Hook $hook already exists in $HOOKS_DIR"
        read -p "  - Do you want to overwrite it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "FreeCAD_Automation/hooks/$hook" "$HOOKS_DIR/$hook"
            chmod +x "$HOOKS_DIR/$hook"
            echo "    Installed $hook hook"
            echo
        else
            echo "    Skipping $hook"
            echo
        fi
    else
        cp "FreeCAD_Automation/hooks/$hook" "$HOOKS_DIR/$hook"
        chmod +x "$HOOKS_DIR/$hook"
        echo "Installed $hook hook"
        echo
    fi
done
echo "=============================================================================================="
echo "                                   Initializing Git-LFS"
echo "=============================================================================================="


echo "=============================================================================================="
echo "                                     Adding Filters"
echo "=============================================================================================="

# Check if filter.FCStd.clean exists
CURRENT_CLEAN=$(git config --get filter.FCStd.clean 2>/dev/null)
if [ -n "$CURRENT_CLEAN" ]; then
    if [ "$CURRENT_CLEAN" = "cat /dev/null" ]; then
        echo "filter.FCStd.clean is already set to the desired value"
        echo
    else
        echo "filter.FCStd.clean already exists:"
        echo "  - Permission to change \`$CURRENT_CLEAN\` --> \`cat /dev/null\`?"
        read -p "    (( This makes git see .FCStd files as being empty ))  (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git config filter.FCStd.clean "cat /dev/null"
            echo "    Updated filter.FCStd.clean"
            echo
        else
            echo "    Skipping update of filter.FCStd.clean"
            echo
        fi
    fi
else
    git config filter.FCStd.clean "cat /dev/null"
    echo "Set filter.FCStd.clean"
    echo
fi

# Check .gitattributes for *.FCStd filter
GITATTRIBUTES=".gitattributes"
if [ ! -f "$GITATTRIBUTES" ]; then
    touch "$GITATTRIBUTES"
    echo "Created .gitattributes"
fi

LINE=$(grep "^\*\.FCStd" "$GITATTRIBUTES" 2>/dev/null)
if [ -n "$LINE" ]; then
    FILTER_VALUE=$(echo "$LINE" | sed 's/.*filter=\([^ ]*\).*/\1/')
    if [ "$FILTER_VALUE" = "FCStd" ]; then
        echo "*.FCStd already has filter=FCStd in .gitattributes"
    else
        if echo "$LINE" | grep -q "filter="; then
            ORIGINAL_FILTER="$FILTER_VALUE"
            echo "*.FCStd has different filter in .gitattributes:"
            read -p "  - Permission to change \`filter=$ORIGINAL_FILTER\` --> \`filter=FCStd\`? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sed -i "s/filter=[^ ]*/filter=FCStd/" "$GITATTRIBUTES"
                echo "    Updated .gitattributes for *.FCStd"
                echo
            else
                echo "    Skipping update of .gitattributes for *.FCStd"
                echo
            fi
        else
            sed -i "s/$/ filter=FCStd/" "$GITATTRIBUTES"
            echo "Added filter=FCStd to existing *.FCStd line"
            echo
        fi
    fi
else
    echo "*.FCStd filter=FCStd" >> "$GITATTRIBUTES"
    echo "Added *.FCStd filter=FCStd to .gitattributes"
    echo
fi
