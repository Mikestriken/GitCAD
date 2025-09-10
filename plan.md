Is it better instead of doing filters put all the code in pre commit and post checkout hooks?

### Pre-commit:
1. Extract added zip files to a subdir the name of the zip file with `_zipFileExtension` appended to the folder name.
2. Add extracted contents, exclude added zip file.


### Problem:
1. Friend locks .FCStd file.
2. I clone the repo
3. * I need to update the .FCStd file with uncompressed data



Is there a way I can make git pretend that a file has no changes, but if I make another change to that file then it will note those changes, like a local commit that is never pushed.


### IDEA:
- [x] Git clean filter makes .FCStd files look empty (from git's pov)
- [ ] Users lock a .lockfile inside the `_FCStd` dir instead of the .FCStd file itself
- [ ] On Post-Checkout Hook
	- [ ] Update .FCStd files with uncompressed files 
	- [ ] if the .lockfile is not locked by the user, the .FCStd file is set to readonly.
- [ ] On Pre-Commit Hook:
	- [ ] Extracts non-locked .FCStd files
- [ ] On Pre-Push Hook:
	- [ ] If locked dir changed, cancel push
- [ ] To lock, use lock.sh path/to/file.FCStd | path/to/.lockfile:
	- [ ] Set git lfs lock appropriate _FCStd directory .lockfile
	- [ ] mark .FCStd file as writable
- [ ] To unlock, use unlock.sh path/to/file.FCStd | path/to/.lockfile:
	- [ ] Set git lfs unlock appropriate _FCStd directory .lockfile
	- [ ] mark .FCStd file as readonly


Locks:
 - Set file to readonly
 - Prevents changes from being pushed.