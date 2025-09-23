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
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: There are uncommitted changes in the working directory. Please commit or stash them before running tests."
    exit $FAIL
fi

# ==============================================================================================
#                                          Get Binaries
# ==============================================================================================
git checkout test_binaries -- FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd
git clearFCStdMod FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd

# ==============================================================================================
#                                          Test Functions
# ==============================================================================================
TEST_BRANCH="active_test"
TEST_DIR="FreeCAD_Automation/tests/$TEST_BRANCH"
setup() {
    # Checkout -b active_test
    if ! git checkout -b "$TEST_BRANCH" > /dev/null; then
        echo "Error: Branch '$TEST_BRANCH' already exists" >&2
        return $FAIL
    fi
    
    # push active_test to remote
    if ! git push -u origin "$TEST_BRANCH" > /dev/null 2>&1; then
        echo "Error: Failed to push branch '$TEST_BRANCH' to remote" >&2
        return $FAIL
    fi

    mkdir -p $TEST_DIR

    # Copies binaries into active_test dir (already done globally, but ensure)
    cp $TEST_DIR/../AssemblyExample.FCStd $TEST_DIR/../BIMExample.FCStd $TEST_DIR || return $FAIL
    
    echo ">>>> Setup complete <<<<"

    return $SUCCESS
}

tearDown() {
    # remove any locks in test dir
    git lfs locks --path="$TEST_DIR" | xargs -r git lfs unlock --force || true
    
    git reset --hard >/dev/null 2>&1
    
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
    
    echo ">>>> TearDown complete <<<<"
    
    return $SUCCESS
}

# Custom assert functions
assert_dir_exists() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "Assertion failed: Directory '$dir' does not exist" >&2
        tearDown
        exit $FAIL
    fi
}

assert_readonly() {
    local file="$1"
    if [ -w "$file" ]; then
        echo "Assertion failed: File '$file' is writable" >&2
        tearDown
        exit $FAIL
    fi
}

assert_writable() {
    local file="$1"
    if [ ! -w "$file" ]; then
        echo "Assertion failed: File '$file' is readonly" >&2
        tearDown
        exit $FAIL
    fi
}

assert_dir_has_changes() {
    local dir="$1"
    if ! git diff --name-only | grep -q "^$dir/"; then
        echo "Assertion failed: Directory '$dir' has no changes" >&2
        tearDown
        exit $FAIL
    fi
}

assert_command_fails() {
    local cmd="$1"
    if eval "$cmd"; then
        echo "Assertion failed: Command '$cmd' succeeded but expected to fail" >&2
        tearDown
        exit $FAIL
    fi
}

assert_command_succeeds() {
    local cmd="$1"
    if ! eval "$cmd"; then
        echo "Assertion failed: Command '$cmd' failed but expected to succeed" >&2
        tearDown
        exit $FAIL
    fi
}

await_user_modification() {
    local file="$1"
    while true; do
        echo "Please modify '$file' in FreeCAD and save it. Press enter when done."
        read -r dummy
        if git status --porcelain | grep -q "^.M $file$"; then
            break
        else
            echo "No changes detected in '$file'. Please make sure to save your modifications."
        fi
    done
}

# ==============================================================================================
#                                           Run Tests
# ==============================================================================================
# ToDo: Ponder edge cases missing from tests below

test_FCStd_filter() {
    setup || { echo "Setup failed" >&2 ; exit $FAIL; }

    # remove `BIMExample.FCStd` (not used for this test)
    rm $TEST_DIR/BIMExample.FCStd

    # `git add` `AssemblyExample.FCStd` (file copied during setup)
    git add $TEST_DIR/AssemblyExample.FCStd

    # Assert get_FCStd_dir for `AssemblyExample.FCStd` exists now
    local FCStd_dir_path
    FCStd_dir_path=$(get_FCStd_dir "$TEST_DIR/AssemblyExample.FCStd") || { tearDown; exit $FAIL; }
    assert_dir_exists "$FCStd_dir_path"

    # git add get_FCStd_dir for `AssemblyExample.FCStd`
    git add "$FCStd_dir_path"

    # git commit -m "initial active_test commit"
    git commit -m "initial active_test commit"

    # Assert `AssemblyExample.FCStd` is now readonly
    assert_readonly "$TEST_DIR/AssemblyExample.FCStd"

    # Request user modify `AssemblyExample.FCStd`
    await_user_modification "$TEST_DIR/AssemblyExample.FCStd"

    # attempt to git add changes (expect error)
    assert_command_fails "git add $TEST_DIR/AssemblyExample.FCStd"

    # git lock `AssemblyExample.FCStd` (git alias)
    git lock "$TEST_DIR/AssemblyExample.FCStd"

    # Assert `AssemblyExample.FCStd` is NOT readonly
    assert_writable "$TEST_DIR/AssemblyExample.FCStd"

    # git add `AssemblyExample.FCStd`
    git add "$TEST_DIR/AssemblyExample.FCStd"

    # Assert `AssemblyExample.FCStd` dir has changes that can be `git add`(ed)
    assert_dir_has_changes "$FCStd_dir_path"

    tearDown

    return $SUCCESS
}

