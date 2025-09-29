#!/bin/bash
echo "=============================================================================================="
echo "                                    Create Config File"
echo "=============================================================================================="
DEFAULT_CONFIG='{
    "freecad-python-instance-path": "",
    "require-lock-to-modify-FreeCAD-files": true,
    "include-thumbnails": true,

    "uncompressed-directory-structure": {
        "uncompressed-directory-suffix": "_FCStd",
        "uncompressed-directory-prefix": "FCStd_",
        "subdirectory": {
            "put-uncompressed-directory-in-subdirectory": true,
            "subdirectory-name": "uncompressed"
        }
    },

    "compress-non-human-readable-FreeCAD-files": {
        "enabled": true,
        "files-to-compress": ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"],
        "max-compressed-file-size-gigabyte": 2,
        "compression-level": 9,
        "zip-file-prefix": "compressed_binaries_"
    }
}'

if [ ! -f "FreeCAD_Automation/config.json" ]; then
    echo "$DEFAULT_CONFIG" > "FreeCAD_Automation/config.json"
    echo "Created config file: FreeCAD_Automation/config.json" >&2
    echo >&2
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> USER ACTION REQUESTED <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<" >&2
    echo "1. Please define 'freecad-python-instance-path' key in config.json" >&2
    echo "2. Then Re-Run This Script" >&2
    exit $FAIL
fi

echo "Config already exists."

echo "=============================================================================================="
echo "                             Verify and Retrieve Dependencies"
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
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

# Extract Python path
echo "Extracted Python path: $PYTHON_PATH"

# Check if Python runs correctly
if "$PYTHON_PATH" --version > /dev/null; then
    echo "Python runs correctly"
else
    echo "Error: Python does not run or path is invalid" >&2
    exit $FAIL
fi

# Check if the import works
if "$PYTHON_PATH" -c "from freecad import project_utility as PU; print('Import successful')" > /dev/null; then
    echo "FreeCAD Python library import successful"
else
    echo "Error: Import 'from freecad import project_utility as PU' failed" >&2
    exit $FAIL
fi

echo "All checks passed"
echo "=============================================================================================="
echo "                                    Setup .gitignore"
echo "=============================================================================================="
add_to_gitignore() {
    local ignore_target="$1"
    if [ -f .gitignore ]; then
        if ! grep -q "^$ignore_target$" .gitignore; then
            # Ensure .gitignore ends with a newline before appending
            if [ -s .gitignore ] && [ "$(tail -c1 .gitignore)" != $'\n' ]; then
                echo >> .gitignore
            fi
            echo "$ignore_target" >> .gitignore
            echo "Added $ignore_target to .gitignore"
        else
            echo "$ignore_target already in .gitignore"
        fi
    else
        echo "$ignore_target" > .gitignore
        echo "Created .gitignore and added $ignore_target"
    fi
}

add_to_gitignore "**/__pycache__"
add_to_gitignore "FreeCAD_Automation/config.json"
add_to_gitignore "*.FCBak"

echo "=============================================================================================="
echo "                                     Setup Git Hooks"
echo "=============================================================================================="
# Setup Git hooks
HOOKS_DIR=".git/hooks"
if [ ! -d "$HOOKS_DIR" ]; then
    echo "Error: .git/hooks directory not found" >&2
    exit $FAIL
fi

if [ ! -d "FreeCAD_Automation/hooks" ]; then
    echo "Error: FreeCAD_Automation/hooks directory not found" >&2
    exit $FAIL
fi

HOOKS=("post-checkout" "post-commit" "post-merge" "post-rewrite" "pre-commit" "pre-push")
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

# ! WARNING BELOW IS SOME VIBE SHIT THAT WILL DISTURB YOU.
# I just didn't want to touch regex ;( I'll come back to it later if I care enough but all I know is
# I have tested it against as many edge cases as I could find and it does what I expect it to.
# Minimum Viable Product achieved!

