# FreeCAD Git Automation

## Description
This repository contains tools and scripts to automate the Git workflow for committing uncompressed `.FCStd` files. Binary/other non-human-unreadable files such as `.brp` files are stored using git LFS (optionally they are compressed before storing them as LFS objects).

### Key Features
- **Git Clean Filter**: Treats `.FCStd` files as empty in Git to avoid large binary commits.
  
- **Post-Checkout Hook**: Updates `.FCStd` files with uncompressed content and sets the `.FCStd` file to readonly if not locked by the user.
  
- **Pre-Commit Hook**: Extracts non-locked `.FCStd` files and adds them to the commit.
  
- **Pre-Push Hook**: Cancels push if commits being pushed contains modifications to directories the user don't have the lock for.
  
- **Locking Mechanism**: Users use the git aliases `git lock path/to/file.FCStd` and `git unlock path/to/file.FCStd` lock a `.lockfile` inside the uncompressed directory instead of the `.FCStd` file itself.
  
- ~~**Lock/Unlock Scripts**: `lock.sh` and `unlock.sh` for managing file locks and permissions.~~

## Installation
1. Dependencies
   - [Git-LFS](https://git-lfs.com)
  
2. Ensure `FreeCAD > Tools > Edit Parameters > Preferences > Document` has a boolean key `BackupPolicy` set to `false`.  
   - Techically only required if `require-lock-to-modify-FreeCAD-files` is configured to `true`.  
   - If the boolean key does not exist, create it.  
   - This prevents FreeCAD overwritting readonly (locked) files.  
   - Git is your new backup policy lol  

3. Download and extract this repository into the root of your FreeCAD project's git repository.
   
4. Configure the settings in `FreeCAD_Automation/git-freecad-config.json` as needed.  
    Make sure to configure:
    - `freecad-python-instance-path` -- Path to FreeCAD's Python executable.  
        Example: `C:/Path/To/FreeCAD 1.0/bin/python.exe`
    
5. ****Test your configurations on python script:

6. Run the initialization script:
   ```bash
   ./FreeCAD_Automation/freecad-repo-init.sh
   ```
   *The Script can be ran multiple times without error.*  
   To see how to change `x` configuration post initialization see the [Changing Things](#changing-things) section.

7. Update your `.gitattributes` with LFS files you want to track.  
   - `git lfs track "*.zip"`
   - `git lfs track "**/no_extension/*"` -- folder created by this script to track files without extension
   - `git lfs track "*.brp"`
   - `git lfs track "*.Map.*"`
   - `git lfs track "*.png"` -- thumbnail pictures

8. Verify `.gitattributes` tracking files you want to track:  
   `git check-attr --all /path/to/file/to/check`

9.  Update your `README.md` documentation for collaboration.  
   *Template available in [Template Readme](#template-readmemd).*

## Updating
1. Backup `FreeCAD_Automation/git-freecad-config.json`.
   
2. Download, extract and overwrite this repository into the root of your FreeCAD project's git repository.
   
3. Manually merge (if required) your backup of `FreeCAD_Automation/git-freecad-config.json` into the new (updated?) `FreeCAD_Automation/git-freecad-config.json`.
   
4. Run the initialization script:
   ```bash
   ./FreeCAD_Automation/freecad-repo-init.sh
   ```
   *The Script can be ran multiple times without error.*  
   To see how to change `x` configuration post initialization see the [Changing Things](#changing-things) section.

## Quick Guide
### Cloning and Initializing Your Git Repository
1. Clone your repository.
   
2. Run `./FreeCAD_Automation/freecad-repo-init.sh`

### Switching Branches (Checking Out Files)
1. `git checkout` branches/files as usual.  
    *Everything will be handled automatically.*

### Pushing Changes
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

## Changing Things
Some configurations in `FreeCAD_Automation/git-freecad-config.json` cannot be changed by simply changing its value in the JSON file. After you have already initialized the repository with the `freecad-repo-init.sh` script.

This section will cover how you can change certain configurations, post-initialization.

If not mentioned here, you can just assume that changing the configuration value in the JSON is all that is required.

### Changing `uncompressed-directory-structure`
If you change any value inside the `uncompressed-directory-structure` JSON key, you will need to follow this checklist to properly propagate that configuration change to your repository.
- [ ] `git mv path/to/old/dir path/to/new/dir` all uncompressed FCStd file folders.
  
- [ ] Ensure `git status` shows directories as `renamed`, **NOT** `deleted` and `added`.
  
- [ ] Change the values of the `uncompressed-directory-structure` JSON key to match.

- [ ] `git add FreeCAD_Automation/git-freecad-config.json` (**DO NOT `git add .`**)

- [ ] `git commit` changes.

### Changing `require-lock-to-modify-FreeCAD-files`
If you change this value, you will need to re-run the `freecad-repo-init.sh` script.

## Configuration Options
```json
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
    // make sure to re-run the `freecad-repo-init.sh` script.
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
        "enabled": true,
        
        // --------------------------------------------------------------
            
        // File/folder names to match
        // Note 1: "*/no_extension" is a directory all files without extension are added to. 
        //         This is for convenience of being able to use git LFS to track specifically files without extension.
        
        // ****************Note 2: Pattern matching uses fnmatch. See documentation here: https://docs.python.org/3/library/fnmatch.html
        "files-to-compress": ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*"],
        
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

## Flowchart
A Mermaid diagram illustrating the Git workflow process will be added here in a future update.

## Template README.MD
```md

```