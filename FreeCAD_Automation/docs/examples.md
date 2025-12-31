## GitCAD Usage Examples
### Cloning and Initializing Your Git Repository
1. Clone your repository.

2. Run the initialization script:
   *Note: Linux users will need to make the script executable with `chmod`*
   ```bash
   ./FreeCAD_Automation/user_scripts/init-repo
   ```
   *This will create a `FreeCAD_Automation/config.json` file.*

3. Configure the settings in newly added `FreeCAD_Automation/config.json` (from initialization script) as needed.  
   *Note 1: When you re-run the initialization script later in this installation guide this file will be added to `.gitignore` automatically.*  
   *Note 2: For documentation on what every json item does see the [Configuration Options](#configuration-options) section.*
   
   **Make sure to configure:**
    - `freecad-python-instance-path` -- Path to FreeCAD's Python executable.  
      *IE WINDOWS: `C:/Path/To/FreeCAD 1.0/bin/python.exe`*  
      -- **NOTE: MUST BE `/`, NOT `\`**  
      
      *IE LINUX: `/path/to/FreeCAD_Extracted_AppImage/usr/bin/python`*  
      -- **NOTE: LINUX USERS WILL NEED TO `FreeCAD.AppImage --appimage-extract`**  

4. Run the initialization script one last time to complete the initialization:
   ```bash
   ./FreeCAD_Automation/user_scripts/init-repo
   ```
   *The Script can be ran multiple times without error.*  
   *When the script asks "Do you want to import data from all uncompressed FreeCAD dirs?" in the "Synchronizing \`.FCStd\` Files" section, press `y`*

### Committing FreeCAD files (and their uncompressed directories)
1. `git fadd path/to/file.FCStd` your file.  
   *file contents will be extracted into configured uncompressed directory*  
   *The `.FCStd` file will be added and later committed as an empty text file.*

2. `git add path/to/file/uncompressed/dir` (`git fadd` works as well) the uncompressed directory.

3. `git commit -m "your commit message"` the uncompressed directory and empty (from git's POV) `.FCStd` file.

### Switching Branches / Checking Out Individual `.FCStd` Files
#### Switching Branches
**NOTE: DO NOT USE `git checkout branch_or_commit_hash -- path/to/file.FCStd` TO CHECKOUT INDIVIDUAL FILES FROM DIFFERENT COMMITS**  
- `git checkout branch_or_commit_hash` as usual.  
  *Everything will be handled automatically.*

#### Checking Out Individual Files
- `git fco branch_or_commit_hash path/to/file1.FCStd path/to/file2.FCStd ...`

#### __If used `git checkout COMMIT -- FILE [FILE ...]` instead on accident:__
The `.FCStd` file will be checked out as empty without importing from the uncompressed directory. In other words, nothing will happen, so simply run the `git fco` the command.  
*NOTE: `git fco` is ONLY for `.FCStd` files (and their dirs), any other type of file can be checked out manually using the normal `git checkout COMMIT -- FILE [FILE ...]`.*

### Committing/Pushing Changes
1. To lock a FreeCAD file for editing:  
   *Only mandatory if `require-lock-to-modify-FreeCAD-files` is configured to `true`.*
   ```bash
   git lock path/to/file.FCStd
   ```

2. Edit the file in FreeCAD.
   
3. Commit and push changes as usual. The hooks will handle compression and validation automatically.
   
4. To unlock after pushing changes:  
   *Only mandatory if `require-lock-to-modify-FreeCAD-files` is configured to `true`.*
   ```bash
   git unlock path/to/file.FCStd
   ```