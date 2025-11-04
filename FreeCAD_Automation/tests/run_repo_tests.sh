#!/bin/bash
# ==============================================================================================
#                                  Verify and Retrieve Dependencies
# ==============================================================================================
# Ensure working dir is the root of the repo
GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/utils.sh"
source "$FUNCTIONS_FILE"

# Check for uncommitted work in working directory, exit early if so with error message
if [ -n "$(git stat --porcelain)" ]; then
    while ! rm -rf FreeCAD_Automation/tests/uncompressed/; do
        sleep 10
    done # Note: Dir spontaneously appears after git checkout test_binaries

    if [ -n "$(git stat --porcelain)" ]; then
        echo "Error: There are uncommitted changes in the working directory. Please commit or stash them before running tests."
        exit $FAIL
    fi
fi

# Check for stashed items, warn user they will be dropped and ask if they want to exit early
if [ -n "$(git stash list)" ]; then
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
    git stash clear
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
TEST_DIR="FreeCAD_Automation/tests/$TEST_BRANCH"
setup() {
    local test_name="$1"
    echo 
    echo ">>>> Setting Up '$1' <<<<"

    # Checkout -b active_test
    assert_command_succeeds "git checkout -b \"$TEST_BRANCH\" > /dev/null"
    
    # push active_test to remote
    assert_command_succeeds "git push -u origin \"$TEST_BRANCH\" > /dev/null 2>&1"

    assert_command_succeeds "mkdir -p $TEST_DIR"

    # Copies binaries into active_test dir (already done globally, but ensure)
    assert_command_succeeds "cp $TEST_DIR/../AssemblyExample.FCStd $TEST_DIR/../BIMExample.FCStd $TEST_DIR"

    echo ">>>> Setup Complete <<<<"
    echo 

    return $SUCCESS
}

tearDown() {
    local test_name="$1"
    echo 
    echo ">>>> Tearing Down '$1' <<<<"

    # remove any locks in test dir
    git lfs locks | grep "^$TEST_DIR" | awk '{print $3}' | sed 's/ID://' | xargs -r -I {} git lfs unlock --id {} --force || true
    
    # Clear working dir changes
    git reset --hard >/dev/null 2>&1

    if ! git fstash | grep -q "No local changes to save"; then # Stash any leftover changes, if stash successful, drop the stashed changes
        git fstash drop stash@{0}
    fi
    
    git checkout main > /dev/null

    rm -rf $TEST_DIR

    git reset --hard >/dev/null 2>&1

    # Delete active_test* branches (local and remote)
    mapfile -t REMOTE_BRANCHES < <(git branch -r 2>/dev/null | sed -e 's/ -> /\n/g' -e 's/^[[:space:]]*//')

    for remote_branch in ${REMOTE_BRANCHES[@]}; do
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
        echo -n ">>>>>> Paused for user testing. Press enter when done....."; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_readonly() {
    local file="$1"
    if [ -w "$file" ]; then
        echo "Assertion failed: File '$file' is writable" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....."; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_writable() {
    local file="$1"
    if [ ! -w "$file" ]; then
        echo "Assertion failed: File '$file' is readonly" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....."; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_dir_has_changes() {
    local dir="$1"
    if ! git diff-index --name-only HEAD | grep -q "^$dir/"; then
        echo "Assertion failed: Directory '$dir' has no changes" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....."; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_command_fails() {
    local cmd="$1"
    if eval "$cmd"; then
        echo "Assertion failed: Command '$cmd' succeeded but expected to fail" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....."; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_command_succeeds() {
    local cmd="$1"
    if ! eval "$cmd"; then
        echo "Assertion failed: Command '$cmd' failed but expected to succeed" >&2
        echo -n ">>>>>> Paused for user testing. Press enter when done....."; read -r dummy; echo
        tearDown
        exit $FAIL
    fi
}

assert_no_uncommitted_changes() {
    if [ -n "$(git stat --porcelain)" ]; then
        rm -rf FreeCAD_Automation/tests/uncompressed/ # Note: Dir spontaneously appears after git checkout test_binaries

        if [ -n "$(git stat --porcelain)" ]; then
            echo "Assertion failed: There are uncommitted changes" >&2
            echo -n ">>>>>> Paused for user testing. Press enter when done....."; read -r dummy; echo
            tearDown
            exit $FAIL
        fi
    fi
}

await_user_modification() {
    local file="$1"
    while true; do
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "Please modify '$file' in FreeCAD and save it. Press enter when done."
            xdg-open "$file" > /dev/null &
            disown
            read -r dummy
            if git stat --porcelain | grep -q "^.M $file$"; then
                freecad_pid=$(pgrep -n -i FreeCAD)
                kill $freecad_pid
                break
            else
                echo "No changes detected in '$file'. Please make sure to save your modifications."
            fi
        
        elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
            echo "Please modify '$file' in FreeCAD and save it. Press enter when done."
            start "$file"
            read -r dummy
            if git stat --porcelain | grep -q "^.M $file$"; then
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
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "$message (y/n)"
            xdg-open "$file" > /dev/null &
            disown
            read -r response
            freecad_pid=$(pgrep -n -i FreeCAD)
            kill $freecad_pid

            case $response in
                [Yy]* ) return;;
                [Nn]* ) tearDown "$test_name"; exit $FAIL;;
                * ) echo "Please answer y or n.";;
            esac
        
        elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
            echo "$message (y/n)"
            start "$file"
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

