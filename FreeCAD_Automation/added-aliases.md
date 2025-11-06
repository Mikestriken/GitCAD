## Git Aliases
### `git fadd`
Sets the `EXPORT_ENABLED=1` environment variable flag when calling `git add`. This allows the FCStd clean filter to export `.FCStd` files.
Git sometimes sneakily calls the clean filter when exporting is not intended, this is a guard to make sure `.FCStd` files are ONLY exported when the user explicitly expects it.

*Behind the scenes all this does is call `EXPORT_ENABLED=1 git add`*

Usage: `git fadd path/to/file.FCStd` (same as `git add`)

### `git lock`
Locks a `.FCStd` file for editing by locking the associated `.lockfile` in the uncompressed directory using Git LFS. This prevents others from modifying the file and makes the `.FCStd` file writable for editing in FreeCAD. Supports `--force` to steal existing locks (if you have permission to do so according to GitHub).

Usage: `git lock path/to/file.FCStd [--force]`

### `git unlock`
Unlocks a previously locked `.FCStd` file by unlocking the associated `.lockfile` in Git LFS. Checks for unpushed changes in the uncompressed directory and prevents unlocking if changes exist (unless `--force` is used). Makes the `.FCStd` file readonly after unlocking.

Usage: `git unlock path/to/file.FCStd [--force]`

### `git locks`
A shorthand alias for `git lfs locks`.
Provides a list of who has locks on files and which file they have a lock for.

Usage: `git locks`

### `git freset`
#### __Description:__
A wrapper for `git reset` that ensures `.FCStd` files remain synchronized with their uncompressed directories after resetting. Wrapper observes the commit and working directory before and after the reset action to make changes. This should command should be used as a replacement for `git reset`.

Usage: `git freset [reset options]` (same as `git reset`)

#### __If used `git reset` instead on accident:__
The `.FCStd` files in your working directory may not be synchronized with their uncompressed directories. To manually fix this:

1. Run `git fimport path/to/file.FCStd` for each `.FCStd` file affected by the `git reset` to import the data from the uncompressed directory back into the `.FCStd` file.
2. Use `git fcmod path/to/file.FCStd` to clear the modification in git's view (make git think the `.FCStd` file is empty)

### `git fstash`
#### __Description:__
A wrapper for `git stash` operations that ensures `.FCStd` files remain synchronized with their uncompressed directories. Automatically imports `.FCStd` files after popping or applying stashes, also imports them after stashing to keep the `.FCStd` files synchronized with uncompressed directories. For pop/apply operations, checks that the user owns locks for any associated `.lockfile`s in the stash before proceeding.

Usage:
- `git fstash` - Stash working directory changes (imports stashed uncompressed `.FCStd` directories after stash)
- `git fstash -- path/to/files/to/stash` - Stash specific working directory changes (imports stashed uncompressed `.FCStd` directories after stash)
- `git fstash pop [index]` - Pop a stash (imports `.FCStd` files after)
- `git fstash apply [index]` - Apply a stash without removing it (imports `.FCStd` files after)

*Note: `git fstash` is basically a hook wrapper for `git stash` so you can other normal `git stash` operations such as `git fstash list` without consequence.*

#### __If used `git stash` instead on accident:__
After popping, applying or stashing with `git stash`, the stashed/unstashed `.FCStd` file directories will not be synchronized with their corresponding `.FCStd` files. To manually fix this:

1. Run `git fimport path/to/file.FCStd` for each affected `.FCStd` file to synchronize the data.

### `git fco`
#### __Description:__
Checks out specific `.FCStd` files from a given commit by retrieving their uncompressed directories and importing the data back into the `.FCStd` files. This allows reverting individual `.FCStd` files to a previous version without affecting other files.

This is basically how you `git checkout COMMIT -- FILE [FILE ...]` **ONLY** `.FCStd` files. The purpose of this alias is to redirect `FILE` from the empty `.FCStd` file to the directory containing the data for the `.FCStd` file and then reimport/synchronize the `.FCStd` file with its directory.

Usage: `git fco COMMIT FILE [FILE ...]`

Note 1: Wildcards are not supported; specify exact file paths.

Note 2: `git fco` is **ONLY** for `.FCStd` files (and their dirs), any other type of file can be checked out manually using the normal `git checkout COMMIT -- FILE [FILE ...]`. Checking out branches with `git checkout` works normally (no alias required).

#### __If used `git checkout COMMIT -- FILE [FILE ...]` instead on accident:__
The `.FCStd` file will be checked out as empty without importing from the uncompressed directory. In other words, nothing will happen, so simply re-run the command.  
*NOTE AGAIN: `git fco` is ONLY for `.FCStd` files (and their dirs), any other type of file can be checked out manually using the normal `git checkout COMMIT -- FILE [FILE ...]`.*

### `git fcmod`
Manually tells git to observe a `.FCStd` file as empty (unmodified). Unfortunately to do this it will first restore any currently staged (added) `.FCStd` files.

*Behind the scenes all this does is call `git restore --staged $STAGED_FCSTD_FILES` then `RESET_MOD=1 git add [ARGS]`*

Usage: `git fcmod path/to/file.FCStd` (same as `git add`)

### `git ftool`
Runs the `FCStdFileTool.py` script for manual export or import of `.FCStd` files. Useful for advanced operations, troubleshooting, or direct manipulation of `.FCStd` files outside the normal Git workflow.

Run: `git ftool` (no args) to see usage details.

### `git fimport`
Runs the `FCStdFileTool.py` script with preset args to manually import data to specified `.FCStd` file.

Usage: `git fimport path/to/file.FCStd`

### `git fexport`
Runs the `FCStdFileTool.py` script with preset args to manually export data from specified `.FCStd` file.

Usage: `git fexport path/to/file.FCStd`