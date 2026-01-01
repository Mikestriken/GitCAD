# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# When bash wrapper script git is in the path, and 'git' is called via PowerShell terminal.
# This script translates the PowerShell call to a bash call.
# Usage: .\FreeCAD_Automation\git.ps1 [args...]

# ==============================================================================================
#                                       Constant Globals
# ==============================================================================================
if (-not $global:BASH_GLOBALS_EXIST) {
    New-Variable -Name SUCCESS -Description "Bash exit success value" -Scope Global -Option ReadOnly -Visibility Public -Value 0
    New-Variable -Name FAIL -Description "Bash exit failure value" -Scope Global -Option ReadOnly -Visibility Public -Value 1
    New-Variable -Name BASH_TRUE -Description "Bash true value" -Scope Global -Option ReadOnly -Visibility Public -Value 0
    New-Variable -Name BASH_FALSE -Description "Bash false value" -Scope Global -Option ReadOnly -Visibility Public -Value 1
    $global:BASH_GLOBALS_EXIST = $true
}

# ==============================================================================================
#                                  Call init-repo with Git Bash
# ==============================================================================================
& "$PSScriptRoot\bash.ps1" "$PSScriptRoot\git" @args 

exit $SUCCESS