#!/bin/bash
# ==============================================================================================
#                                  Verify and Retrieve Dependencies
# ==============================================================================================
# Ensure working dir is the root of the repo
GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE" --ignore-GitCAD-activation

# Activate/Deactivate GitCAD to match config file setting
if [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ] && { [ -z "$GITCAD_ACTIVATED" ] || [ "$GITCAD_ACTIVATED" = "$FALSE" ]; }; then
    source FreeCAD_Automation/user_scripts/activate

elif [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ] && [ "$GITCAD_ACTIVATED" = "$TRUE" ]; then
    # Implicitly already done by user calling this script
    :

elif [ "$REQUIRE_GITCAD_ACTIVATION" = "$FALSE" ] && { [ -z "$GITCAD_ACTIVATED" ] || [ "$GITCAD_ACTIVATED" = "$FALSE" ]; }; then
    # Do leave it unactivated.
    :

elif [ "$REQUIRE_GITCAD_ACTIVATION" = "$FALSE" ] && [ "$GITCAD_ACTIVATED" = "$TRUE" ]; then
    deactivate_GitCAD() {
        # Remove deactivate_GitCAD EXIT callback
        trap - EXIT

        # Remove the deactivate_GitCAD function definition (this function cannot be called anymore unless redefined)
        if [ ! "$1" = "--keep-function-definition" ]; then
            unset -f deactivate_GitCAD
        fi
        
        # Restore original PATH
        PATH="${PATH#$GIT_WRAPPER_PATH:}"      # Remove $GIT_WRAPPER_PATH (if found) from beginning of $PATH
        PATH="${PATH%:$GIT_WRAPPER_PATH}"      # Remove $GIT_WRAPPER_PATH (if found) from end of $PATH
        PATH="${PATH//:$GIT_WRAPPER_PATH:/:}"  # Remove $GIT_WRAPPER_PATH (if found) from middle of $PATH
        export PATH
        
        # Unset environment variables
        unset GITCAD_REPO_ROOT
        unset REAL_GIT
        unset GITCAD_ACTIVATED
        unset GIT_WRAPPER_PATH
        
        # Remove `(GitCAD)` from PS1 prompt
        if [ -n "$PS1" ]; then
            PS1="${PS1//"$GitCAD_Prompt "/}"
        fi
        
        echo "GitCAD git wrapper deactivated"
    }

    reactivate_GitCAD() {
        trap - EXIT
        source FreeCAD_Automation/user_scripts/activate
    }

    deactivate_GitCAD
    trap 'reactivate_GitCAD' EXIT
fi

# Check for uncommitted work in working directory, exit early if so with error message
if [ -n "$(GIT_COMMAND="status" git status --porcelain)" ]; then
    echo "Error: You have uncommitted changes, commit or remove them to run this test." >&2
    exit $FAIL
fi

# Check for stashed items, warn user they will be dropped and ask if they want to exit early
if [ -n "$(GIT_COMMAND="stash" git stash list)" ]; then
    echo "Warning: There are stashed items in the working directory. They will all be dropped during testing."
    while true; do
        echo "Do you want to exit early to commit your stash? (y/n)"
        read -r response
        case $response in
            [Yy]* ) exit $FAIL;;
            [Nn]* ) break;;
            * ) echo "Please answer y or n.";;
        esac
    done
    GIT_COMMAND="stash" git stash clear
fi

# ==============================================================================================
#                                          Get Binaries
# ==============================================================================================
git checkout test_binaries -- FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd
git fcmod FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd

# ==============================================================================================
#                                          Test Functions
# ==============================================================================================
TEST_BRANCH="active_test"
TEST_FOLDER="active test"
TEST_DIR="FreeCAD_Automation/tests/$TEST_FOLDER"
setup() {
    local test_name="$1"
    echo 
    echo ">>>> Setting Up '$1' <<<<"

    # Checkout -b active_test
    assert_command_succeeds "git checkout -b \"$TEST_BRANCH\" > /dev/null"
    
    # push active_test to remote
    assert_command_succeeds "git push -u origin \"$TEST_BRANCH\" > /dev/null 2>&1"

    assert_command_succeeds "mkdir -p \"$TEST_DIR\""

    # Copies binaries into active_test dir (already done globally, but ensure)
    assert_command_succeeds "cp \"$TEST_DIR/../AssemblyExample.FCStd\" \"$TEST_DIR/../BIMExample.FCStd\" \"$TEST_DIR\""

    echo ">>>> Setup Complete <<<<"
    echo 

    return $SUCCESS
}

