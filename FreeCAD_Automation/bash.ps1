# ==============================================================================================
#                                       Script Overview
# ==============================================================================================
# PowerShell script to call bash scripts with proper PATH setup
# Usage: .\FreeCAD_Automation\bash.ps1 [args...]

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
#                                       Get Git Bash Path
# ==============================================================================================
$whereGit = where.exe git 2>$null
$gitExe = $whereGit | Select-Object -First 1

if (-not $gitExe) {
    Write-Host "Error: Git not found in PATH. Please ensure Git for Windows is installed."
    exit $FAIL
}

$gitDir = Split-Path $gitExe
$gitBash = $null
while ($gitDir -and -not $gitBash) {
    $candidate = Join-Path $gitDir "usr\bin\bash.exe"
    if (Test-Path $candidate) {
        $gitBash = $candidate
    } else {
        $gitDir = Split-Path $gitDir
    }
}

if (-not (Test-Path $gitBash)) {
    Write-Host "Error: Git bash not found at expected location. Please ensure during the installation of git, that git bash for Windows was also installed."
    exit $FAIL
}

# ==============================================================================================
#                                        Export Bash PATH                                       
# ==============================================================================================
if (-not $env:BASH_PATH_ADDED) {
    $env:PATH = "/usr/bin;$env:PATH" # Without this bash tools like grep would error with 'grep: command not found'
    $env:BASH_PATH_ADDED = $true
}

# ==============================================================================================
#                                  Call script with Git Bash
# ==============================================================================================
& $gitBash @args

exit $SUCCESS