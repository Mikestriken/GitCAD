### ToDo:
- [ ] Make sure `./FreeCAD_Automation/freecad-repo-init.sh` triggers Post-Checkout hook after execution (for sake of initializing a newly cloned repo)
	- [ ] Make `./FreeCAD_Automation/freecad-repo-init.sh` set .FCStd files to readonly if config requires it and remove readonly if config doesn't require it.

- [x] Make `./FreeCAD_Automation/freecad-repo-init.sh` setup git-lfs.  
  Make sure rerunning after config changes is OK.

- [x] Make `./FreeCAD_Automation/freecad-repo-init.sh` set `git config filter.FCStd.required true`

- [x] Make `./FreeCAD_Automation/freecad-repo-init.sh` set `git config filter.FCStd.smudge cat`

### Workflow Idea:
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

- [ ] On Pre-Commit Hook:
	- [ ] Check if `require-lock-to-modify-FreeCAD-files` is true
		- [ ] Cancel commit if user doesn't have lock on .lockfile in dir being modified

- [ ] On Pre-Push Hook:
	- [ ] Check if `require-lock-to-modify-FreeCAD-files` is true
		- [ ] Cancel push if in any commits being pushed, user doesn't have lock on .lockfile for dir with modifications.

- [ ] To lock, use lock.sh path/to/file.FCStd | path/to/.lockfile:
	- [ ] Set git lfs lock appropriate _FCStd directory .lockfile
	- [ ] mark .FCStd file as writable

- [ ] To unlock, use unlock.sh path/to/file.FCStd | path/to/.lockfile:
	- [ ] Set git lfs unlock appropriate _FCStd directory .lockfile
	- [ ] mark .FCStd file as readonly
	- [ ] Warn user if unlocking before changes have been pushed changes


Locks:
 - Set file to readonly
 - Prevents changes from being pushed.