tearDown() {
    local test_name="$1"
    echo 
    echo ">>>> Tearing Down '$1' <<<<"

    # remove any locks in test dir
    git lfs locks | grep -- "^$TEST_DIR" | sed -n 's/.*ID:\([0-9]\+\).*/\1/p' | xargs -r -I {} git lfs unlock --id {} --force || true
    
    # Clear working dir changes
    git reset --hard >/dev/null 2>&1

    if ! git_stash | grep -Fq -- "No local changes to save"; then # Stash any leftover changes, if stash successful, drop the stashed changes
        git_stash drop stash@{0}
    fi
    
    git checkout main > /dev/null

    rm -rf "$TEST_DIR"

    git reset --hard >/dev/null 2>&1

    # Delete active_test* branches (local and remote)
    mapfile -t REMOTE_BRANCHES < <(git branch -r 2>/dev/null | sed -e 's/ -> /\n/g' -e 's/^[[:space:]]*//') # Convert line 'origin/HEAD -> origin/main' to 'origin/HEAD' and 'origin/main' lines

    for remote_branch in "${REMOTE_BRANCHES[@]}"; do
        if [[ "$remote_branch" == "origin/$TEST_BRANCH"* ]]; then
            git push origin --delete "${remote_branch#origin/}" >/dev/null 2>&1 || true
            git branch -D "${remote_branch#origin/}" >/dev/null 2>&1 || true
        fi
    done

    # Get list of local active_test* branches and delete them
    LOCAL_ACTIVE_TEST_BRANCHES=$(git branch --list "$TEST_BRANCH*" | sed 's/^* //;s/^  //')
    if [ -n "$LOCAL_ACTIVE_TEST_BRANCHES" ]; then
        echo "Local active_test* branches: '$LOCAL_ACTIVE_TEST_BRANCHES'"
        echo "$LOCAL_ACTIVE_TEST_BRANCHES" | xargs -r git branch -D >/dev/null 2>&1 || true
    fi
    
    echo ">>>> TearDown Complete <<<<"
    echo 
    
    return $SUCCESS
}

# Custom assert functions
assert_dir_exists() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "Assertion failed: Directory '$dir' does not exist" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_readonly() {
    local file="$1"
    if [ -w "$file" ]; then
        echo "Assertion failed: File '$file' is writable" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_writable() {
    local file="$1"
    if [ ! -w "$file" ]; then
        echo "Assertion failed: File '$file' is readonly" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_dir_has_changes() {
    local dir="$1"
    GIT_COMMAND="update-index" git update-index --refresh -q >/dev/null 2>&1
    if ! GIT_COMMAND="diff-index" git diff-index --name-only HEAD | grep -q -- "^$dir/"; then
        echo "Assertion failed: Directory '$dir' has no changes" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_command_fails() {
    local cmd="$1"
    if eval "$cmd"; then
        echo "Assertion failed: Command '$cmd' succeeded but expected to fail" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_command_succeeds() {
    local cmd="$1"
    if ! eval "$cmd"; then
        echo "Assertion failed: Command '$cmd' failed but expected to succeed" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_no_uncommitted_changes() {
    if [ -n "$(GIT_COMMAND="status" git status --porcelain)" ]; then
        rm -rf FreeCAD_Automation/tests/uncompressed/ # Note: Dir spontaneously appears after git checkout test_binaries

        if [ -n "$(GIT_COMMAND="status" git status --porcelain)" ]; then
            echo "Assertion failed: There are uncommitted changes" >&2
            echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo
            tearDown
            exit $FAIL
        fi
    fi
}

assert_file_modified() {
    local file="$1"
    GIT_COMMAND="update-index" git update-index --refresh -q >/dev/null 2>&1
    if ! GIT_COMMAND="diff-index" git diff-index --name-only HEAD | grep -Fxq "$file"; then
        echo "Assertion failed: File '$file' has not been modified" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

await_user_modification() {
    local file="$1"
    while true; do
        if [[ "${OSTYPE^^}" == "LINUX-GNU"* ]]; then
            echo "Please modify '$file' in FreeCAD and save it. Press enter when done."
            xdg-open "$file" > /dev/null &
            disown
            read -r dummy
            if GIT_COMMAND="status" git status --porcelain -z | grep -q -- "^.M $file$"; then
                freecad_pid=$(pgrep -n -i FreeCAD)
                kill "$freecad_pid"
                break
            else
                echo "No changes detected in '$file'. Please make sure to save your modifications."
            fi
        
        elif [[ "${OSTYPE^^}" == "CYGWIN"* || "${OSTYPE^^}" == "MSYS"* || "${OSTYPE^^}" == "MINGW"* ]]; then
            echo "Please modify '$file' in FreeCAD and save it. Press enter when done."
            start "" "$file"
            read -r dummy
            if GIT_COMMAND="status" git status --porcelain -z | grep -q -- "^.M $file$"; then
                taskkill //IM freecad.exe //F
                break
            else
                echo "No changes detected in '$file'. Please make sure to save your modifications."
            fi
        
        else
            echo "Error: Unsupported operating system: $OSTYPE"  >&2
            exit $FAIL
        fi
    done
}

confirm_user() {
    local message="$1"
    local test_name="$2"
    local file="$3"
    while true; do
        if [[ "${OSTYPE^^}" == "LINUX-GNU"* ]]; then
            echo "$message (y/n)"
            xdg-open "$file" > /dev/null &
            disown
            read -r response
            freecad_pid=$(pgrep -n -i FreeCAD)
            kill "$freecad_pid"

            case $response in
                [Yy]* ) return;;
                [Nn]* ) tearDown "$test_name"; exit $FAIL;;
                * ) echo "Please answer y or n.";;
            esac
        
        elif [[ "${OSTYPE^^}" == "CYGWIN"* || "${OSTYPE^^}" == "MSYS"* || "${OSTYPE^^}" == "MINGW"* ]]; then
            echo "$message (y/n)"
            start "" "$file"
            read -r response
            taskkill //IM freecad.exe //F
            case $response in
                [Yy]* ) return;;
                [Nn]* ) tearDown "$test_name"; exit $FAIL;;
                * ) echo "Please answer y or n.";;
            esac
        
        else
            echo "Error: Unsupported operating system: $OSTYPE"  >&2
            exit $FAIL
        fi
    done
}

