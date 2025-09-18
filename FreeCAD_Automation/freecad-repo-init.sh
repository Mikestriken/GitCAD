#!/bin/bash

echo "=============================================================================================="
echo "                                     Verifying Dependencies"
echo "=============================================================================================="
# Check git user.name and user.email set
if ! git config --get user.name > /dev/null || ! git config --get user.email > /dev/null; then
    echo "git config user.name or user.email not set!" >&2
    exit 1
fi

# Check if inside a Git repository and ensure working dir is the root of the repo
if ! git rev-parse --git-dir > /dev/null; then
    echo "Error: Not inside a Git repository" >&2
    exit 1
fi

# Check if git-lfs is installed
if ! command -v git-lfs >/dev/null; then
    echo "Error: git-lfs is not installed" >&2
    exit 1
fi
echo "git-lfs is installed"

GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/functions.sh"
source "$FUNCTIONS_FILE"

CONFIG_FILE="FreeCAD_Automation/git-freecad-config.json"

# Extract Python path
PYTHON_PATH=$(get_json_value "$CONFIG_FILE" "freecad-python-instance-path") || {
    echo "Error: get_json_value failed" >&2
    exit 1
}

if [ -z "$PYTHON_PATH" ]; then
    echo "Error: Python path is empty" >&2
    exit 1
fi

echo "Extracted Python path: $PYTHON_PATH"

# Check if Python runs correctly
if "$PYTHON_PATH" --version > /dev/null; then
    echo "Python runs correctly"
else
    echo "Error: Python does not run or path is invalid" >&2
    exit 1
fi

# Check if the import works
if "$PYTHON_PATH" -c "from freecad import project_utility as PU; print('Import successful')" > /dev/null; then
    echo "FreeCAD Python library import successful"
else
    echo "Error: Import 'from freecad import project_utility as PU' failed" >&2
    exit 1
fi

echo "All checks passed"

echo "=============================================================================================="
echo "                                     Setup Git Hooks"
echo "=============================================================================================="

# Setup Git hooks
HOOKS_DIR=".git/hooks"
if [ ! -d "$HOOKS_DIR" ]; then
    echo "Error: .git/hooks directory not found" >&2
    exit 1
fi

if [ ! -d "FreeCAD_Automation/hooks" ]; then
    echo "Error: FreeCAD_Automation/hooks directory not found" >&2
    exit 1
fi

HOOKS=("post-checkout" "post-commit" "post-merge" "pre-commit" "pre-push")
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

# Configure locksverify for .lockfile
git config lfs.locksverify true
echo "Enabled git lfs locksverify for lockable files."

git lfs track ".lockfile" --lockable

echo "=============================================================================================="
echo "                                     Adding Filters"
echo "=============================================================================================="
setup_git_FCStd_filter() {
    local filter_type="$1"
    local desired_value="$2"
    local purpose="$3"

    CURRENT_VALUE=$(git config --get "filter.FCStd.$filter_type" 2>/dev/null)

    if [ -n "$CURRENT_VALUE" ]; then
        if [ "$CURRENT_VALUE" = "$desired_value" ]; then
            echo "filter.FCStd.$filter_type is already set to the desired value"
            echo
        else
            echo "filter.FCStd.$filter_type already exists:"
            echo "  - Permission to change \`$CURRENT_VALUE\` --> \`$desired_value\`?"
            read -p "    (( $purpose ))  (y/n): " -n 1 -r
            
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git config "filter.FCStd.$filter_type" "$desired_value"
                echo "    Updated filter.FCStd.$filter_type"
                echo
            else
                echo "    Skipping update of filter.FCStd.$filter_type"
                echo
            fi
        fi
    else
        git config "filter.FCStd.$filter_type" "$desired_value"
        echo "Set filter.FCStd.$filter_type"
        echo
    fi
}

# Add FCStd filters
setup_git_FCStd_filter "clean" "./FreeCAD_Automation/FCStd-filter.sh %f" "This makes git see .FCStd files as being empty and decompresses added .FCStd files"
setup_git_FCStd_filter "smudge" "cat" "Prevents checking out .FCStd files from throwing errors"
setup_git_FCStd_filter "required" "true" "If clean/smudge filter fails, error the script out"

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
