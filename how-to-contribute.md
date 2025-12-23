## Installation
### Ubuntu Linux WSL Install
1. Install WSL  
    -- `wsl --install`
2. Reboot
3. Sign in and create your Ubuntu Account  
    -- `wsl`
4. Update Ubuntu  
    -- `sudo apt update && sudo apt upgrade -y`
5. Download the FreeCAD `.AppImage` from the [FreeCAD website](https://www.freecad.org/downloads.php)
6. Extract the app image using  
    -- `/path/to/FreeCAD.AppImage --appimage-extract`
7. Rename the extracted app image:  
    -- `mv ./squashfs-root/ ./FreeCAD/`
8. Remove the `.AppImage` file  
    -- `rm /path/to/FreeCAD.AppImage`
9.  Test run FreeCAD (should be no problems)  
    -- `./FreeCAD/AppRun`
10. install git-lfs if needed  
    -- `sudo apt install git-lfs`
11. fork and clone the repo  
    -- Copy the ssh link instead of the https link on GitHUB under the green clone button.
12. Run the init repo script for GitCAD twice (and specify the FreeCAD python file in the config), as per the install instructions in the [README](README.md) file.  
    -- `./FreeCAD_Automation/init-repo.sh`
13. Get a FreeCAD `.FCStd` file to test xdg-open on later  
    -- `git checkout test_binaries -- ./FreeCAD_Automation/tests/AssemblyExample.FCStd`
14. install xdg-open (used to open `.FCStd` files via CLI)  
    -- `sudo apt install xdg-utils desktop-file-utils shared-mime-info`
15. Configure xdg-open to work for FreeCAD using a `.desktop` file and MIME  `.xml` type file
    1.  Create a `freecad.xml` MIME type file in `/usr/share/mime/packages/freecad.xml`  
        ```xml
        <?xml version="1.0" encoding="UTF-8"?>
        <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
            <mime-type type="application/x-freecad">
                <comment>FreeCAD Document</comment>
                <glob pattern="*.FCStd"/>
            </mime-type>
        </mime-info>
        ```
    2. Create a `freecad.desktop` file in `/usr/share/applications/freecad.desktop`
        ```desktop
        [Desktop Entry]
        Type=Application
        Name=FreeCAD
        GenericName=3D CAD Modeler
        Comment=Parametric 3D CAD Modeler
        Exec=/path/to/FreeCAD/AppRun %F
        Icon=/path/to/FreeCAD/freecad.png
        Terminal=false
        Categories=Engineering;Science;
        MimeType=application/x-freecad;
        StartupWMClass=FreeCAD
        StartupNotify=true
        ```
    3. Update MIME types  
        -- `sudo update-mime-database /usr/share/mime`
    4. Update desktop databases  
        -- `sudo update-desktop-database`
    5. Validate the `.desktop` file (if nothing is printed, everything is good)  
        -- `desktop-file-validate /usr/share/applications/freecad.desktop` 
    6. Try opening the `AssemblyExample.FCStd` file  
        -- `xdg-open ./FreeCAD_Automation/tests/AssemblyExample.FCStd`
16. Setup ssh for git credentials -- Ask Google or ChatGPT
17. Run `./FreeCAD_Automation/tests/run_repo_tests.sh --sandbox`
18. If the terminal says `` then your all clear!
### Windows Install