# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# Source this file to activate GitCAD workflow for this PowerShell session
# Usage: .\FreeCAD_Automation\user_scripts\activate.ps1

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

if (-not $global:GITCAD_GLOBALS_EXIST) {
    New-Variable -Name GitCAD_Prompt -Description "GitCAD activation prompt prefix" -Scope Global -Option ReadOnly -Visibility Public -Value "(GitCAD)"
    $global:GITCAD_GLOBALS_EXIST = $true
}

# ==============================================================================================
#                                 Register Deactivate Function
# ==============================================================================================
function global:deactivate_GitCAD ([switch]$Keep_Function_Definition) {

    # Remove deactivate_GitCAD function
    if (-not $Keep_Function_Definition) {
        Remove-Item Function:deactivate_GitCAD -ErrorAction SilentlyContinue
    }

    # Restore original PATH
    $path = $env:PATH -split ';'                                    # Split PATH into parts
    $path = $path | Where-Object { $_ -ne $env:GIT_WRAPPER_PATH }   # Remove exact match
    $env:PATH = ($path -join ';')                                   # Rejoin PATH

    # Unset environment variables
    Remove-Item Env:\GITCAD_REPO_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:\REAL_GIT -ErrorAction SilentlyContinue
    Remove-Item Env:\GITCAD_ACTIVATED -ErrorAction SilentlyContinue
    Remove-Item Env:\GIT_WRAPPER_PATH -ErrorAction SilentlyContinue

    # The prior prompt:
    if (Test-Path -Path Function:original_prompt) {
        Copy-Item -Path Function:original_prompt -Destination Function:prompt
        Remove-Item -Path Function:original_prompt
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
if ($env:GITCAD_ACTIVATED -eq $BASH_TRUE) {
    deactivate_GitCAD -Keep_Function_Definition
}

# ==============================================================================================
#                               Verify and Retrieve Dependencies
# ==============================================================================================
# Check if inside a Git repository
try {
    $null = & git rev-parse --git-dir 2>$null
} catch {
    Write-Error "Error: Not inside a Git repository"
    exit $FAIL
}

# Store the repository root
$gitcad_repo_root = & git rev-parse --show-toplevel 2>$null
$env:GITCAD_REPO_ROOT = $gitcad_repo_root -replace '/', '\'

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
$env:GITCAD_ACTIVATED = $BASH_TRUE
$env:GIT_WRAPPER_PATH = "$env:GITCAD_REPO_ROOT\FreeCAD_Automation"
$env:PATH = "$env:GIT_WRAPPER_PATH;$env:PATH"

# Set the prompt to include the env name
# Make sure original_prompt is global
function global:original_prompt { "" }
Copy-Item -Path function:prompt -Destination function:original_prompt

function global:prompt {
    Write-Host -NoNewline -ForegroundColor Green "$GitCAD_Prompt "
    original_prompt
}

Write-Host "=============================================================================================="
Write-Host "GitCAD git wrapper activated for this PowerShell session"
Write-Host "Repository: $env:GITCAD_REPO_ROOT"
Write-Host ""
Write-Host "Use 'deactivate_GitCAD' to exit this environment."
Write-Host "=============================================================================================="