test_setup_teardown() {
    setup || { echo "Setup failed" >&2; exit $FAIL; }
    echo -n "Paused for user inspection..."
    read -r dummy

    echo "Adding: '$TEST_DIR/AssemblyExample.FCStd' and '$TEST_DIR/BIMExample.FCStd'........"

    git add "$TEST_DIR/AssemblyExample.FCStd" "$TEST_DIR/BIMExample.FCStd"

    echo "committing..."
    git commit -m "test commit for setup/tearDown"
    git push origin $TEST_BRANCH

    echo -n "Paused for user inspection..."
    read -r dummy
    tearDown

    return $SUCCESS
}

# Run the tests
test_setup_teardown
# test_FCStd_filter

# ToDo: Test Pre-Commit Hook
    # remove `BIMExample.FCStd` (not used for this test)
    # `git add` `AssemblyExample.FCStd` (file copied during setup)
    # Assert get_FCStd_dir for `AssemblyExample.FCStd` exists now
    # git add get_FCStd_dir for `AssemblyExample.FCStd`
    # git commit -m "initial active_test commit"
    # Assert `AssemblyExample.FCStd` is now readonly
    # Request user modify `AssemblyExample.FCStd`
    # GIT_ALLOW_FILTER_FAILURE=1 git add `AssemblyExample.FCStd`
    # Assert `AssemblyExample.FCStd` dir has changes that can be `git add`(ed)
    # git add get_FCStd_dir for `AssemblyExample.FCStd`
    # git commit -m "active_test commit that should error, no lock" (expect error)

# ToDo: Test Pre-Push Hook
    # `git add` `AssemblyExample.FCStd` and `BIMExample.FCStd` (files copied during setup)
    # Assert get_FCStd_dir exists now for both `AssemblyExample.FCStd` and `BIMExample.FCStd`
    # git add get_FCStd_dir for both `AssemblyExample.FCStd` and `BIMExample.FCStd`
    # git commit -m "initial active_test commit"
    # Assert `AssemblyExample.FCStd` and `BIMExample.FCStd` are now readonly
    # git lock `AssemblyExample.FCStd` (git alias)
    # Assert `AssemblyExample.FCStd` is NOT readonly
    # 2x Request user modify `AssemblyExample.FCStd`
    # 2x git add `AssemblyExample.FCStd`
    # 2x Assert `AssemblyExample.FCStd` dir has changes that can be `git add`(ed)
    # 2x git add get_FCStd_dir for `AssemblyExample.FCStd`
    # 2x git commit -m "active_test commit 1" ... git commit -m "active_test commit 2"
    # 2x assert `AssemblyExample.FCStd` is NOT readonly
    # git unlock `AssemblyExample.FCStd` (git alias)
    # Assert error shows up in stderr about unlocking a file that has local changes not pushed to remote
    # git unlock --force `AssemblyExample.FCStd` (git alias)
    # assert `AssemblyExample.FCStd` is now readonly
    # git lock `BIMExample.FCStd` (git alias)
    # assert `BIMExample.FCStd` is NOT readonly
    # Request user modify `BIMExample.FCStd`
    # git add `BIMExample.FCStd`
    # Assert `BIMExample.FCStd` dir has changes that can be `git add`(ed)
    # git add get_FCStd_dir for `BIMExample.FCStd`
    # git commit -m "active_test commit 3"
    # assert `BIMExample.FCStd` is NOT readonly
    # git push origin active_test
    # assert error about commits with changes to files without locks being pushed
    # git lock `AssemblyExample.FCStd` again (git alias)
    # Assert `AssemblyExample.FCStd` is NOT readonly
    # git push origin active_test
    # assert success

# ToDo: Test Post-Checkout Hook -- Branch and file checkout
    # `git add` `AssemblyExample.FCStd` and `BIMExample.FCStd` (files copied during setup)
    # Assert get_FCStd_dir exists now for both `AssemblyExample.FCStd` and `BIMExample.FCStd`
    # git add get_FCStd_dir for both `AssemblyExample.FCStd` and `BIMExample.FCStd`
    # git commit -m "initial active_test commit"
    # Assert `AssemblyExample.FCStd` and `BIMExample.FCStd` are now readonly
    # git checkout -b active_test_branch1
    # git lock `AssemblyExample.FCStd` (git alias)
    # Assert `AssemblyExample.FCStd` is NOT readonly
    # Request user modify `AssemblyExample.FCStd`
    # git add `AssemblyExample.FCStd`
    # Assert `AssemblyExample.FCStd` dir has changes that can be `git add`(ed)
    # git add get_FCStd_dir for `AssemblyExample.FCStd`
    # git commit -m "active_test_branch1 commit 1"
    # assert `AssemblyExample.FCStd` is NOT readonly
    # git unlock `AssemblyExample.FCStd` (git alias)
    # Assert error shows up in stderr about unlocking a file that has local changes not pushed
    # git checkout active_branch
    # assert `AssemblyExample.FCStd` is NOT readonly
    # assert `BIMExample.FCStd` is readonly
    # Ask user to confirm `AssemblyExample.FCStd` changes reverted
    # git checkout active_test_branch1 -- `AssemblyExample.FCStd`
    # Ask user to confirm `AssemblyExample.FCStd` changes are back
    # assert `AssemblyExample.FCStd` is NOT readonly
    # assert `BIMExample.FCStd` is readonly

