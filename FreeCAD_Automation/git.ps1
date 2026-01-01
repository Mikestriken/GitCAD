# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# When bash wrapper script git is in the path, and 'git' is called via PowerShell terminal.
# This script translates the PowerShell call to a bash call.
# Usage: .\FreeCAD_Automation\git.ps1 [args...]

# ==============================================================================================
#                                  Call init-repo with Git Bash
# ==============================================================================================
& bash "$PSScriptRoot\git" @args 

exit $SUCCESS