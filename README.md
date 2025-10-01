# FreeCAD Git Automation

## Description
This repository contains tools and scripts to automate the git workflow for committing uncompressed `.FCStd` files. Binary/other non-human-unreadable files such as `.brp` files are stored using git LFS (optionally they are compressed before storing them as LFS objects). Also supports locking `.FCStd` files to enable multi file collaboration.

### Key Features
- **Git Clean Filter**: Tricks git into thinking `.FCStd` files are empty and exports `git add`(ed) `.FCStd` files to their uncompressed directories.
  
- **Various Hooks**: Updates `.FCStd` files with uncompressed when git commands cause changes. Sets `.FCStd` files to readonly if not locked by the user. Prevents user from committing / pushing changes for `.FCStd` files (and their dirs) that they don't own the lock for.
  
- **Locking Mechanism**: Users use the git aliases `git lock path/to/file.FCStd` and `git unlock path/to/file.FCStd` lock a `.lockfile` inside the uncompressed directory instead of the `.FCStd` file itself.  
   **NOTE: THE COMMAND IS NOT `git lfs lock`/`git lfs unlock`**
   - Why lock `.lockfile` instead of `.FCStd` directly? 
      - *`.FCStd` files are filtered to appear empty to git to save space.  
      If the `.FCStd` files were directly locked you would be storing the entire `.FCStd` file in git-lfs,  
      which would somewhat defeat one of the secondary purpose of extracting the `.FCStd` files in the first place...  
      To efficiently store the diffable contents separate from the binary contents.*