# ==============================================================================================
#                                          Define Tests
# ==============================================================================================
# ToDo: Ponder edge cases missing from tests below
# Note on formatting:
    # End every command with `; echo` (variable declarations can be excluded from this)
    # Convert comments to echo statements prepended with "TEST: "

test_sandbox() {
    setup "test_sandbox" || exit $FAIL

    echo "TEST: \`git add\` \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (files copied during setup)" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$TEST_DIR/AssemblyExample.FCStd\" \"$TEST_DIR/BIMExample.FCStd\" > /dev/null"; echo
    git stat

    echo "TEST: git add get_FCStd_dir for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$(get_FCStd_dir $TEST_DIR/AssemblyExample.FCStd)\" \"$(get_FCStd_dir $TEST_DIR/BIMExample.FCStd)\" > /dev/null"; echo
    git stat

    echo "TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial test commit\" > /dev/null"; echo
    git stat

    echo "TEST: git lock \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_command_succeeds "git lock \"$TEST_DIR/BIMExample.FCStd\""; echo
    git stat
    
    echo "TEST: git push origin active_test" >&2
    assert_command_succeeds "git push origin active_test"; echo
    git stat
    
    echo -n ">>>>>> Paused for user testing. Press enter when done....."; read -r dummy; echo
    
    tearDown "test_sandbox" || exit $FAIL

    return $SUCCESS
}

