<#
.SYNOPSIS
Installs this repository's committed Git hooks.

.DESCRIPTION
Configures Git to use the repo-local .githooks directory. Commit-producing
hooks validate the effective local committer identity before Git creates or
rewrites commits. The pre-push hook validates the current identity and origin,
then runs scripts/verify.ps1 before a push leaves the machine.

The identity guard is optional and configured through ignored
repo-identity.local.jsonc. Personal names, emails, and private remotes must
stay in that local config, not in committed hook templates.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepoRoot,

    [Parameter()]
    [switch] $ConfigureIdentityGuard,

    [Parameter()]
    [string] $ExpectedUserName,

    [Parameter()]
    [string] $ExpectedUserEmail,

    [Parameter()]
    [string] $ExpectedOriginUrl,

    [Parameter()]
    [bool] $CheckCurrentGitConfig = $true,

    [Parameter()]
    [bool] $CheckEffectiveCommitterIdentity = $true,

    # Retained only so older callers fail safely instead of receiving an
    # unknown-parameter error. Push-history identity policing is retired.
    [Parameter(DontShow)]
    [Nullable[bool]] $CheckCommitsBeingPushed,

    [Parameter(DontShow)]
    [Nullable[bool]] $CheckCommitter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
$hookRelativePaths = @(
    ".githooks/pre-commit",
    ".githooks/pre-merge-commit",
    ".githooks/pre-applypatch",
    ".githooks/pre-rebase",
    ".githooks/pre-push"
)
$identityGuardScriptPath = Join-Path -Path $repoRootFull -ChildPath "scripts/Test-GitIdentityGuard.ps1"
$identityLocalPath = Join-Path -Path $repoRootFull -ChildPath "repo-identity.local.jsonc"

if (-not (Test-Path -LiteralPath $repoRootFull -PathType Container)) {
    throw "Repo root does not exist: $repoRootFull"
}

foreach ($hookRelativePath in $hookRelativePaths) {
    $hookPath = Join-Path -Path $repoRootFull -ChildPath $hookRelativePath
    if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) {
        throw "Missing hook template: $hookPath"
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $git) {
    throw "Git is required to install hooks."
}

& git -C $repoRootFull rev-parse --git-dir 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Not a Git repository: $repoRootFull"
}

if ($PSBoundParameters.ContainsKey("CheckCommitsBeingPushed") -or $PSBoundParameters.ContainsKey("CheckCommitter")) {
    Write-Warning "CheckCommitsBeingPushed and CheckCommitter are retired. The guard now validates commits when this checkout creates them and never rejects collaborator history."
}

if ($ConfigureIdentityGuard) {
    if ([string]::IsNullOrWhiteSpace($ExpectedUserName)) {
        $ExpectedUserName = (& git -C $repoRootFull config user.name 2>$null) -join "`n"
        $ExpectedUserName = $ExpectedUserName.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedUserEmail)) {
        $ExpectedUserEmail = (& git -C $repoRootFull config user.email 2>$null) -join "`n"
        $ExpectedUserEmail = $ExpectedUserEmail.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedOriginUrl)) {
        $ExpectedOriginUrl = (& git -C $repoRootFull remote get-url origin 2>$null) -join "`n"
        $ExpectedOriginUrl = $ExpectedOriginUrl.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedUserName) -and [string]::IsNullOrWhiteSpace($ExpectedUserEmail) -and [string]::IsNullOrWhiteSpace($ExpectedOriginUrl)) {
        throw "Identity guard was requested, but no expected user.name, user.email, or origin URL could be resolved."
    }

    $identityConfig = [ordered] @{
        expectedUserName = $ExpectedUserName
        expectedUserEmail = $ExpectedUserEmail
        expectedOriginUrl = $ExpectedOriginUrl
        checkCurrentGitConfig = $CheckCurrentGitConfig
        checkOriginUrl = -not [string]::IsNullOrWhiteSpace($ExpectedOriginUrl)
        checkEffectiveCommitterIdentity = $CheckEffectiveCommitterIdentity
    }

    $identityConfig |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $identityLocalPath -Encoding UTF8

    $gitignorePath = Join-Path -Path $repoRootFull -ChildPath ".gitignore"
    $gitignoreLine = "repo-identity.local.jsonc"
    $gitignoreLines = @()
    if (Test-Path -LiteralPath $gitignorePath -PathType Leaf) {
        $gitignoreLines = @(Get-Content -LiteralPath $gitignorePath)
    }

    if ($gitignoreLines -notcontains $gitignoreLine) {
        Add-Content -LiteralPath $gitignorePath -Value $gitignoreLine -Encoding UTF8
    }

    if (Test-Path -LiteralPath $identityGuardScriptPath -PathType Leaf) {
        & $identityGuardScriptPath -RepoRoot $repoRootFull -Context Manual
    }
}

& git -C $repoRootFull config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set core.hooksPath."
}

Write-Host "Git hooks installed."
Write-Host "Repo root: $repoRootFull"
Write-Host "core.hooksPath: .githooks"
Write-Host "Commit identity hooks: pre-commit, pre-merge-commit, pre-applypatch, pre-rebase"
Write-Host "Pre-push verification: identity/origin guard, then scripts/verify.ps1"
if (Test-Path -LiteralPath $identityLocalPath -PathType Leaf) {
    Write-Host "Git identity guard: repo-identity.local.jsonc"
}
else {
    Write-Host "Git identity guard: not configured; rerun with -ConfigureIdentityGuard to enable it"
}
Write-Host "Intentional bypass: use the relevant Git --no-verify option"
