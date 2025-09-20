#!/bin/bash
# ==============================================================================================
#                                  Verify and Retrieve Dependencies
# ==============================================================================================
# Check if inside a Git repository and ensure working dir is the root of the repo
if ! git rev-parse --git-dir > /dev/null; then
    echo "Error: Not inside a Git repository" >&2
    exit 1
fi

GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Import code used in this script
FUNCTIONS_FILE="FreeCAD_Automation/functions.sh"
source "$FUNCTIONS_FILE"

CONFIG_FILE="FreeCAD_Automation/git-freecad-config.json"

# Extract Python path
PYTHON_PATH=$(get_freecad_python_path "$CONFIG_FILE") || exit 1

# ToDo: Check for uncommitted work in working directory, exit early if so with error message

# ==============================================================================================
#                                          Test Functions
# ==============================================================================================
# ToDo: setup function
    # Checkout -b active_test
        # Err if returns 1 (branch already exists)
    # push active_test to remote
    # Copies binaries into active_test dir
    # return test dir path

# ToDo: tearDown function
    # Note: this should be called in the event any of the tests fail as well and then the script will exit early (this test will fail-fast)
    # remove any locks in test dir
    # git reset --hard
    # git checkout main
    # Delete active_test* branches (local and remote)

# ToDo: Any custom assert functions

# ToDo: Await user modification of `.FCStd` file (verify file was modified before exiting)
# ==============================================================================================
#                                          Get Binaries
# ==============================================================================================
git checkout test_binaries -- FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd
git add FreeCAD_Automation/tests/AssemblyExample.FCStd FreeCAD_Automation/tests/BIMExample.FCStd

# ! git add executes the clean FCStd filter on the added .FCStd files.
# ! Make sure to remove them after running the tests (don't commit them)

# ==============================================================================================
#                                           Run Tests
# ==============================================================================================
# ToDo: Ponder edge cases missing from tests below
# ToDo: Locking alias will need to be tested manually in separate cloned repos

# ToDo: Test FCStd-filter.sh
    # remove `BIMExample.FCStd` (not used for this test)
    # `git add` `AssemblyExample.FCStd` (file copied during setup)
    # Assert get_FCStd_dir for `AssemblyExample.FCStd` exists now
    # git add get_FCStd_dir for `AssemblyExample.FCStd`
    # git commit -m "initial active_test commit"
    # Assert `AssemblyExample.FCStd` is now readonly
    # Request user modify `AssemblyExample.FCStd`
    # attempt to git add changes (expect error)
    # git lock `AssemblyExample.FCStd` (git alias)
    # Assert `AssemblyExample.FCStd` is NOT readonly
    # git add `AssemblyExample.FCStd`
    # Assert `AssemblyExample.FCStd` dir has changes that can be `git add`(ed)

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
