# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Source this file to activate GitCAD workflow for this PowerShell session
# Usage: . .\FreeCAD_Automation\activate.ps1

# ==============================================================================================
#                                       Constant Globals
# ==============================================================================================
$SUCCESS = 0
$FAIL = 1
$TRUE = 0
$FALSE = 1
$GitCAD_Prompt = "(GitCAD)"

# ==============================================================================================
#                                 Register Deactivate Function
# ==============================================================================================
function deactivate_GitCAD {
    # Remove deactivate_GitCAD function
    Remove-Item Function:\deactivate_GitCAD -ErrorAction SilentlyContinue

    # Restore original PATH
    $path = $env:PATH -split ';'                 # Split PATH into parts
    $path = $path | Where-Object { $_ -ne $GIT_WRAPPER_PATH }  # Remove exact match
    $env:PATH = ($path -join ';')                # Rejoin PATH

    # Unset environment variables
    Remove-Item Env:\GITCAD_REPO_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:\REAL_GIT -ErrorAction SilentlyContinue
    Remove-Item Env:\GITCAD_ACTIVATED -ErrorAction SilentlyContinue
    Remove-Item Env:\GIT_WRAPPER_PATH -ErrorAction SilentlyContinue

    # Restore original prompt
    if ($PS1_ENVIRONMENT_BACKUP) {
        $function:prompt = $PS1_ENVIRONMENT_BACKUP
        Remove-Item Variable:\PS1_ENVIRONMENT_BACKUP -ErrorAction SilentlyContinue
    }

    Write-Host "GitCAD git wrapper deactivated"
}

# Register cleanup on exit (PowerShell equivalent of trap)
$global:GitCAD_ExitHandler = {
    deactivate_GitCAD
}
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $global:GitCAD_ExitHandler | Out-Null

# ==============================================================================================
#                                  Prevent Infinite Recursion
# ==============================================================================================
if ($env:GITCAD_ACTIVATED -eq $TRUE) {
    deactivate_GitCAD
}

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Check if script is dot-sourced (PowerShell equivalent of checking if sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Write-Error "Error: User did not dot-source this script correctly. Use: . .\FreeCAD_Automation\activate.ps1"
    exit $FAIL
}

# Check if inside a Git repository
try {
    $null = & git rev-parse --git-dir 2>$null
} catch {
    Write-Error "Error: Not inside a Git repository"
    exit $FAIL
}

# Store the repository root
$gitcad_repo_root = & git rev-parse --show-toplevel 2>$null
if ($env:OS -match "Windows") {
    # Convert drive letters if needed (similar to Bash logic)
    $env:GITCAD_REPO_ROOT = $gitcad_repo_root -replace '^([A-Za-z]):/', '/${1}/' | ForEach-Object { $_.ToLower() }
} else {
    $env:GITCAD_REPO_ROOT = $gitcad_repo_root
}

if (-not $env:GITCAD_REPO_ROOT) {
    Write-Error "Error: Not in a git repository"
    exit $FAIL
}

# ==============================================================================================
#         Add Wrapper Script to PATH Environment Variable, Ahead Of The Real `git.exe`
# ==============================================================================================
# Note: Used by FreeCAD_Automation/git to call the appropriate git executable.
$env:REAL_GIT = (Get-Command git).Source

# Add git wrapper script to PATH Environment variable
$env:GITCAD_ACTIVATED = $TRUE
$env:GIT_WRAPPER_PATH = "$env:GITCAD_REPO_ROOT/FreeCAD_Automation"
$env:PATH = "$env:GIT_WRAPPER_PATH;$env:PATH"

# Add $GitCAD_Prompt to PowerShell prompt
if ($function:prompt) {
    $global:PS1_ENVIRONMENT_BACKUP = $function:prompt
    $function:prompt = { "$GitCAD_Prompt " + (& $global:PS1_ENVIRONMENT_BACKUP) }
}

Write-Host "=============================================================================================="
Write-Host "GitCAD git wrapper activated for this PowerShell session"
Write-Host "Repository: $env:GITCAD_REPO_ROOT"
Write-Host ""
Write-Host "Use 'deactivate_GitCAD' to exit this environment."
Write-Host "=============================================================================================="