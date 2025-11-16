#!/bin/bash
# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Source this file to activate GitCAD workflow for this terminal session
# Usage: source FreeCAD_Automation/activate.sh

# ==============================================================================================
#                                       Constant Globals
# ==============================================================================================
SUCCESS=0
FAIL=1
TRUE=0
FALSE=1

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Check if inside a Git repository
if ! git rev-parse --git-dir > /dev/null; then
    echo "Error: Not inside a Git repository" >&2
    exit $FAIL
fi

# Store the repository root
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    gitcad_repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    export GITCAD_REPO_ROOT="$(echo "$gitcad_repo_root" | sed -E 's#^([A-Za-z]):/#/\L\1/#')" # Note: Convert drive letters IE `D:/` to `/d/`
else
    export GITCAD_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

if [ -z "$GITCAD_REPO_ROOT" ]; then
    echo "Error: Not in a git repository" >&2
    return $FAIL
fi

# ==============================================================================================
#                                  Prevent Infinite Recursion
# ==============================================================================================
if [ -n "$GITCAD_ACTIVATED" ]; then
    deactivate_GitCAD
fi

# ==============================================================================================
#                                 Register Deactivate Function
# ==============================================================================================
deactivate_GitCAD() {
    # Restore original PATH
    if [ -n "$PATH_ENVIRONMENT_BACKUP" ]; then
        export PATH="$PATH_ENVIRONMENT_BACKUP"
        unset PATH_ENVIRONMENT_BACKUP
    fi
    
    # Unset environment variables
    unset GITCAD_REPO_ROOT
    unset GITCAD_ACTIVATED
    unset REAL_GIT
    unset -f deactivate_GitCAD
    
    # Restore original PS1 prompt
    if [ -n "$PS1_ENVIRONMENT_BACKUP" ]; then
        export PS1="$PS1_ENVIRONMENT_BACKUP"
        unset PS1_ENVIRONMENT_BACKUP
    fi
    
    echo "GitCAD git wrapper deactivated"
}

trap 'deactivate_GitCAD 2>/dev/null' EXIT

# ==============================================================================================
#         Add Wrapper Script to PATH Environment Variable, Ahead Of The Real `git.exe`
# ==============================================================================================
# Note: Used by FreeCAD_Automation/git to call the appropriate git executable.
export REAL_GIT="$(command -v git)"

# Add git wrapper script to PATH Environment variable and create a backup to restore on deactivation
export GITCAD_ACTIVATED="$GITCAD_REPO_ROOT/FreeCAD_Automation"
export PATH_ENVIRONMENT_BACKUP="$PATH"
export PATH="$GITCAD_ACTIVATED:$PATH"

# Add `(GitCAD)` to terminal prompt to note activation.
if [ -n "$PS1" ]; then
    export PS1_ENVIRONMENT_BACKUP="$PS1"
    export PS1="(GitCAD) $PS1"
fi

echo "=============================================================================================="
echo "GitCAD git wrapper activated for this terminal session"
echo "Repository: $GITCAD_REPO_ROOT"
echo 
echo "Use 'deactivate_GitCAD' to exit this environment."
echo "=============================================================================================="