git_add() {
    if [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ]; then
        git add "$@"
    else
        git fadd "$@"
    fi
}

git_reset() {
    if [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ]; then
        git reset "$@"
    else
        git freset "$@"
    fi
}

git_stash() {
    if [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ]; then
        GIT_COMMAND="stash" git stash "$@"
    else
        git fstash "$@"
    fi
}

git_file_checkout() {
    if [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ]; then
        git checkout "$@"
    else
        git fco "$@"
    fi
}

# ==============================================================================================
#                                          Define Tests
# ==============================================================================================
# Note on formatting:
    # End every command with `; echo` (variable declarations can be excluded from this)
    # Convert comments to echo statements prepended with "TEST: "

test_sandbox() {
    setup "test_sandbox" || exit $FAIL

    echo ">>>>>> TEST: Get REQUIRE_LOCKS configuration" >&2
    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || { tearDown "test_sandbox"; exit $FAIL; }
    echo ">>>>>> TEST: REQUIRE_LOCKS=$REQUIRE_LOCKS" >&2
    echo

    echo ">>>>>> TEST: rm -rf FreeCAD_Automation/tests/uncompressed" >&2
    assert_command_succeeds "rm -rf FreeCAD_Automation/tests/uncompressed/"; echo

    echo ">>>>>> TEST: \`git_add\` \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (files copied during setup)" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\" \"$TEST_DIR/BIMExample.FCStd\"" > /dev/null; echo

    echo ">>>>>> TEST: Assert get_FCStd_dir exists now for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    local Assembly_dir_path
    Assembly_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_sandbox"; exit $FAIL; }
    echo ">>>>>> TEST: Assembly_dir_path=$Assembly_dir_path" >&2
    assert_dir_exists "$Assembly_dir_path"; echo
    local BIM_dir_path
    BIM_dir_path=$(get_FCStd_dir "$TEST_DIR/BIMExample.FCStd") || { tearDown "test_sandbox"; exit $FAIL; }
    echo ">>>>>> TEST: BIM_dir_path=$BIM_dir_path" >&2
    assert_dir_exists "$BIM_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$Assembly_dir_path\" \"$BIM_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial test commit\" > /dev/null"; echo

    echo ">>>>>> TEST: git lock \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_command_succeeds "git lock \"$TEST_DIR/BIMExample.FCStd\""; echo
    
    echo ">>>>>> TEST: git push origin active_test" >&2
    assert_command_succeeds "git push origin active_test"; echo
    
    echo -n ">>>>>> Sandbox Setup, Press ENTER when done testing to exit and reset to main....." >&2; read -r dummy; echo
    
    tearDown "test_sandbox" || exit $FAIL

    return $SUCCESS
}