# If anyone comes back to refactor this, the objectives are as follows:
    # 1. Ensure any *.fcstd (case insensitive) in .gitattributes has filter=FCStd
    # 2. Ensure any *.[Ff][Cc][Ss][Tt][Dd] in .gitattributes has filter=FCStd
    # 3. If no *.[Ff][Cc][Ss][Tt][Dd] exists, add one with filter=FCStd.

    # Note for testing: test with multiple attributes
        # IE
            # Before: *.[Ff][Cc][Ss][Tt][Dd] diff=lfs filter=wrong merge=lfs
            # After: *.[Ff][Cc][Ss][Tt][Dd] diff=lfs filter=FCStd merge=lfs
setup_filter_gitattribute() {
    local file_match="$1"
    local filter_target="$2"
    # The first argument is always treated as a regular expression.
    # Use it directly for matching and derive a literal pattern for insertion.
    local regex_pattern="$file_match"
    # Derive a literal pattern by stripping the leading ^ (if present) and unescaping only \* and \.
    local literal_pattern="${file_match#^}"
    literal_pattern="$(printf '%s' "$literal_pattern" | sed -e 's/\\\*/\*/g' -e 's/\\\././g')"
    # Normalize the known FCStd regex to the exact expected literal pattern to avoid any shell/glob side effects
    if [[ "$file_match" == "^\*\.[Ff][Cc][Ss][Tt][Dd]" ]]; then
        literal_pattern="*.[Ff][Cc][Ss][Tt][Dd]"
    fi

    # Process .gitattributes
    if [ -f "$GITATTRIBUTES" ]; then
        # Read the file into an array
        mapfile -t lines < "$GITATTRIBUTES"
        updated=false
        found=false
        shopt -s nocasematch
        for i in "${!lines[@]}"; do
            line="${lines[$i]}"
            # Check if line matches the regex variant OR starts with the canonical literal pattern
            # This ensures we also update lines like "*.[Ff][Cc][Ss][Tt][Dd] filter=F2CStd1"
            if [[ "$line" =~ $regex_pattern || "$line" == "$literal_pattern"* ]]; then
                found=true
                # Check for filter=
                if [[ "$line" =~ filter=([^ ]*) ]]; then
                    filter_value="${BASH_REMATCH[1]}"
                    if [ -z "$filter_value" ]; then
                        # Set to filter_target
                        lines[$i]="${line} filter=$filter_target"
                        updated=true
                    elif [ "$filter_value" != "$filter_target" ]; then
                        echo "$file_match has different filter in .gitattributes:"
                        read -p "  - Permission to change \`filter=$filter_value\` --> \`filter=$filter_target\`? (y/n): " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            # Replace the filter value
                            lines[$i]=$(echo "$line" | sed "s/filter=[^ ]*/filter=$filter_target/")
                            updated=true
                            echo "    Updated .gitattributes for $file_match"
                            echo
                        else
                            echo "    Skipping update of .gitattributes for $file_match"
                            echo
                        fi
                    fi
                else
                    # No filter=, add it
                    lines[$i]="$line filter=$filter_target"
                    updated=true
                fi
            fi
        done
        shopt -u nocasematch
        # Correct any previously mis-generated wildcard-only line (e.g., "* filter=FCStd")
        for i in "${!lines[@]}"; do
            if [[ "${lines[$i]}" == "* filter=$filter_target" ]]; then
                lines[$i]="$literal_pattern filter=$filter_target"
                updated=true
                echo "Corrected misgenerated line: '* filter=$filter_target' -> '$literal_pattern filter=$filter_target'"
                echo
            fi
        done

        # Ensure presence of a canonical entry without creating duplicates:
        # If any line that starts with the literal pattern already contains filter=$filter_target,
        # do not add another minimal canonical line.
        has_canonical=false
        for i in "${!lines[@]}"; do
            if [[ "${lines[$i]}" == "$literal_pattern"* ]] && [[ "${lines[$i]}" == *"filter=$filter_target"* ]]; then
                has_canonical=true
                break
            fi
        done
        if [ "$has_canonical" = false ]; then
            lines+=("$literal_pattern filter=$filter_target")
            updated=true
            echo "Added canonical pattern: $literal_pattern filter=$filter_target to .gitattributes"
            echo
        fi
        if [ "$updated" = true ]; then
            # Write back to file
            printf '%s\n' "${lines[@]}" > "$GITATTRIBUTES"
        fi
    else
        # If no .gitattributes, create it with the literal pattern line
        echo "$literal_pattern filter=$filter_target" > "$GITATTRIBUTES"
        echo "Added $literal_pattern filter=$filter_target to .gitattributes"
        echo
    fi
}