# ToDo: Test stashing
    # remove `BIMExample.FCStd` (not used for this test)
    # `git add` `AssemblyExample.FCStd` (file copied during setup)
    # Assert get_FCStd_dir for `AssemblyExample.FCStd` exists now
    # git add get_FCStd_dir for `AssemblyExample.FCStd`
    # git commit -m "initial active_test commit"
    # Assert `AssemblyExample.FCStd` is now readonly
    # git lock `AssemblyExample.FCStd` (git alias)
    # Assert `AssemblyExample.FCStd` is NOT readonly
    # Request user modify `AssemblyExample.FCStd`
    # git add `AssemblyExample.FCStd`
    # Assert changes to get_FCStd_dir for `AssemblyExample.FCStd` exists now
    # git stash the changes
    # Ask user to confirm `AssemblyExample.FCStd` changes reverted
    # git unlock `AssemblyExample.FCStd` (git alias)
    # Assert error shows up in stderr about unlocking a file that has stashed changes not pushed
    # git unlock --force `AssemblyExample.FCStd` (git alias)
    # Assert `AssemblyExample.FCStd` is readonly
    # git stash pop
    # Assert error shows up in stderr about failing to merge stashed changes with files user doesn't have lock for
    # git lock `AssemblyExample.FCStd` (git alias)
    # Assert `AssemblyExample.FCStd` is NOT readonly
    # git stash pop
    # Ask user to confirm `AssemblyExample.FCStd` changes are back

# ToDo: Test Post-Merge Hook
    # `git add` `AssemblyExample.FCStd` and `BIMExample.FCStd` (files copied during setup)
    # Assert get_FCStd_dir exists now for both `AssemblyExample.FCStd` and `BIMExample.FCStd`
    # git add get_FCStd_dir for both `AssemblyExample.FCStd` and `BIMExample.FCStd`
    # git commit -m "initial active_test commit"
    # Assert `AssemblyExample.FCStd` and `BIMExample.FCStd` are now readonly
    # git lock `AssemblyExample.FCStd` (git alias)
    # Assert `AssemblyExample.FCStd` is NOT readonly
    # Request user modify `AssemblyExample.FCStd`
    # git add `AssemblyExample.FCStd`
    # Assert `AssemblyExample.FCStd` dir has changes that can be `git add`(ed)
    # git add get_FCStd_dir for `AssemblyExample.FCStd`
    # git commit -m "active_test commit 1"
    # git push origin active_test
    # git reset --hard active_test^
    # git update-ref refs/remotes/origin/active_test active_test
    # Ask user to confirm `AssemblyExample.FCStd` changes reverted
    # git unlock `AssemblyExample.FCStd` (git alias)
    # Assert `AssemblyExample.FCStd` is now readonly
    # Assert no error from git unlock
    # git lock `BIMExample.FCStd` (git alias)
    # Assert `BIMExample.FCStd` is NOT readonly
    # Request user modify `BIMExample.FCStd`
    # git add `BIMExample.FCStd`
    # Assert `BIMExample.FCStd` dir has changes that can be `git add`(ed)
    # git add get_FCStd_dir for `BIMExample.FCStd`
    # git commit -m "active_test commit 1b"
    # git pull --rebase origin active_test
    # Assert `BIMExample.FCStd` is NOT readonly
    # Assert `AssemblyExample.FCStd` is readonly
    # Ask user to confirm `AssemblyExample.FCStd` changes are back
    # git reset --soft active_test^
    # git stash
    # git reset --hard active_test^
    # Ask user to confirm `BIMExample.FCStd` changes reverted
    # Ask user to confirm `AssemblyExample.FCStd` changes reverted
    # git update-ref refs/remotes/origin/active_test active_test
    # git stash pop
    # git commit -m "active_test commit 1b"
    # Ask user to confirm `BIMExample.FCStd` changes are back
    # git pull origin active_test
    # Assert `BIMExample.FCStd` is NOT readonly
    # Assert `AssemblyExample.FCStd` is readonly
    # Ask user to confirm `AssemblyExample.FCStd` changes are back

exit $SUCCESS