## Installation
1. Dependencies
   - [Git](https://git-scm.com)
   - [Git-LFS](https://git-lfs.com)
  
2. Ensure `FreeCAD > Tools > Edit Parameters > Preferences > Document` has a boolean key `BackupPolicy` set to `false`.  
   - Techically only required if `require-lock-to-modify-FreeCAD-files` is configured to `true`.  
   - If the boolean key does not exist, create it.  
   - This prevents FreeCAD overwritting readonly (locked) files.  
   - Git is your new backup policy lol  

3. Download and extract release into the root of your FreeCAD project's git repository.

4. Run the initialization script:
   ```bash
   ./FreeCAD_Automation/init-repo.sh
   ```
   
4. Configure the settings in newly added `FreeCAD_Automation/config.json` (from initialization script) as needed.  
    Make sure to configure:
    - `freecad-python-instance-path` -- Path to FreeCAD's Python executable.  
      *IE: `C:/Path/To/FreeCAD 1.0/bin/python.exe`*
    
5. Test your configurations:
    - To see how your `.FCStd` files will export use:
      `"C:/Path/To/FreeCAD 1.0/bin/python.exe" "FreeCAD_Automation/FCStdFileTool.py" --CONFIG-FILE --export path/to/file.FCStd`  
      *Note: If using powershell prepend `&` to the above command. IE: `& "C:/Path/To/FreeCAD 1.0/bin/python.exe"`*

6. Run the initialization script one last time:
   ```bash
   ./FreeCAD_Automation/init-repo.sh
   ```
   *The Script can be ran multiple times without error (Assuming config wasn't changed).*  
   To see how to change `x` configuration post initialization see the [Changing Things](#changing-things) section.

7. Update your `.gitattributes` with LFS files you want to track.  
   __Recommendations if `compress-non-human-readable-FreeCAD-files` is disabled in config:__
   - `git lfs track "**/no_extension/*"` -- folder created by this script to track files without extension
   - `git lfs track "*.brp"`
   - `git lfs track "*.Map.*"`
   - `git lfs track "*.png"` -- thumbnail pictures

8. Verify `.gitattributes` is tracking files you want to track:  
   `git check-attr --all /path/to/file/to/check`

9. Update your `README.md` documentation for collaboration.  
   *Template available in [Template.md](template.md).*

## Updating
1. Backup `FreeCAD_Automation/config.json`.
   
2. Download and extract release into the root of your FreeCAD project's git repository.
   
3. Manually merge (if required) your backup of `FreeCAD_Automation/config.json` into the new (updated?) `FreeCAD_Automation/config.json`.
   
4. Run the initialization script:
   ```bash
   ./FreeCAD_Automation/init-repo.sh
   ```
   *The Script can be ran multiple times without error (Assuming config wasn't changed).*  
   To see how to change `x` configuration post initialization see the [Changing Things](#changing-things) section.

## Quick Guide
### Committing FreeCAD files (and their uncompressed directories)
1. `git add` your file.  
   *`*.FCStd` file filter will extract the contents*

2. `git add` the uncompressed directory.

3. `git commit` the uncompressed directory and empty (from git's POV) `.FCStd` file.

### Cloning and Initializing Your Git Repository
1. Clone your repository.
   
2. Run `./FreeCAD_Automation/init-repo.sh`

4. Press `y` to `Do you want to import data from all uncompressed FreeCAD dirs to their respective '.FCStd' files?`

### Switching Branches (Checking Out Files) <!-- ToDo: file checkout + what if didn't use alias -->
1. `git checkout` branches/files as usual.  
    *Everything will be handled automatically.*

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

## [Git Aliases](FreeCAD_Automation/added-aliases.md)
It is important to read the linked alias documentation. These aliases help ensure the `.FCStd` files in your working directory are correctly synced with their corresponding uncompressed directories.

They are also important for manually resynchronizing them in case you forgot to use an alias.

### IMPORTANT ALIASES / TL;DR:
1. Use `git freset` instead of `git reset`
2. Use `git fstash` instead of `git stash`
3. Use `git fco COMMIT FILE [FILE ...]` instead of `git checkout COMMIT -- FILE [FILE ...]`  
   *Note: **ONLY** for `.FCStd` files (and their dirs), any other type of file can be checked out manually using the normal `git checkout COMMIT -- FILE [FILE ...]`.*
4. `git lock path/to/file.FCStd` / `git unlock path/to/file.FCStd` / `git locks` -- Do what you expect

### If you forgot to use one of the above commands instead:
1. Use `git fimport` to manually import the contents of a dir to its `.FCStd` file.
2. Use `git fcmod` to make git think your `.FCStd` file is empty, without exporting it.

## Changing Things
Some configurations in `FreeCAD_Automation/config.json` cannot be changed by simply changing its value in the JSON file. After you have already initialized the repository with the `init-repo.sh` script.

This section will cover how you can change certain configurations, post-initialization.

If not mentioned here, you can just assume that changing the configuration value in the JSON is all that is required.

### Changing `uncompressed-directory-structure`
If you change any value inside the `uncompressed-directory-structure` JSON key, you will need to follow this checklist to properly propagate that configuration change to your repository.
- [ ] `git lock *.FCStd` to get edit permissions.

- [ ] `git mv path/to/old/dir path/to/new/dir` all uncompressed FCStd file folders.
  
- [ ] Ensure `git status` shows directories as `renamed`, **NOT** `deleted` and `added`.
  
- [ ] Change the values of the `uncompressed-directory-structure` JSON key to match.

- [ ] `git add FreeCAD_Automation/config.json` (**DO NOT `git add .`**)

- [ ] `git commit` changes.

## Configuration Options
```jsonc
{
    // Location of the python interpreter bundled with your FreeCAD installation.
    // Linux users may need to unpack their app image of FreeCAD to get access to this.
    // NOTE: Make sure to use `/` instead of `\` (( probably, I haven't tested TBH ))
    "freecad-python-instance-path": "C:/path/to/FreeCAD 1.0/bin/python.exe",

    // ------------------------------------------------------------------
    
    // If true, Post-Checkout will set all FreeCAD files to readonly 
    // (unless you have the lock for that file)
    
    // TL;DR: It simulates the --lockable git lfs attribute.

    // If you change this post-initialization, 
    // make sure to re-run the `init-repo.sh` script.
    "require-lock-to-modify-FreeCAD-files": true,

    // ------------------------------------------------------------------
    
    // If true, thumbnails will be exported and imported to/from the .FCStd file.
    "include-thumbnails": true,

    // ------------------------------------------------------------------
    
    // Configures the name and location of the uncompressed .FCStd file directory.

    // Current config exports .FCStd file to:
    //      /path/to/file.FCStd -> /path/to/compressed/FCStd_file_FCStd/

    // To change this post initialization follow instructions in `## Changing Things`
    "uncompressed-directory-structure": {
        "uncompressed-directory-suffix": "_FCStd",
        "uncompressed-directory-prefix": "FCStd_",
        "subdirectory": {
            "put-uncompressed-directory-in-subdirectory": true,
            "subdirectory-name": "uncompressed"
        }
    },
            
    // ------------------------------------------------------------------
                
    "compress-non-human-readable-FreeCAD-files": {
        // If enabled, after exporting the .FCStd file to a directory,
        // files/folders with names matching strings listed
        // will be further compressed to save git LFS space.

        // Using template patterns and compression level 9 reduces FreeCAD BIMExample.FCStd's
        // created folder by 67.98%.

        // Enabling this option makes exporting .FCStd files take considerably longer on max compression level.
        // If too unbearable and you don't mind a reduced compression, reduce the compression-level property below.
        "enabled": true,
        
        // --------------------------------------------------------------
            
        // File/folder names to match
        // Note 1: "*/no_extension" is a directory all files without extension are added to. 
        //         This is for convenience of being able to use git LFS to track specifically files without extension.
        
        // Note 2: Pattern matching uses PurePosixPath().match(). See documentation here: https://docs.python.org/3/library/pathlib.html#pathlib.PurePath.match
        //         FreeCAD's python is version Python 3.11.13 FYI (hence not using full_match())

        // Note 3: My template pattern matching is also compressing certain text files. This is because they are written in a way that only
        //         a computer / algorithm could understand. Diffing them has no value in my opinion.
        //         Basically the only thing left uncompressed with this template is Document.xml and GuiDocument.xml.
        "files-to-compress": ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"],
        
        // --------------------------------------------------------------
        
        // Max size of compressed archive.
        // If value is exceeded an additional zip file will be created.
        
        // See the following for GitHub's LFS limitations:
            // https://docs.github.com/en/billing/concepts/product-billing/git-lfs#free-use-of-git-lfs
            // https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage#about-git-large-file-storage
        "max-compressed-file-size-gigabyte": 2,
        
        // --------------------------------------------------------------

        // level of compression 0-9
        // zlib documentation: https://docs.python.org/3/library/zlib.html#zlib.compress
        "compression-level": 9,
        
        // --------------------------------------------------------------

        // Prefix for created zip files.
        // IE: Current setting will create `compressed_binaries_{i}.zip` where {i} is an iterator for all created zip files (that exceed `max-compressed-file-size-gigabyte`).
        "zip-file-prefix": "compressed_binaries_"
    }
}
```