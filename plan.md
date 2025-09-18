### Workflow / ToDo List:
- [ ] `freecad-repo-init.sh`
    - [x] Verify and retrieve dependency objects
    - [x] setup git-lfs.
    - [ ] Setup `*.[Ff][Cc][Ss][Tt][Dd]` filter
		- [x] `git config filter.FCStd.required true`
		- [x] `git config filter.FCStd.smudge cat`
		- [ ] Check for any case of *.FCStd
			- [ ] Research what happens when 2 filters for *.FCStd
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
	- [ ] Update .FCStd files with uncompressed files
		- [ ] Check if `require-lock-to-modify-FreeCAD-files` is true
			- [ ] if the .lockfile is not locked by the user, the .FCStd file is set to readonly.

- [x] On Pre-Commit Hook:
	- [x] Check if `require-lock-to-modify-FreeCAD-files` is true
		- [x] Cancel commit if user doesn't have lock on .lockfile in dir being modified

- [x] On Pre-Push Hook:
	- [x] Check if `require-lock-to-modify-FreeCAD-files` is true
		- [x] Cancel push if in any commits being pushed, user doesn't have lock on .lockfile for dir with modifications.

- [ ] To lock, use lock.sh path/to/file.FCStd | path/to/.lockfile:
	- [ ] Set git lfs lock appropriate _FCStd directory .lockfile
	- [ ] mark .FCStd file as writable

- [ ] To unlock, use unlock.sh path/to/file.FCStd | path/to/.lockfile:
	- [ ] Set git lfs unlock appropriate _FCStd directory .lockfile
	- [ ] mark .FCStd file as readonly
	- [ ] Warn user if unlocking before changes have been pushed changes

- [ ] Verify `Readme.md` is correct

Locks:
 - Set file to readonly
 - Prevents changes from being pushed.