### Workflow / ToDo List:
- [ ] `freecad-repo-init.sh`
	- [ ] Newly Clone Repo Support
		- [ ] Pull latest LFS files
		- [ ] If `.FCStd` file in repo has size 0 => Import data to file.
		- [ ] Trigger post-checkout after initialization.
			- [ ] .FCStd files to readonly if config requires it and remove readonly if config doesn't require it.

- [ ] Verify update (import) of .FCStd files with uncompressed files:
	- [ ] When?:
		- [ ] After cloning the repository
			- [ ] Update all files

- [ ] Verify `Readme.md` is correct