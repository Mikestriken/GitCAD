# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# PowerShell script to call init-repo using git bash
# Usage: .\FreeCAD_Automation\user_scripts\init-repo.ps1

# ==============================================================================================
#                                  Call init-repo with Git Bash
# ==============================================================================================
& bash "FreeCAD_Automation/user_scripts/init-repo" @args 

exit $SUCCESS