# Add FCStd filters
setup_git_FCStd_filter "clean" "./FreeCAD_Automation/FCStd-filter.sh %f" "This makes git see .FCStd files as being empty and decompresses added .FCStd files"
setup_git_FCStd_filter "smudge" "cat" "Disabled smudge filter" # Required requires both clean and smudge be defined else it will always error out.
setup_git_FCStd_filter "required" "true" "If clean/smudge filter fails, undo add operation."

# Check .gitattributes for *.FCStd filter
GITATTRIBUTES=".gitattributes"
if [ ! -f "$GITATTRIBUTES" ]; then
    touch "$GITATTRIBUTES"
    echo "Created .gitattributes"
fi

# Setup filters for .gitattributes
setup_filter_gitattribute "^\*\.[Ff][Cc][Ss][Tt][Dd]" "FCStd"

echo "=============================================================================================="
echo "                                     Adding git aliases"
echo "=============================================================================================="
setup_git_alias() {
    local alias="$1"
    local desired_value="$2"
    local purpose="$3"

    CURRENT_VALUE=$(git config --get "alias.$alias" 2>/dev/null)

    if [ -n "$CURRENT_VALUE" ]; then
        if [ "$CURRENT_VALUE" = "$desired_value" ]; then
            echo "alias.$alias is already set to the desired value"
            echo
        else
            echo "alias.$alias already exists:"
            echo "  - Permission to change \`$CURRENT_VALUE\` --> \`$desired_value\`?"
            read -p "    (( $purpose ))  (y/n): " -n 1 -r
            
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git config "alias.$alias" "$desired_value"
                echo "    Updated alias.$alias"
                echo
            else
                echo "    Skipping update of alias.$alias"
                echo
            fi
        fi
    else
        git config "alias.$alias" "$desired_value"
        echo "Set alias.$alias"
        echo
    fi
}

setup_git_alias "stat" "!STATUS_CALL=1 git status" "Stops clean filter from running on \`git status\`"
setup_git_alias "clearFCStdMod" "!RESET_MOD=1 git add" "Forcefully adds files (bypass clean filter valid lock checks)"
setup_git_alias "coFCStdFiles" "!sh FreeCAD_Automation/coFCStdFiles.sh \"\${GIT_PREFIX}\"" "Adds \`git coFCStdFiles\` as alias to run coFCStdFiles.sh"
setup_git_alias "lock" "!sh FreeCAD_Automation/lock.sh \"\${GIT_PREFIX}\"" "Adds \`git lock\` as alias to run lock.sh"
setup_git_alias "unlock" "!sh FreeCAD_Automation/unlock.sh \"\${GIT_PREFIX}\"" "Adds \`git unlock\` as alias to run unlock.sh"
setup_git_alias "locks" "lfs locks" "1 to 1 alias for \`git lfs locks\`"
setup_git_alias "ftool" "!sh FreeCAD_Automation/run_FCStdFileTool.sh \"\${GIT_PREFIX}\"" "Adds \`git ftool\` as alias to run FCStdFileTool.py"
setup_git_alias "fimport" "!sh FreeCAD_Automation/run_FCStdFileTool.sh \"\${GIT_PREFIX}\" --CONFIG-FILE --import" "Adds \`git fimport\` as alias to run FCStdFileTool.py with preset import args"
setup_git_alias "fexport" "!sh FreeCAD_Automation/run_FCStdFileTool.sh \"\${GIT_PREFIX}\" --CONFIG-FILE --export" "Adds \`git fexport\` as alias to run FCStdFileTool.py with preset export args"
setup_git_alias "FCStdStash" "!sh FreeCAD_Automation/FCStdStash.sh" "Adds \`git FCStdStash\` as alias to run FCStdStash.sh"
setup_git_alias "freset" "!sh FreeCAD_Automation/FCStdReset.sh" "Adds \`git freset\` as alias to run FCStdReset.sh"

exit $SUCCESS