### Workflow / ToDo List:
- [ ] Move hard coded file locations to `functions.sh`

- [ ] Remove useless cds at start of hooks / filter / lock / unlock scripts

- [ ] `freecad-repo-init.sh`
    - [x] Verify and retrieve dependency objects
    - [x] setup git-lfs.
    - [x] Setup `*.[Ff][Cc][Ss][Tt][Dd]` filter
		- [x] `git config filter.FCStd.required true`
		- [x] `git config filter.FCStd.smudge cat`
		- [x] Check for any case of *.FCStd
	- [ ] Add git aliases
	- [ ] Newly Clone Repo Support
		- [ ] Trigger post-checkout after initialization.
		- [ ] .FCStd files to readonly if config requires it and remove readonly if config doesn't require it.
		- [ ] Pull latest LFS files
		- [ ] Ensure all .FCStd files have been imported with local data

- [x] Git clean filter
    - [x] Makes .FCStd files look empty (from git's pov)
    - [x] Calls script to extract the added file.
		- [x] If user doesn't have lock, error out specifying that the user doesn't have the lock
		- [x] Check if `require-lock-to-modify-FreeCAD-files` is true

- [ ] On Post-Checkout Hook
    - [ ] Pull LFS files
		- [ ] Make sure `FCStdFileTool.py` doesn't import pointer files
	- [ ] Update (import) .FCStd files with uncompressed files:
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

- [x] On Pre-Commit Hook:
	- [x] Check if `require-lock-to-modify-FreeCAD-files` is true
		- [x] Cancel commit if user doesn't have lock on .lockfile in dir being modified

- [x] On Pre-Push Hook:
	- [x] Check if `require-lock-to-modify-FreeCAD-files` is true
		- [x] Cancel push if in any commits being pushed, user doesn't have lock on .lockfile for dir with modifications.

- [ ] Git Aliases:
	- [ ] Experiment with `${GIT_PREFIX:-.}` see https://stackoverflow.com/questions/26243145/git-aliases-operate-in-the-wrong-directory
	- [ ] lock.sh | USAGE: lock.sh path/to/file.FCStd:
		- [ ] Set git lfs lock appropriate _FCStd directory .lockfile
		- [ ] mark .FCStd file as writable
	- [ ] unlock.sh | USAGE: unlock.sh path/to/file.FCStd:
		- [ ] Set git lfs unlock appropriate _FCStd directory .lockfile
		- [ ] mark .FCStd file as readonly
		- [ ] Warn user if unlocking before changes have been pushed changes
	- [ ] To use `FCStdFileTool.py` manually

- [ ] Verify `Readme.md` is correct

Locks:
 - Set file to readonly
 - Prevents changes from being pushed.