test_FCStd_filter() {
    setup "test_FCStd_filter" || exit $FAIL

    echo "TEST: remove \`BIMExample.FCStd\` (not used for this test)" >&2
    assert_command_succeeds "rm $TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: \`git add\` \`AssemblyExample.FCStd\` (file copied during setup)" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd > /dev/null"; echo

    echo "TEST: Assert get_FCStd_dir for \`AssemblyExample.FCStd\` exists now" >&2
    local FCStd_dir_path
    FCStd_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_FCStd_filter"; exit $FAIL; }
    assert_dir_exists "$FCStd_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$FCStd_dir_path\" > /dev/null"; echo

    echo "TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\" > /dev/null"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is now readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: attempt to git add changes (expect error)" >&2
    assert_command_fails "git add $TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git add \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git add\`(ed)" >&2
    assert_dir_has_changes "$FCStd_dir_path"; echo

    tearDown "test_FCStd_filter" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_FCStd_filter' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_pre_commit_hook() {
    setup "test_pre_commit_hook" || exit $FAIL

    echo "TEST: remove \`BIMExample.FCStd\` (not used for this test)" >&2
    assert_command_succeeds "rm $TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: \`git add\` \`AssemblyExample.FCStd\` (file copied during setup)" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Assert get_FCStd_dir for \`AssemblyExample.FCStd\` exists now" >&2
    local FCStd_dir_path
    FCStd_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_pre_commit_hook"; exit $FAIL; }
    assert_dir_exists "$FCStd_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$FCStd_dir_path\""; echo

    echo "TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is now readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: BYPASS_LOCK=1 git add \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "BYPASS_LOCK=1 git add $TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git add\`(ed)" >&2
    assert_dir_has_changes "$FCStd_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$FCStd_dir_path\""; echo

    echo "TEST: git commit -m \"active_test commit that should error, no lock\" (expect error)" >&2
    assert_command_fails "git commit -m \"active_test commit that should error, no lock\""; echo

    tearDown "test_pre_commit_hook" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_pre_commit_hook' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_pre_push_hook() {
    setup "test_pre_push_hook" || exit $FAIL

    echo "TEST: \`git add\` \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (files copied during setup)" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd $TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Assert get_FCStd_dir exists now for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    local Assembly_dir_path
    Assembly_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_pre_push_hook"; exit $FAIL; }
    assert_dir_exists "$Assembly_dir_path"; echo
    local BIM_dir_path
    BIM_dir_path=$(get_FCStd_dir "$TEST_DIR/BIMExample.FCStd") || { tearDown "test_pre_push_hook"; exit $FAIL; }
    assert_dir_exists "$BIM_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$Assembly_dir_path\" \"$BIM_dir_path\""; echo

    echo "TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` are now readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
    assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    for i in 1 2; do
        echo "TEST: 2x Request user modify \`AssemblyExample.FCStd\` ($i)" >&2
        assert_no_uncommitted_changes; echo
        await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

        echo "TEST: 2x git add \`AssemblyExample.FCStd\` ($i)" >&2
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
        assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd"; echo

        echo "TEST: 2x Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git add\`(ed) ($i)" >&2
        assert_dir_has_changes "$Assembly_dir_path"; echo

        echo "TEST: 2x git add get_FCStd_dir for \`AssemblyExample.FCStd\` ($i)" >&2
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
        assert_command_succeeds "git add \"$Assembly_dir_path\""; echo

        echo "TEST: 2x git commit -m \"active_test commit $i\" ($i)" >&2
        assert_command_succeeds "git commit -m \"active_test commit $i\""; echo
        assert_no_uncommitted_changes; echo

        echo "TEST: 2x assert \`AssemblyExample.FCStd\` is NOT readonly ($i)" >&2
        assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    done

    echo "TEST: git unlock \`AssemblyExample.FCStd\` (git alias) -- should fail because changes haven't been pushed" >&2
    assert_command_fails "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: git unlock --force \`AssemblyExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git unlock --force \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: assert \`AssemblyExample.FCStd\` is now readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git lock \`BIMExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo "TEST: assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Request user modify \`BIMExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: git add \`BIMExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Assert \`BIMExample.FCStd\` dir has changes that can be \`git add\`(ed)" >&2
    assert_dir_has_changes "$BIM_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for \`BIMExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$BIM_dir_path\""; echo

    echo "TEST: git commit -m \"active_test commit 3\"" >&2
    assert_command_succeeds "git commit -m \"active_test commit 3\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: git push origin active_test -- should fail because need to lock changes to AssemblyExample.FCStd" >&2
    assert_command_fails "git push origin active_test"; echo

    echo "TEST: git lock \`AssemblyExample.FCStd\` again (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git push origin active_test" >&2
    assert_command_succeeds "git push origin active_test"; echo
    assert_no_uncommitted_changes; echo

    tearDown "test_pre_push_hook" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_pre_push_hook' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_post_checkout_hook() {
    setup "test_post_checkout_hook" || exit $FAIL

    echo "TEST: \`git add\` \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (files copied during setup)" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd $TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Assert get_FCStd_dir exists now for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    local Assembly_dir_path
    Assembly_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_post_checkout_hook"; exit $FAIL; }
    assert_dir_exists "$Assembly_dir_path"; echo
    local BIM_dir_path
    BIM_dir_path=$(get_FCStd_dir "$TEST_DIR/BIMExample.FCStd") || { tearDown "test_post_checkout_hook"; exit $FAIL; }
    assert_dir_exists "$BIM_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$Assembly_dir_path\" \"$BIM_dir_path\""; echo

    echo "TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` are now readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
    assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: git checkout -b active_test_branch1" >&2
    assert_command_succeeds "git checkout -b active_test_branch1"; echo

    echo "TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git add \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git add\`(ed)" >&2
    assert_dir_has_changes "$Assembly_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$Assembly_dir_path\""; echo

    echo "TEST: git commit -m \"active_test_branch1 commit 1\"" >&2
    assert_command_succeeds "git commit -m \"active_test_branch1 commit 1\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git unlock \`AssemblyExample.FCStd\` (git alias) -- should fail because changes haven't been pushed" >&2
    assert_command_fails "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: git checkout active_test" >&2
    assert_command_succeeds "git checkout active_test"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: assert \`BIMExample.FCStd\` is readonly" >&2
    assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo "TEST: git fco active_test_branch1 \`*.FCStd\` -- should fail because regex isn't supported" >&2
    assert_command_fails "git fco active_test_branch1 \"*.FCStd\""; echo

    echo "TEST: git fco active_test_branch1 \`AssemblyExample.FCStd\`" >&2
    assert_command_succeeds "git fco active_test_branch1 "$TEST_DIR/AssemblyExample.FCStd""; echo

    echo "TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_post_checkout_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo "TEST: assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: assert \`BIMExample.FCStd\` is readonly" >&2
    assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo

    tearDown "test_post_checkout_hook" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_post_checkout_hook' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_stashing() {
    setup "test_stashing" || exit $FAIL

    echo "TEST: remove \`BIMExample.FCStd\` (not used for this test)" >&2
    assert_command_succeeds "rm $TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: \`git add\` \`AssemblyExample.FCStd\` (file copied during setup)" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Assert get_FCStd_dir for \`AssemblyExample.FCStd\` exists now" >&2
    local FCStd_dir_path
    FCStd_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_stashing"; exit $FAIL; }
    assert_dir_exists "$FCStd_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$FCStd_dir_path\""; echo

    echo "TEST: git commit -m \"initial active_test commit\"" >&2
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is now readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git add \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Assert changes to get_FCStd_dir for \`AssemblyExample.FCStd\` exists now" >&2
    assert_dir_has_changes "$FCStd_dir_path"; echo

    echo "TEST: git fstash the changes" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git fstash"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_stashing" "$TEST_DIR/AssemblyExample.FCStd"

    echo "TEST: git unlock \`AssemblyExample.FCStd\` (git alias) -- should fail because changes haven't been pushed" >&2
    assert_command_fails "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git push origin active_test" >&2
    assert_command_succeeds "git push origin active_test"; echo # Note: Only `git unlock` checks for stashed changes.
    assert_no_uncommitted_changes; echo

    echo "TEST: git unlock \`AssemblyExample.FCStd\` (git alias) -- should fail because STASHED changes haven't been pushed" >&2
    assert_command_fails "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git unlock --force \`AssemblyExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git unlock --force \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git fstash pop -- should fail need lock to modify AssemblyExample.FCStd" >&2
    assert_no_uncommitted_changes; echo
    assert_command_fails "git fstash pop"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git lock \`AssemblyExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git fstash pop" >&2
    assert_no_uncommitted_changes; echo
    assert_command_succeeds "git fstash pop"; echo

    echo "TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_stashing" "$TEST_DIR/AssemblyExample.FCStd"

    tearDown "test_stashing" || exit $FAIL

    echo ">>>>>>>>> TEST 'test_stashing' PASSED <<<<<<<<<" >&2
    return $SUCCESS
}

test_post_merge_hook() {
    setup "test_post_merge_hook" || exit $FAIL

    echo "TEST: \`git add\` \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (files copied during setup)" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd $TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Assert get_FCStd_dir exists now for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    local Assembly_dir_path
    Assembly_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown "test_post_merge_hook"; exit $FAIL; }
    assert_dir_exists "$Assembly_dir_path"; echo
    local BIM_dir_path
    BIM_dir_path=$(get_FCStd_dir "$TEST_DIR/BIMExample.FCStd") || { tearDown "test_post_merge_hook"; exit $FAIL; }
    assert_dir_exists "$BIM_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for both \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$Assembly_dir_path\" \"$BIM_dir_path\""; echo

    echo "TEST: git commit -m \"initial active_test commit\"" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git commit -m \"initial active_test commit\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` are now readonly" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
    assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git lock \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` (git alias)" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git lock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_command_succeeds "git lock \"$TEST_DIR/BIMExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` and \`BIMExample.FCStd\` is NOT readonly" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"; echo
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git push origin active_test" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git push origin active_test"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git unlock \`BIMExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git unlock \"$TEST_DIR/BIMExample.FCStd\""; echo

    echo "TEST: Assert \`BIMExample.FCStd\` is now readonly" >&2
    assert_readonly "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Request user modify \`AssemblyExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: git add \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` dir has changes that can be \`git add\`(ed)" >&2
    assert_dir_has_changes "$Assembly_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for \`AssemblyExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$Assembly_dir_path\""; echo

    echo "TEST: git commit -m \"active_test commit 1\"" >&2
    assert_command_succeeds "git commit -m \"active_test commit 1\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git push origin active_test" >&2
    assert_command_succeeds "git push origin active_test"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git freset --hard active_test^" >&2
    assert_command_succeeds "git freset --hard active_test^"; echo
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_no_uncommitted_changes; echo

    echo "TEST: git update-ref refs/remotes/origin/active_test active_test" >&2
    assert_command_succeeds "git update-ref refs/remotes/origin/active_test active_test"; echo
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_no_uncommitted_changes; echo

    echo "TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_merge_hook" "$TEST_DIR/AssemblyExample.FCStd"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_no_uncommitted_changes; echo

    echo "TEST: git unlock \`AssemblyExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git unlock \"$TEST_DIR/AssemblyExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is now readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git lock \`BIMExample.FCStd\` (git alias)" >&2
    assert_command_succeeds "git lock \"$TEST_DIR/BIMExample.FCStd\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Request user modify \`BIMExample.FCStd\`" >&2
    assert_no_uncommitted_changes; echo
    await_user_modification "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: git add \`BIMExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Assert \`BIMExample.FCStd\` dir has changes that can be \`git add\`(ed)" >&2
    assert_dir_has_changes "$BIM_dir_path"; echo

    echo "TEST: git add get_FCStd_dir for \`BIMExample.FCStd\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add \"$BIM_dir_path\""; echo

    echo "TEST: git commit -m \"active_test commit 1b\"" >&2
    assert_command_succeeds "git commit -m \"active_test commit 1b\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git pull --rebase origin active_test" >&2
    # For some reason linux likes to go into interactive rebase mode with no changes, requesting `git rebase --continue` command...
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "--- TEST: Rebasing and continuing for linux" >&2
        echo -n ">>>>>> Paused for manual user rebasing. (should be no conflicts or modified files post rebase). Press enter when done....."; read -r dummy; echo
        # git pull --rebase origin active_test; echo
        # git rebase --continue; echo
    else
        echo "--- TEST: Standard rebase for windows" >&2
        assert_command_succeeds "git pull --rebase origin active_test"; echo
    fi
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Ask user to confirm \`BIMExample.FCStd\` changes are still present" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' changes are still present." "test_post_merge_hook" "$TEST_DIR/BIMExample.FCStd"

    echo "TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes are back." "test_post_merge_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo "TEST: git freset --soft active_test^" >&2
    assert_command_succeeds "git freset --soft active_test^"; echo

    echo "TEST: git fstash" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git fstash"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: git freset --hard active_test^" >&2
    assert_command_succeeds "git freset --hard active_test^"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Ask user to confirm \`BIMExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' changes have been reverted." "test_post_merge_hook" "$TEST_DIR/BIMExample.FCStd"

    echo "TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes reverted" >&2
    confirm_user "Please confirm that 'AssemblyExample.FCStd' changes have been reverted." "test_post_merge_hook" "$TEST_DIR/AssemblyExample.FCStd"

    echo "TEST: git update-ref refs/remotes/origin/active_test active_test" >&2
    assert_command_succeeds "git update-ref refs/remotes/origin/active_test active_test"; echo

    echo "TEST: git fstash pop" >&2
    assert_no_uncommitted_changes; echo
    assert_command_succeeds "git fstash pop"; echo

    echo "TEST: git add \`$TEST_DIR\`" >&2
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then sleep 1; sync; sync; echo; fi
    assert_command_succeeds "git add $TEST_DIR"; echo

    echo "TEST: git commit -m \"active_test commit 1b\"" >&2
    assert_command_succeeds "git commit -m \"active_test commit 1b\""; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Ask user to confirm \`BIMExample.FCStd\` changes are back" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' changes are back." "test_post_merge_hook" "$TEST_DIR/BIMExample.FCStd"

    echo "TEST: git pull --no-rebase origin active_test" >&2
    assert_command_succeeds "git pull --no-rebase origin active_test"; echo
    assert_no_uncommitted_changes; echo

    echo "TEST: Assert \`BIMExample.FCStd\` is NOT readonly" >&2
    assert_writable "$TEST_DIR/BIMExample.FCStd"; echo

    echo "TEST: Assert \`AssemblyExample.FCStd\` is readonly" >&2
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"; echo

    echo "TEST: Ask user to confirm \`BIMExample.FCStd\` changes are still present" >&2
    confirm_user "Please confirm that 'BIMExample.FCStd' changes are still present." "test_post_merge_hook" "$TEST_DIR/BIMExample.FCStd"

    echo "TEST: Ask user to confirm \`AssemblyExample.FCStd\` changes are back" >&2
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
    echo -n ">>>> START SANDBOX TEST? <<<<"; read -r dummy; echo
    
    test_sandbox

    echo -n ">>>> END OF TESTING <<<<"; read -r dummy; echo

    rm -rf FreeCAD_Automation/tests/uncompressed/ # Note: Dir spontaneously appears after git checkout test_binaries
    exit $SUCCESS

elif [ -z "$1" ]; then
    echo -n ">>>> START STANDARD TEST? <<<<"; read -r dummy; echo
    
    # test_FCStd_filter
    # test_pre_commit_hook
    # test_pre_push_hook
    # test_post_checkout_hook
    # test_stashing
    test_post_merge_hook

    echo -n ">>>> END OF TESTING <<<<"; read -r dummy; echo

    rm -rf FreeCAD_Automation/tests/uncompressed/ # Note: Dir spontaneously appears after git checkout test_binaries
    exit $SUCCESS
fi
exit $FAIL