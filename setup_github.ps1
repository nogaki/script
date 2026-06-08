[CmdletBinding()]
param(
    [string]$KeyPath = (Join-Path $HOME ".ssh\id_ed25519")
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

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [securestring]$SecureString
    )

    $credential = [System.Management.Automation.PSCredential]::new("token", $SecureString)
    return $credential.GetNetworkCredential().Password
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if ($null -eq (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    throw "ssh-keygen not found. Install OpenSSH Client or Git for Windows, then rerun this script."
}

$sshDirectory = Split-Path -Parent $KeyPath
if (-not (Test-Path -LiteralPath $sshDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
}

$publicKeyPath = "$KeyPath.pub"
if (-not (Test-Path -LiteralPath $KeyPath -PathType Leaf)) {
    Invoke-ExternalCommand `
        -FilePath "ssh-keygen" `
        -ArgumentList @("-t", "ed25519", "-N", "", "-f", $KeyPath) `
        -FailureMessage "ssh-keygen failed"
} elseif (-not (Test-Path -LiteralPath $publicKeyPath -PathType Leaf)) {
    $publicKey = & ssh-keygen -y -f $KeyPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($publicKey)) {
        throw "Failed to derive public key from $KeyPath"
    }
    Set-Content -LiteralPath $publicKeyPath -Value $publicKey -Encoding ascii
}

$githubPublicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($githubPublicKey)) {
    throw "Public key is empty: $publicKeyPath"
}

$secureToken = Read-Host -Prompt "GitHub Personal Access Token" -AsSecureString
$githubToken = ConvertTo-PlainText -SecureString $secureToken
if ([string]::IsNullOrWhiteSpace($githubToken)) {
    throw "GitHub Personal Access Token is empty."
}

$headers = @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "token $githubToken"
}

$existingKeys = @(Invoke-RestMethod -Method Get -Uri "https://api.github.com/user/keys" -Headers $headers)
if ($existingKeys | Where-Object { $_.key -eq $githubPublicKey }) {
    Write-Host "Public key already registered with GitHub."
    return
}

$title = "$env:USERNAME@$env:COMPUTERNAME"
$body = @{
    title = $title
    key = $githubPublicKey
} | ConvertTo-Json -Compress

Invoke-RestMethod -Method Post -Uri "https://api.github.com/user/keys" -Headers $headers -ContentType "application/json" -Body $body | Out-Null

Write-Host
Write-Host "Public key registered successfully."
