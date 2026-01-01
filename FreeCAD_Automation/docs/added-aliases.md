# Git Aliases
## GitCAD Activation
### __DESCRIPTION:__
Some of the aliases listed below are intended to be a complete replacement for a standard git commands.  
Failing to use the alias instead of the standard git command can sometimes cause undesired results.  
The solution to this is to activate the GitCAD terminal environment.

Doing this redirects all git calls to the wrapper script `FreeCAD_Automation/git`.  
This script intercepts standard git calls and redirects them to the appropriate git alias.

Activation is indicated with a `(GitCAD)` to the left of the prompt string.

### __USAGE:__
- PowerShell: `.\FreeCAD_Automation\user_scripts\activate.ps1`
- Bash: `source FreeCAD_Automation/user_scripts/activate`

*To deactivate run `deactivate_GitCAD`*

## `git fadd` / `git add` (with GitCAD Activation)
### __DESCRIPTION:__
Sets the `GIT_COMMAND="add"` environment variable when calling `git add`. This allows the FCStd clean filter to know that an add command triggered it, allowing it to export `.FCStd` files.

Git sometimes sneakily calls the clean filter when exporting is not intended, this is a guard to make sure `.FCStd` files are ONLY exported when the user explicitly expects it.

*Behind the scenes all this does is call `GIT_COMMAND="add" git add`*

**IMPORTANT NOTE:** This command should be used as a replacement for `git add`.

### __USAGE:__
- `git fadd FILE.FCStd` (same as `git add`)

### __If used `git add` instead on accident (without GitCAD Activation):__
The specified `.FCStd` file will not be exported HOWEVER, the `.FCStd` file will be staged. 

You will not be able to commit the staged `.FCStd` file (the pre-commit hook will fail the operation).

1. Run `git restore --staged FILE.FCStd`
2. Run `git fadd FILE.FCStd` to actually export it this time

## `git lock`
### __DESCRIPTION:__
Locks a `.FCStd` file for editing by locking the associated `.lockfile` in the uncompressed directory using Git LFS. This prevents others from modifying the file and makes the `.FCStd` file writable for editing in FreeCAD.

Supports `--force` to steal existing locks (if you have permission to do so according to the remote repository (GitHub)).

### __IMPORTANT NOTE ON LOCKING:__ 
When you lock a file the name registered on the file that is locked is either the username in the ssh credential (if repo is cloned via ssh link), OR the username in your windows credential (search Manage Windows Credentials on windows taskbar to see it).

In order for GitCAD as a whole (all the scripts that encompass this project) the username registered to the ssh link or Windows Credentials MUST match the username that you set locally via `git config user.name YOUR_USERNAME` or globally if not set locally via `git config --global user.name YOUR_USERNAME`.

### __USAGE:__
- `git lock [--force] FILE.FCStd [FILE.FCStd ...]`

## `git unlock`
### __DESCRIPTION:__
Unlocks a previously locked `.FCStd` file by unlocking the associated `.lockfile` in Git LFS. Checks for unpushed changes in the uncompressed directory and prevents unlocking if changes exist (unless `--force` is used). Makes the `.FCStd` file readonly after unlocking.

### __IMPORTANT NOTE ON LOCKING:__ 
When you lock a file the name registered on the file that is locked is either the username in the ssh credential (if repo is cloned via ssh link), OR the username in your windows credential (search Manage Windows Credentials on windows taskbar to see it).

In order for GitCAD as a whole (all the scripts that encompass this project) the username registered to the ssh link or Windows Credentials MUST match the username that you set locally via `git config user.name YOUR_USERNAME` or globally if not set locally via `git config --global user.name YOUR_USERNAME`.

### __USAGE:__
- `git unlock [--force] FILE.FCStd [FILE.FCStd ...]`

## `git locks`
### __DESCRIPTION:__
A shorthand alias for `git lfs locks`.
Provides a list of who has locks on files and which file they have a lock for.

### __IMPORTANT NOTE ON LOCKING:__ 
When you lock a file the name registered on the file that is locked is either the username in the ssh credential (if repo is cloned via ssh link), OR the username in your windows credential (search Manage Windows Credentials on windows taskbar to see it).

In order for GitCAD as a whole (all the scripts that encompass this project) the username registered to the ssh link or Windows Credentials MUST match the username that you set locally via `git config user.name YOUR_USERNAME` or globally if not set locally via `git config --global user.name YOUR_USERNAME`.

### __USAGE:__
- `git locks`

## `git freset` / `git reset` (with GitCAD Activation)
### __DESCRIPTION:__
A wrapper for `git reset` that ensures `.FCStd` files remain synchronized with their uncompressed directories after resetting. Wrapper observes the commit and working directory before and after the reset action to make changes.