test_FCStd_clean_filter() {
    # TEST: Initialize
    setup "test_FCStd_clean_filter" || exit $FAIL

    echo ">>>>>> TEST: Get REQUIRE_LOCKS configuration" >&2
    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || { tearDown "test_FCStd_clean_filter"; exit $FAIL; }
    echo ">>>>>> TEST: REQUIRE_LOCKS=$REQUIRE_LOCKS" >&2
    echo

    echo ">>>>>> TEST: remove \`BIMExample.FCStd\` (not used for this test)" >&2
    assert_command_succeeds "rm \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: \`git_add\` \`AssemblyExample.FCStd\` (file copied during setup)" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\" > /dev/null"; echo

    echo ">>>>>> TEST: Assert get_FCStd_dir for \`AssemblyExample.FCStd\` exists now" >&2
    local FCStd_dir_path
    FCStd_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_FCStd_clean_filter"; exit $FAIL; }
    echo ">>>>>> TEST: FCStd_dir_path=$FCStd_dir_path" >&2
    assert_dir_exists "$FCStd_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$FCStd_dir_path\" > /dev/null"; echo

    echo ">>>>>> TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\" > /dev/null"; echo
    assert_no_uncommitted_changes; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is now readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
    else
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    fi
    
    
    # TEST: FCStd Clean filter prevents unlocked add
    echo ">>>>>> TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: attempt to git_add changes (expect error)" >&2
        if [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ]; then
            assert_command_fails "git add \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        else
            assert_command_fails "git fadd \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        fi

        echo ">>>>>> TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    fi

    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo ">>>>>> TEST: git_add \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git_add\`(ed)" >&2
    assert_dir_has_changes "$FCStd_dir_path"; echo

    tearDown "test_FCStd_clean_filter" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_FCStd_clean_filter' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_pre_commit_hook() {
    # TEST: Initialize
    setup "test_pre_commit_hook" || exit $FAIL

    echo ">>>>>> TEST: Get REQUIRE_LOCKS configuration" >&2
    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || { tearDown "test_pre_commit_hook"; exit $FAIL; }
    echo ">>>>>> TEST: REQUIRE_LOCKS=$REQUIRE_LOCKS" >&2
    echo

    echo ">>>>>> TEST: remove \`BIMExample.FCStd\` (not used for this test)" >&2
    assert_command_succeeds "rm \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: \`git_add\` \`AssemblyExample.FCStd\` (file copied during setup)" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert get_FCStd_dir for \`AssemblyExample.FCStd\` exists now" >&2
    local FCStd_dir_path
    FCStd_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_pre_commit_hook"; exit $FAIL; }
    echo ">>>>>> TEST: FCStd_dir_path=$FCStd_dir_path" >&2
    assert_dir_exists "$FCStd_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$FCStd_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is now readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
    else
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    fi
    
    
    # TEST: pre-commit prevents unlocked commit
    echo ">>>>>> TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: BYPASS_LOCK=$TRUE git_add \`AssemblyExample.FCStd\`" >&2
        if [ "$REQUIRE_GITCAD_ACTIVATION" = "$TRUE" ]; then
            assert_command_succeeds "BYPASS_LOCK=$TRUE git add \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        else
            assert_command_succeeds "BYPASS_LOCK=$TRUE git fadd \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        fi
    else
        echo ">>>>>> TEST: git_add \`AssemblyExample.FCStd\` (no lock required)" >&2
        assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    fi

    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git_add\`(ed)" >&2
    assert_dir_has_changes "$FCStd_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$FCStd_dir_path\""; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: git commit -m \"active_test commit that should error, no lock\" (expect error)" >&2
        assert_command_fails "git commit -m \"active_test commit that should error, no lock\""; echo
    else
        echo ">>>>>> TEST: git commit -m \"active_test commit without lock\" (should succeed)" >&2
        assert_command_succeeds "git commit -m \"active_test commit without lock\""; echo
        assert_no_uncommitted_changes; echo
    fi

    tearDown "test_pre_commit_hook" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_pre_commit_hook' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_pre_push_hook() {
    # TEST: Initialize
    setup "test_pre_push_hook" || exit $FAIL

    echo ">>>>>> TEST: Get REQUIRE_LOCKS configuration" >&2
    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || { tearDown "test_pre_push_hook"; exit $FAIL; }
    echo ">>>>>> TEST: REQUIRE_LOCKS=$REQUIRE_LOCKS" >&2
    echo

    echo ">>>>>> TEST: \`git_add\` \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (files copied during setup)" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\" \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert get_FCStd_dir exists now for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    local Assembly_dir_path
    Assembly_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_pre_push_hook"; exit $FAIL; }
    echo ">>>>>> TEST: Assembly_dir_path=$Assembly_dir_path" >&2
    assert_dir_exists "$Assembly_dir_path"; echo
    local BIM_dir_path
    BIM_dir_path=$(get_FCStd_dir "$TEST_DIR/BIMExample.FCStd") || { tearDown "test_pre_push_hook"; exit $FAIL; }
    echo ">>>>>> TEST: BIM_dir_path=$BIM_dir_path" >&2
    assert_dir_exists "$BIM_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$Assembly_dir_path\" \"$BIM_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` are now readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
        assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo

        echo ">>>>>> TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    else
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` are NOT readonly" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
        assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    fi

    
    # TEST 1: pre-push checks multiple commits being pushed and ensures user has lock for modifications in all commits
    for i in 1 2; do
        echo ">>>>>> TEST: 2x Request user modify \`AssemblyExample.FCStd\` ($i)" >&2
        assert_no_uncommitted_changes; echo
        await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

        echo ">>>>>> TEST: 2x git_add \`AssemblyExample.FCStd\` ($i)" >&2
        assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\""; echo

        echo ">>>>>> TEST: 2x Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git_add\`(ed) ($i)" >&2
        assert_dir_has_changes "$Assembly_dir_path"; echo

        echo ">>>>>> TEST: 2x git_add get_FCStd_dir for \`AssemblyExample.FCStd\` ($i)" >&2
        assert_command_succeeds "git_add \"$Assembly_dir_path\""; echo

        echo ">>>>>> TEST: 2x git commit -m \"active_test commit $i\" ($i)" >&2
        assert_command_succeeds "git commit -m \"active_test commit $i\""; echo
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: 2x assert \`AssemblyExample.FCStd\` is NOT readonly ($i)" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    done

    
    # TEST 2: git unlock requires --force to unlock unpushed changes (checks all unpushed commits)
        # Note: TEST 1 still in progress
    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: git unlock \`AssemblyExample.FCStd\` (git alias) -- should fail because changes haven't been pushed" >&2
        assert_command_fails "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

        echo ">>>>>> TEST: git unlock --force \`AssemblyExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git unlock --force \"$TEST_DIR/AssemblyExample.FCStd\""; echo

        echo ">>>>>> TEST: assert \`AssemblyExample.FCStd\` is now readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

        echo ">>>>>> TEST: git lock \`BIMExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/BIMExample.FCStd\""; echo
    fi

    echo ">>>>>> TEST: assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo

    echo ">>>>>> TEST: Request user modify \`BIMExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/BIMExample.FCStd"; echo

    echo ">>>>>> TEST: git_add \`BIMExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert \`BIMExample.FCStd\` dir has changes that can be \`git_add\`(ed)" >&2
    assert_dir_has_changes "$BIM_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for \`BIMExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$BIM_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"active_test commit 3\"" >&2
    assert_command_succeeds "git commit -m \"active_test commit 3\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: git push origin active_test -- should fail because need to lock changes to AssemblyExample.FCStd" >&2
        assert_command_fails "git push origin active_test"; echo

        echo ">>>>>> TEST: git lock \`AssemblyExample.FCStd\` again (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    fi

    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo ">>>>>> TEST: git push origin active_test" >&2
    assert_command_succeeds "git push origin active_test"; echo
    assert_no_uncommitted_changes; echo

    tearDown "test_pre_push_hook" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_pre_push_hook' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_post_checkout_hook() {
    # TEST: Initialize
    setup "test_post_checkout_hook" || exit $FAIL

    echo ">>>>>> TEST: Get REQUIRE_LOCKS configuration" >&2
    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || { tearDown "test_post_checkout_hook"; exit $FAIL; }
    echo ">>>>>> TEST: REQUIRE_LOCKS=$REQUIRE_LOCKS" >&2
    echo

    echo ">>>>>> TEST: \`git_add\` \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (files copied during setup)" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\" \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert get_FCStd_dir exists now for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    local Assembly_dir_path
    Assembly_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_post_checkout_hook"; exit $FAIL; }
    echo ">>>>>> TEST: Assembly_dir_path=$Assembly_dir_path" >&2
    assert_dir_exists "$Assembly_dir_path"; echo
    local BIM_dir_path
    BIM_dir_path=$(get_FCStd_dir "$TEST_DIR/BIMExample.FCStd") || { tearDown "test_post_checkout_hook"; exit $FAIL; }
    echo ">>>>>> TEST: BIM_dir_path=$BIM_dir_path" >&2
    assert_dir_exists "$BIM_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$Assembly_dir_path\" \"$BIM_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` are now readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
        assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo
    else
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` are NOT readonly" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
        assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    fi

    
    # TEST: post-checkout hook synchronizes (imports) FCStd files during a branch checkout
    echo ">>>>>> TEST: git checkout -b active_test_branch1" >&2
    assert_command_succeeds "git checkout -b active_test_branch1"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    fi

    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo ">>>>>> TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo ">>>>>> TEST: git_add \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git_add\`(ed)" >&2
    assert_dir_has_changes "$Assembly_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$Assembly_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"active_test_branch1 commit 1\"" >&2
    assert_command_succeeds "git commit -m \"active_test_branch1 commit 1\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: git unlock \`AssemblyExample.FCStd\` (git alias) -- should fail because changes haven't been pushed" >&2
        assert_command_fails "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    fi

    echo ">>>>>> TEST: git checkout active_test" >&2
    assert_command_succeeds "git checkout active_test"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: assert \`BIMExample.FCStd\` is readonly" >&2
        assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo
    else
        echo ">>>>>> TEST: assert \`BIMExample.FCStd\` is NOT readonly" >&2
        assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    fi

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    
    # TEST: git fco / post-checkout hook synchronizes (imports) FCStd files during a file checkout (files specified with wildcards)
    echo ">>>>>> TEST: git_file_checkout active_test_branch1 -- \`$TEST_DIR/*.FCStd\` (wildcard)" >&2
    assert_command_succeeds "git_file_checkout active_test_branch1 -- \"$TEST_DIR/*.FCStd\""; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back (wildcard test)" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo ">>>>>> TEST: assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: assert \`BIMExample.FCStd\` is readonly" >&2
        assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo
    else
        echo ">>>>>> TEST: assert \`BIMExample.FCStd\` is NOT readonly" >&2
        assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    fi

    echo ">>>>>> TEST: git_file_checkout HEAD -- \"$TEST_DIR/*.FCStd\"" >&2
    assert_command_succeeds "git_file_checkout HEAD -- \"$TEST_DIR/*.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    
    # TEST: git fco / post-checkout hook synchronizes (imports) FCStd files during a file checkout (file specified explicitly)
    echo ">>>>>> TEST: git_file_checkout active_test_branch1 -- \`AssemblyExample.FCStd\` (single file with --)" >&2
    assert_command_succeeds "git_file_checkout active_test_branch1 -- \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo ">>>>>> TEST: git_file_checkout active_test -- \"$TEST_DIR/AssemblyExample.FCStd\"" >&2
    assert_command_succeeds "git_file_checkout active_test -- \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    
    # TEST: git fco / post-checkout hook synchronizes (imports) FCStd files during a file checkout (file specified without `--`)
    echo ">>>>>> TEST: git_file_checkout active_test_branch1 \`AssemblyExample.FCStd\` (single file without --)" >&2
    assert_command_succeeds "git_file_checkout active_test_branch1 \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo ">>>>>> TEST: git_file_checkout active_test \"$TEST_DIR/AssemblyExample.FCStd\"" >&2
    assert_command_succeeds "git_file_checkout active_test \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    
    # TEST: git fco / post-checkout hook synchronizes (imports) FCStd files during a file checkout (multiple files specified explicitly)
    echo ">>>>>> TEST: git_file_checkout active_test_branch1 -- \`AssemblyExample.FCStd\` \`BIMExample.FCStd\` (multiple files)" >&2
    assert_command_succeeds "git_file_checkout active_test_branch1 -- \"$TEST_DIR/AssemblyExample.FCStd\" \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo ">>>>>> TEST: Ask user to confirm \`BIMExample.FCStd\` is unchanged (no changes in branch)" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' is unchanged (no changes were made to it in active_test_branch1)." "test_post_checkout_hook" "$TEST_DIR/BIMExample.FCStd"

    echo ">>>>>> TEST: git_file_checkout active_test -- \"$TEST_DIR/AssemblyExample.FCStd\" \"$TEST_DIR/BIMExample.FCStd\"" >&2
    assert_command_succeeds "git_file_checkout active_test -- \"$TEST_DIR/AssemblyExample.FCStd\" \"$TEST_DIR/BIMExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    
    # TEST: git fco / post-checkout hook synchronizes (imports) FCStd files during a file checkout (directory specified explicitly)
    echo ">>>>>> TEST: git_file_checkout active_test_branch1 -- \`$TEST_DIR/\` (directory)" >&2
    assert_command_succeeds "git_file_checkout active_test_branch1 -- \"$TEST_DIR/\""; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back from directory checkout" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back from directory checkout." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo ">>>>>> TEST: git_file_checkout active_test -- \"$TEST_DIR/\"" >&2
    assert_command_succeeds "git_file_checkout active_test -- \"$TEST_DIR/\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    
    # TEST: git fco / post-checkout hook synchronizes (imports) FCStd files during a file checkout (files and directory specified explicitly)
    echo ">>>>>> TEST: git_file_checkout active_test_branch1 -- \`$TEST_DIR/\` \`AssemblyExample.FCStd\` (mixed)" >&2
    assert_command_succeeds "git_file_checkout active_test_branch1 -- \"$TEST_DIR/\" \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back from mixed checkout" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back from mixed checkout." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo ">>>>>> TEST: git_file_checkout active_test -- \"$TEST_DIR/\"" >&2
    assert_command_succeeds "git_file_checkout active_test -- \"$TEST_DIR/\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    
    # TEST: git fco / post-checkout hook synchronizes (imports) FCStd files while cd'd into subdir
    local Original_Working_Directory=$(pwd)
    echo ">>>>>> TEST: Changing Directory to '$TEST_DIR'" >&2
    assert_command_succeeds "cd \"$TEST_DIR\""

    echo ">>>>>> TEST: git_file_checkout active_test_branch1 -- \`AssemblyExample.FCStd\` \`BIMExample.FCStd\` \`.\` \`*\` \`../TEST_BRANCH\` (multiple files)" >&2
    assert_command_succeeds "git_file_checkout active_test_branch1 -- \"AssemblyExample.FCStd\" \"BIMExample.FCStd\" \".\" \"*\" \"../$TEST_FOLDER\""; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back from subdir cd'ed checkout" >&2
    echo ">>>>>> TEST NOTE: If debug prints are active, check that all arg patterns correctly matched files (there is overlap in files matched by patterns)." >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back from subdir cd'ed checkout." "test_post_checkout_hook" "./AssemblyExample.FCStd"

    echo ">>>>>> TEST: Reverting directory change to '$Original_Working_Directory'"
    assert_command_succeeds "cd \"$Original_Working_Directory\""

    
    # TEST: Assert file read / write perms are set correctly
    echo ">>>>>> TEST: assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: assert \`BIMExample.FCStd\` is readonly" >&2
        assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo
    else
        echo ">>>>>> TEST: assert \`BIMExample.FCStd\` is NOT readonly" >&2
        assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    fi

    tearDown "test_post_checkout_hook" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_post_checkout_hook' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_stashing() {
    # TEST: Initialize
    setup "test_stashing" || exit $FAIL

    echo ">>>>>> TEST: Get REQUIRE_LOCKS configuration" >&2
    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || { tearDown "test_stashing"; exit $FAIL; }
    echo ">>>>>> TEST: REQUIRE_LOCKS=$REQUIRE_LOCKS" >&2
    echo

    echo ">>>>>> TEST: remove \`BIMExample.FCStd\` (not used for this test)" >&2
    assert_command_succeeds "rm \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: \`git_add\` \`AssemblyExample.FCStd\` (file copied during setup)" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert get_FCStd_dir for \`AssemblyExample.FCStd\` exists now" >&2
    local FCStd_dir_path
    FCStd_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_stashing"; exit $FAIL; }
    echo ">>>>>> TEST: FCStd_dir_path=$FCStd_dir_path" >&2
    assert_dir_exists "$FCStd_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$FCStd_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is now readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

        echo ">>>>>> TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    fi

    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo


    # TEST: Stashing all changes in working directory
    echo ">>>>>> TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo ">>>>>> TEST: git_stash -- \"$TEST_DIR/AssemblyExample.FCStd\", should error as .FCStd files cannot be stashed" >&2
    assert_command_fails "git_stash -- \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: git_add \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert changes to get_FCStd_dir for \`AssemblyExample.FCStd\` exists now" >&2
    assert_dir_has_changes "$FCStd_dir_path"; echo

    echo ">>>>>> TEST: git_stash the changes" >&2
    assert_command_succeeds "git_stash"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_stashing" "$TEST_DIR/AssemblyExample.FCStd"


    # TEST: Popping the stashed changes and Stashing the specified .FCStd file (should redirect to the FCStd_dir_path)
    echo ">>>>>> TEST: git_stash pop" >&2
    assert_no_uncommitted_changes; echo
    assert_command_succeeds "git_stash pop"; echo
    
    if GIT_COMMAND="status" git status | grep -Fq -- "$TEST_DIR/AssemblyExample.FCStd"; then
        echo "Assertion failed: git stash did not clear the modification for the popped .FCStd file." >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....." >&2; read -r dummy; echo

        tearDown
        exit $FAIL
    fi

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_stashing" "$TEST_DIR/AssemblyExample.FCStd"

    echo ">>>>>> TEST: git_stash -- \"$TEST_DIR/AssemblyExample.FCStd\"" >&2
    assert_command_succeeds "git_stash -- \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_stashing" "$TEST_DIR/AssemblyExample.FCStd"
    
    
    # TEST: git checkout stash file
    echo ">>>>>> TEST: git checkout stash@{0} -- \"$FCStd_dir_path/.changefile\"" >&2
    assert_command_succeeds "git checkout stash@{0} -- \"$FCStd_dir_path/.changefile\""; echo
    assert_file_modified "$FCStd_dir_path/.changefile"; echo
    
    
    # TEST: Remove checked out file
    echo ">>>>>> TEST: git reset --hard" >&2
    assert_command_succeeds "git reset --hard"; echo
    assert_no_uncommitted_changes; echo
    
    
    # TEST: git unlock checks for stashed changes not yet committed (fails if so)
    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: git unlock \`AssemblyExample.FCStd\` (git alias) -- should fail because changes haven't been pushed" >&2
        assert_command_fails "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: git push origin active_test" >&2
        assert_command_succeeds "git push origin active_test"; echo # Note: Only `git unlock` checks for stashed changes.
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: git unlock \`AssemblyExample.FCStd\` (git alias) -- should fail because STASHED changes haven't been pushed" >&2
        assert_command_fails "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: git unlock --force \`AssemblyExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git unlock --force \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

        
        # TEST: Unstashing changes without a lock for changes fails
        echo ">>>>>> TEST: git_stash pop, should fail need lock to modify AssemblyExample.FCStd" >&2
        assert_no_uncommitted_changes; echo
        assert_command_fails "git_stash pop"; echo
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    else
        echo ">>>>>> TEST: git push origin active_test" >&2
        assert_command_succeeds "git push origin active_test"; echo # Note: Only `git unlock` checks for stashed changes.
        assert_no_uncommitted_changes; echo
    fi

    
    # TEST: Unstashing changes with a lock succeeds
    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo ">>>>>> TEST: git_stash pop" >&2
    assert_no_uncommitted_changes; echo
    assert_command_succeeds "git_stash pop"; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_stashing" "$TEST_DIR/AssemblyExample.FCStd"

    tearDown "test_stashing" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_stashing' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_post_merge_hook() {
    # TEST: Initialize
    setup "test_post_merge_hook" || exit $FAIL

    echo ">>>>>> TEST: Get REQUIRE_LOCKS configuration" >&2
    local REQUIRE_LOCKS
    REQUIRE_LOCKS=$(get_require_locks_bool "$CONFIG_FILE") || { tearDown "test_post_merge_hook"; exit $FAIL; }
    echo ">>>>>> TEST: REQUIRE_LOCKS=$REQUIRE_LOCKS" >&2
    echo

    echo ">>>>>> TEST: \`git_add\` \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (files copied during setup)" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\" \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert get_FCStd_dir exists now for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    local Assembly_dir_path
    Assembly_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_post_merge_hook"; exit $FAIL; }
    echo ">>>>>> TEST: Assembly_dir_path=$Assembly_dir_path" >&2
    assert_dir_exists "$Assembly_dir_path"; echo
    local BIM_dir_path
    BIM_dir_path=$(get_FCStd_dir "$TEST_DIR/BIMExample.FCStd") || { tearDown "test_post_merge_hook"; exit $FAIL; }
    echo ">>>>>> TEST: BIM_dir_path=$BIM_dir_path" >&2
    assert_dir_exists "$BIM_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$Assembly_dir_path\" \"$BIM_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` are now readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
        assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: git lock \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        assert_command_succeeds "git lock \"$TEST_DIR/BIMExample.FCStd\""; echo
    fi

    
    # TEST: Simulate teamwork on remote repository
    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: git push origin active_test" >&2
    assert_command_succeeds "git push origin active_test"; echo
    assert_no_uncommitted_changes; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: git unlock \`BIMExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git unlock \"$TEST_DIR/BIMExample.FCStd\""; echo

        echo ">>>>>> TEST: Assert \`BIMExample.FCStd\` is now readonly" >&2
        assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo
    fi

    echo ">>>>>> TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo ">>>>>> TEST: git_add \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git_add\`(ed)" >&2
    assert_dir_has_changes "$Assembly_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$Assembly_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"active_test commit 1\"" >&2
    assert_command_succeeds "git commit -m \"active_test commit 1\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: git push origin active_test" >&2
    assert_command_succeeds "git push origin active_test"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: git_reset --hard active_test^" >&2
    assert_command_succeeds "git_reset --hard active_test^"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: git update-ref refs/remotes/origin/active_test active_test" >&2
    assert_command_succeeds "git update-ref refs/remotes/origin/active_test active_test"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_merge_hook" "$TEST_DIR/AssemblyExample.FCStd"
    assert_no_uncommitted_changes; echo


    # TEST: Pull --rebase remote changes and merge with local work to a different `.FCStd` file
    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: git unlock \`AssemblyExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is now readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
        assert_no_uncommitted_changes; echo

        echo ">>>>>> TEST: git lock \`BIMExample.FCStd\` (git alias)" >&2
        assert_command_succeeds "git lock \"$TEST_DIR/BIMExample.FCStd\""; echo
        assert_no_uncommitted_changes; echo
    fi

    echo ">>>>>> TEST: Assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Request user modify \`BIMExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/BIMExample.FCStd"; echo

    echo ">>>>>> TEST: git_add \`BIMExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo ">>>>>> TEST: Assert \`BIMExample.FCStd\` dir has changes that can be \`git_add\`(ed)" >&2
    assert_dir_has_changes "$BIM_dir_path"; echo

    echo ">>>>>> TEST: git_add get_FCStd_dir for \`BIMExample.FCStd\`" >&2
    assert_command_succeeds "git_add \"$BIM_dir_path\""; echo

    echo ">>>>>> TEST: git commit -m \"active_test commit 1b\"" >&2
    assert_command_succeeds "git commit -m \"active_test commit 1b\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: git pull --rebase origin active_test" >&2
    assert_command_succeeds "git pull --rebase origin active_test"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
    else
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    fi

    echo ">>>>>> TEST: Ask user to confirm \`BIMExample.FCStd\` changes are still present" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' changes are still present." "test_post_merge_hook" "$TEST_DIR/BIMExample.FCStd"

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_post_merge_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo ">>>>>> TEST: git_reset --soft active_test^" >&2
    assert_command_succeeds "git_reset --soft active_test^"; echo

    echo ">>>>>> TEST: git_stash" >&2
    assert_command_succeeds "git_stash"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: git_reset --hard active_test^" >&2
    assert_command_succeeds "git_reset --hard active_test^"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`BIMExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' changes have been reverted." "test_post_merge_hook" "$TEST_DIR/BIMExample.FCStd"

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_merge_hook" "$TEST_DIR/AssemblyExample.FCStd"


    # TEST: Pull --no-rebase (merge) remote changes and merge with local work to a different `.FCStd` file
    echo ">>>>>> TEST: git update-ref refs/remotes/origin/active_test active_test" >&2
    assert_command_succeeds "git update-ref refs/remotes/origin/active_test active_test"; echo

    echo ">>>>>> TEST: git_stash pop" >&2
    assert_no_uncommitted_changes; echo
    assert_command_succeeds "git_stash pop"; echo

    echo ">>>>>> TEST: git_add \`$TEST_DIR\`" >&2
    assert_command_succeeds "git_add \"$TEST_DIR\""; echo

    echo ">>>>>> TEST: git commit -m \"active_test commit 1b\"" >&2
    assert_command_succeeds "git commit -m \"active_test commit 1b\""; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Ask user to confirm \`BIMExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' changes are back." "test_post_merge_hook" "$TEST_DIR/BIMExample.FCStd"

    echo ">>>>>> TEST: git pull --no-rebase origin active_test" >&2
    assert_command_succeeds "git pull --no-rebase origin active_test"; echo
    assert_no_uncommitted_changes; echo

    echo ">>>>>> TEST: Assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo

    if [ "$REQUIRE_LOCKS" = "$TRUE" ]; then
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is readonly" >&2
        assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
    else
        echo ">>>>>> TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    fi

    echo ">>>>>> TEST: Ask user to confirm \`BIMExample.FCStd\` changes are still present" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' changes are still present." "test_post_merge_hook" "$TEST_DIR/BIMExample.FCStd"

    echo ">>>>>> TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_post_merge_hook" "$TEST_DIR/AssemblyExample.FCStd"

    tearDown "test_post_merge_hook" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_post_merge_hook' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

# ==============================================================================================
#                                          Run Tests
# ==============================================================================================
# Note: Expect user to press Ctrl + C to opt out of test

if [ "$1" = "--sandbox" ]; then
    echo -n ">>>> START SANDBOX TEST? <<<<" >&2; read -r dummy; echo
    
    test_sandbox

    echo -n ">>>> END OF TESTING <<<<" >&2; read -r dummy; echo

    rm -rf FreeCAD_Automation/tests/uncompressed/ # Note: Dir spontaneously appears after git checkout test_binaries
    exit $SUCCESS

elif [ -z "$1" ]; then
    echo -n ">>>> START STANDARD TEST? <<<<" >&2; read -r dummy; echo
    
    test_FCStd_clean_filter
    test_pre_commit_hook
    test_pre_push_hook
    test_post_checkout_hook
    test_stashing
    test_post_merge_hook

    echo -n ">>>> END OF TESTING <<<<" >&2; read -r dummy; echo

    rm -rf FreeCAD_Automation/tests/uncompressed/ # Note: Dir spontaneously appears after git checkout test_binaries
    exit $SUCCESS
fi
exit $FAIL