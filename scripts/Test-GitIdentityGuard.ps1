<#
.SYNOPSIS
Checks this checkout's configured and effective Git identity.

.DESCRIPTION
Reads an ignored repo-identity.local.jsonc file, then validates the current
repo Git identity. Commit-time hooks validate the effective committer identity
that Git will use on this machine. The pre-push hook validates the current
identity and origin URL before anything leaves the machine.

The guard deliberately does not scan commit history. Commits authored or
committed by collaborators, GitHub, or automation remain valid repository
history and must not prevent this checkout from pushing.

If no local identity config exists, the check returns successfully so shared
repos do not break for collaborators by default.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepoRoot,

    [Parameter()]
    [string] $ConfigPath,

    [Parameter()]
    [ValidateSet("Manual", "Commit", "PrePush")]
    [string] $Context = "Manual",

    # Backward-compatible alias for older pre-push hook templates.
    [Parameter()]
    [switch] $ReadPrePushInput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($ReadPrePushInput) {
    $Context = "PrePush"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $gitRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
        $RepoRoot = $gitRoot
    }
    else {
        $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    }
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path -Path $repoRootFull -ChildPath "repo-identity.local.jsonc"
}

$configPathFull = [System.IO.Path]::GetFullPath($ConfigPath)

function Read-GitIdentityJsonc {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $text = Get-Content -LiteralPath $Path -Raw
    $text = [regex]::Replace($text, "(?s)/\*.*?\*/", "")
    $text = [regex]::Replace($text, "(?m)//.*$", "")

    return $text | ConvertFrom-Json
}

function Get-GitIdentityBoolean {
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [bool] $DefaultValue
    )

    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return [bool] $property.Value
}

function Get-GitIdentityString {
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ""
    }

    return [string] $property.Value
}

function Invoke-GitIdentityGit {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [Parameter()]
        [switch] $AllowFailure
    )

    $output = & git -C $repoRootFull @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed."
    }

    if ($null -eq $output) {
        return ""
    }

    return ($output -join "`n").Trim()
}

function Get-EffectiveGitCommitterIdentity {
    $identityText = Invoke-GitIdentityGit -Arguments @("var", "GIT_COMMITTER_IDENT") -AllowFailure
    if ([string]::IsNullOrWhiteSpace($identityText)) {
        throw "Git could not resolve an effective committer identity. Configure git user.name and user.email for this repository."
    }

    $match = [regex]::Match($identityText, '^(?<name>.*) <(?<email>[^>]*)> \d+ [+-]\d{4}$')
    if (-not $match.Success) {
        throw "Git returned an unrecognized GIT_COMMITTER_IDENT value: '$identityText'."
    }

    return [pscustomobject] @{
        Name = $match.Groups["name"].Value.Trim()
        Email = $match.Groups["email"].Value.Trim()
    }
}

if (-not (Test-Path -LiteralPath $configPathFull -PathType Leaf)) {
    Write-Host "Git identity guard: no repo-identity.local.jsonc configured; skipping identity guard."
    return
}

$config = Read-GitIdentityJsonc -Path $configPathFull

$expectedUserName = Get-GitIdentityString -Config $config -Name "expectedUserName"
$expectedUserEmail = Get-GitIdentityString -Config $config -Name "expectedUserEmail"
$expectedOriginUrl = Get-GitIdentityString -Config $config -Name "expectedOriginUrl"
$checkCurrentGitConfig = Get-GitIdentityBoolean -Config $config -Name "checkCurrentGitConfig" -DefaultValue $true
$checkOriginUrl = Get-GitIdentityBoolean -Config $config -Name "checkOriginUrl" -DefaultValue (-not [string]::IsNullOrWhiteSpace($expectedOriginUrl))
$checkEffectiveCommitterIdentity = Get-GitIdentityBoolean -Config $config -Name "checkEffectiveCommitterIdentity" -DefaultValue $true

$failures = [System.Collections.Generic.List[string]]::new()

if ($checkCurrentGitConfig) {
    if (-not [string]::IsNullOrWhiteSpace($expectedUserName)) {
        $actualUserName = Invoke-GitIdentityGit -Arguments @("config", "user.name") -AllowFailure
        if ($actualUserName -ne $expectedUserName) {
            $failures.Add("Wrong git user.name: '$actualUserName'. Expected: '$expectedUserName'.") | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($expectedUserEmail)) {
        $actualUserEmail = Invoke-GitIdentityGit -Arguments @("config", "user.email") -AllowFailure
        if ($actualUserEmail -ne $expectedUserEmail) {
            $failures.Add("Wrong git user.email: '$actualUserEmail'. Expected: '$expectedUserEmail'.") | Out-Null
        }
    }
}

if ($checkEffectiveCommitterIdentity -and (-not [string]::IsNullOrWhiteSpace($expectedUserName) -or -not [string]::IsNullOrWhiteSpace($expectedUserEmail))) {
    try {
        $effectiveCommitter = Get-EffectiveGitCommitterIdentity

        if (-not [string]::IsNullOrWhiteSpace($expectedUserName) -and $effectiveCommitter.Name -ne $expectedUserName) {
            $failures.Add("Wrong effective Git committer name: '$($effectiveCommitter.Name)'. Expected: '$expectedUserName'.") | Out-Null
        }

        if (-not [string]::IsNullOrWhiteSpace($expectedUserEmail) -and $effectiveCommitter.Email -ne $expectedUserEmail) {
            $failures.Add("Wrong effective Git committer email: '$($effectiveCommitter.Email)'. Expected: '$expectedUserEmail'.") | Out-Null
        }
    }
    catch {
        $failures.Add($_.Exception.Message) | Out-Null
    }
}

if ($Context -ne "Commit" -and $checkOriginUrl -and -not [string]::IsNullOrWhiteSpace($expectedOriginUrl)) {
    $actualOriginUrl = Invoke-GitIdentityGit -Arguments @("remote", "get-url", "origin") -AllowFailure
    if ($actualOriginUrl -ne $expectedOriginUrl) {
        $failures.Add("Wrong origin remote: '$actualOriginUrl'. Expected: '$expectedOriginUrl'.") | Out-Null
    }
}

if ($failures.Count -gt 0) {
    $message = "Git identity guard failed:`n - " + ($failures -join "`n - ")
    throw $message
}

Write-Host "Git identity guard passed for $Context context."
