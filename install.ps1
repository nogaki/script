[CmdletBinding()]
param(
    [string]$DotfilesDirectory = (Join-Path $HOME ".dotfiles"),
    [string]$Repository = "https://github.com/nogaki/dotfiles.git"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,
        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage with exit code $LASTEXITCODE"
    }
}

function Configure-GitCredentialManager {
    $gcm = Get-Command git-credential-manager -ErrorAction SilentlyContinue
    if ($null -eq $gcm) {
        Write-Warning "git-credential-manager not found. Install Git for Windows with Git Credential Manager enabled if GitHub authentication fails."
        return
    }

    Write-Host "Configuring Git Credential Manager..."
    Invoke-ExternalCommand `
        -FilePath $gcm.Source `
        -ArgumentList @("configure") `
        -FailureMessage "git-credential-manager configure failed"
}

function Get-PowerShellExecutable {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $windowsPowerShell) {
        return $windowsPowerShell.Source
    }

    $powerShell = Get-Command powershell -ErrorAction SilentlyContinue
    if ($null -ne $powerShell) {
        return $powerShell.Source
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwsh) {
        return $pwsh.Source
    }

    throw "PowerShell executable not found."
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Error: git not found. Install Git for Windows, then rerun this script."
}

Configure-GitCredentialManager

if (Test-Path -LiteralPath (Join-Path $DotfilesDirectory ".git") -PathType Container) {
    Write-Host "Updating existing dotfiles repository..."
    Invoke-ExternalCommand `
        -FilePath "git" `
        -ArgumentList @("-C", $DotfilesDirectory, "pull", "--rebase") `
        -FailureMessage "git pull failed"
} else {
    if (Test-Path -LiteralPath $DotfilesDirectory) {
        throw "$DotfilesDirectory already exists but is not a Git repository."
    }

    Write-Host "Cloning dotfiles repository..."
    Invoke-ExternalCommand `
        -FilePath "git" `
        -ArgumentList @("clone", $Repository, $DotfilesDirectory) `
        -FailureMessage "git clone failed"
}

$setupScript = Join-Path $DotfilesDirectory "setup.ps1"
if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    Write-Warning "setup.ps1 not found at $setupScript; skipping dotfiles setup."
    return
}

$powerShell = Get-PowerShellExecutable
Invoke-ExternalCommand `
    -FilePath $powerShell `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $setupScript) `
    -FailureMessage "dotfiles setup.ps1 failed"