**IMPORTANT NOTE:** This command should be used as a replacement for `git reset`.

### __USAGE:__
- `git freset [reset options]` (same as `git reset`)

### __If used `git reset` instead on accident (without GitCAD Activation):__
The `.FCStd` files in your working directory may not be synchronized with their uncompressed directories. To manually fix this:

1. Run `git fimport FILE.FCStd` for each `.FCStd` file affected by the `git reset` to import the data from the uncompressed directory back into the `.FCStd` file.
2. Use `git fcmod FILE.FCStd` to clear the modification in git's view (make git think the `.FCStd` file is empty)

## `git fstash` / `git stash` (with GitCAD Activation)
### __DESCRIPTION:__
A wrapper for `git stash` operations that ensures `.FCStd` files remain synchronized with their uncompressed directories. Automatically imports `.FCStd` files after popping or applying stashes. Also checks that the user owns locks for any associated `.lockfile`s in the stash / being stashed before proceeding.

**IMPORTANT NOTE:** This command should be used as a replacement for `git stash`.

### __USAGE:__
- `git fstash [stash options]` (same as `git stash`)

*Note: `git fstash` is basically a hook wrapper for `git stash` so you can other normal `git stash` operations such as `git fstash list` without consequence.*

### __If used `git stash` instead on accident (without GitCAD Activation):__
After popping, applying or stashing with `git stash`, the stashed/unstashed `.FCStd` file directories will not be synchronized with their corresponding `.FCStd` files. To manually fix this:

1. Run `git fimport FILE.FCStd` for each affected `.FCStd` file to synchronize the data.
2. Use `git fcmod FILE.FCStd` to clear the modification in git's view (make git think the `.FCStd` file is empty)

## `git fco` / `git checkout` (with GitCAD Activation)
### __DESCRIPTION:__
Checks out specified `.FCStd` files from a given commit by retrieving their uncompressed directories and importing the data back into the `.FCStd` files. This allows reverting individual `.FCStd` files to a previous version without affecting other files.

This is basically how you `git checkout COMMIT -- FILE [FILE ...]` `.FCStd` (and other filetype) files. The purpose of this alias is to redirect `FILE` from the empty `.FCStd` file to the directory containing the data for the `.FCStd` file and then reimport/synchronize the `.FCStd` file with its directory.

**IMPORTANT NOTE 1:** This command should be used as a replacement for `git checkout COMMIT -- FILE [FILE ...]`.  
**IMPORTANT NOTE 2:** This command should **NOT** be used as a replacement for `git checkout COMMIT`. **ONLY**  use this command for file checkouts, **NEVER** branch checkouts.  
**IMPORTANT NOTE 3:** The GitCAD environment is able to distinguish between the two when calling `git checkout`, and redirects appropriately.

### __USAGE:__
- `git fco COMMIT FILE [FILE ...]`
- `git fco COMMIT -- FILE [FILE ...]`

### __If used `git checkout COMMIT -- FILE [FILE ...]` instead on accident (without GitCAD Activation):__
The `.FCStd` file will be checked out as empty without importing from the uncompressed directory. In other words, nothing will happen, so simply re-run the command.  

## `git fcmod`
### __DESCRIPTION:__
Manually tells git to observe a `.FCStd` file as empty (unmodified). Unfortunately to do this it will first restore any currently staged (added) `.FCStd` files.

*Behind the scenes all this does is call `git restore --staged $STAGED_FCSTD_FILES` then puts the current utc time in a `.gitignored` `.fcmod` file located in the uncompressed directory. When the FCStd clean filter is triggered it compares the current time to the time in the `.fcmod` file to determine if the modification has been cleared or not.*

### __USAGE:__
- `git fcmod FILE.FCStd [FILE.FCStd ...]` (same as `git add`)

## `git ftool`
### __DESCRIPTION:__
Runs the `FCStdFileTool.py` script for manual export or import of `.FCStd` files. Useful for advanced operations, troubleshooting, or direct manipulation of `.FCStd` files outside the normal Git workflow.

### __USAGE:__
- `git ftool` (no args) to see usage details.

## `git fimport`
### __DESCRIPTION:__
Runs the `FCStdFileTool.py` script with preset args to manually import data to specified `.FCStd` file according to the `FreeCAD_Automation/config.json`. 

### __USAGE:__
- `git fimport FILE.FCStd`

## `git fexport`
### __DESCRIPTION:__
Runs the `FCStdFileTool.py` script with preset args to manually export data from specified `.FCStd` file according to the `FreeCAD_Automation/config.json`. 

### __USAGE:__
- `git fexport FILE.FCStd`