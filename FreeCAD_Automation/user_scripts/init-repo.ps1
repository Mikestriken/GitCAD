# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# PowerShell script to call init-repo using git bash
# Usage: .\FreeCAD_Automation\user_scripts\init-repo.ps1

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
#                                Verify and Retrieve Dependencies
# ==============================================================================================
# Check if inside a Git repository, ensure pwd is root of repository
$git_repo_root_path = git rev-parse --show-toplevel
if ($LASTEXITCODE -eq $SUCCESS) {
    Set-Location $git_repo_root_path
} else {
    Write-Error "Error: Cannot find git repo root dir. Make sure pwd is inside the git repo when calling this script."
    exit $FAIL
}


# ==============================================================================================
#                                  Call init-repo with Git Bash
# ==============================================================================================
& "FreeCAD_Automation\bash.ps1" "FreeCAD_Automation/user_scripts/init-repo"

exit $SUCCESS