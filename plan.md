### ToDo:
- [ ] Make sure `./FreeCAD_Automation/freecad-repo-init.sh` triggers Post-Checkout hook after execution (for sake of initializing a newly cloned repo)

- [ ] Make `./FreeCAD_Automation/freecad-repo-init.sh` setup git-lfs.  
  Make sure rerunning after config changes is OK.

- [ ] Make `./FreeCAD_Automation/freecad-repo-init.sh` set .FCStd files to readonly if config requires it and remove readonly if config doesn't require it.

### IDEA:
- [x] Git clean filter makes .FCStd files look empty (from git's pov)
- [ ] Users lock a .lockfile inside the `_FCStd` dir instead of the .FCStd file itself
- [ ] On Post-Checkout Hook
	- [ ] Update .FCStd files with uncompressed files (pull LFS files)
	- [ ] if the .lockfile is not locked by the user, the .FCStd file is set to readonly.
- [ ] On Pre-Commit Hook:
	- [ ] Extracts non-locked .FCStd files
	- [ ] Cancel commit if user doesn't have lock despite lock requirement being configured
- [ ] On Pre-Push Hook:
	- [ ] If locked dir changed, cancel push
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