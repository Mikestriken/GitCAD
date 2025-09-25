### Workflow / ToDo List:
- [x] Move hard coded file locations to `utils.sh`

- [x] Remove useless cds at start of hooks / filter / lock / unlock scripts

- [ ] `freecad-repo-init.sh`
    - [x] Verify and retrieve dependency objects
    - [x] setup git-lfs.
    - [x] Setup `*.[Ff][Cc][Ss][Tt][Dd]` filter
		- [x] `git config filter.FCStd.required true`
		- [x] `git config filter.FCStd.smudge cat`
		- [x] Check for any case of *.FCStd
	- [x] Add git aliases
	- [ ] Newly Clone Repo Support
		- [ ] Pull latest LFS files
		- [ ] If `.FCStd` file in repo has size 0 => Import data to file.
		- [ ] Trigger post-checkout after initialization.
			- [ ] .FCStd files to readonly if config requires it and remove readonly if config doesn't require it.

- [x] Git clean filter => `git add file.FCStd`
    - [x] Makes .FCStd files look empty (from git's pov)
    - [x] Calls script to extract the added file.
		- [x] If user doesn't have lock, error out specifying that the user doesn't have the lock
		- [x] Check if `require-lock-to-modify-FreeCAD-files` is true

- [ ] Post-Checkout Hook => `git checkout branch` & `git checkout -- file.FCStd`
	- [x] Run `git lfs` hook
    - [x] Pull LFS files
		- [x] Make sure `FCStdFileTool.py` doesn't import pointer files
	- [ ] Update changed `.FCStd` files with uncompressed files
		- [x] Branch checkout => Iterates all `.FCStd` files and checks for changes in dir
		- [ ] File Checkout
			- [ ] Use git alias to provide commit hash and list of files being checked out.
			- [ ] Redirect `.FCStd` checkout to the `.FCStd` file's dir
			- [ ] Check for changes and update the `.FCStd` file if changes are present.

- [x] Pre-Commit Hook => `git commit`
	- [x] Check if `require-lock-to-modify-FreeCAD-files` is true
		- [x] Cancel commit if user doesn't have lock on .lockfile in dir being modified

- [x] Post-Commit Hook => `git commit`
	- [x] Run `git lfs` hook
	- [x] Set committed `.FCStd` files readonly / writable

- [x] Pre-Push Hook => `git push`
	- [x] Run `git lfs` hook
	- [x] Check if `require-lock-to-modify-FreeCAD-files` is true
		- [x] Cancel push if in any commits being pushed, user doesn't have lock on .lockfile for dir with modifications.

- [x] Post-Merge => `git merge`
	- [x] Run `git lfs` hook
    - [x] Pull LFS files
		- [x] Make sure `FCStdFileTool.py` doesn't import pointer files
	- [x] Update changed `.FCStd` files with uncompressed files
		- [x] Iterates all `.FCStd` files and checks for changes in dir

- [x] Post-Rewrite => `git pull --rebase` & `git rebase` & `git commit --amend`
    - [x] Pull LFS files
		- [x] Make sure `FCStdFileTool.py` doesn't import pointer files
	- [x] Update changed `.FCStd` files with uncompressed files
		- [x] Iterates all `.FCStd` files and checks for changes in dir

- [x] Git Aliases:
	- [x] Experiment with `${GIT_PREFIX:-.}` see https://stackoverflow.com/questions/26243145/git-aliases-operate-in-the-wrong-directory
	- [x] lock.sh | USAGE: lock.sh path/to/file.FCStd:
		- [x] Set git lfs lock appropriate _FCStd directory .lockfile
		- [x] mark .FCStd file as writable
	- [x] unlock.sh | USAGE: unlock.sh path/to/file.FCStd:
		- [x] Set git lfs unlock appropriate _FCStd directory .lockfile
		- [x] mark .FCStd file as readonly
		- [x] Warn user if unlocking before changes have been pushed changes
	- [x] To use `FCStdFileTool.py` manually

- [ ] Verify update (import) of .FCStd files with uncompressed files:
	- [ ] When?:
		- [ ] When checking out a branch / commit
			- [ ] If file dir contents changed -> Update file
		- [ ] After cloning the repository
			- [ ] Update all files
		- [ ] When pulling/merging/rebasing changes
			- [ ] If file dir contents changed -> Update file
			- [ ] Locking should enforce fast forward only
		- [ ] Creating a stash
			- [ ] If file dir contents changed -> Update file
		- [ ] Applying a stash
			- [ ] If file dir contents changed -> Update file
		- [ ] Checking out an individual file
			- [ ] Redirect checkout to file dir instead of file itself
			- [ ] If file dir contents changed -> Update file
		- [ ] git reset --hard
			- [ ] If file dir contents changed -> Update file
		- [ ] git lfs pulls changes
			- [ ] If file dir contents changed -> Update file
	- [ ] After importing data to the .FCStd File:
		- [ ] Check if `require-lock-to-modify-FreeCAD-files` is true
			- [ ] if the .lockfile is not locked by the user, the .FCStd file is set to readonly, else writable

- [ ] Verify `Readme.md` is correct

Locks:
 - Set file to readonly
 - Prevents changes from being pushed.