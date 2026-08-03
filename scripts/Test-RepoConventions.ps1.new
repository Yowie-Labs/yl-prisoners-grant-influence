<#
.SYNOPSIS
Checks repository polish conventions.

.DESCRIPTION
Warns about naming and structure issues by default. Use -Strict to fail when
convention findings should block a public release.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepoRoot,

    [Parameter()]
    [switch] $Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
$scriptsRoot = Join-Path -Path $repoRootFull -ChildPath "scripts"
$vendoredScriptsRoot = Join-Path -Path $repoRootFull -ChildPath "tools/ai-repo-workflow/scripts"
$findings = [System.Collections.Generic.List[string]]::new()
$allowedRootEntryPoints = @("repo-tools.ps1")
$allowedVendoredEntryPoints = @("patch.ps1", "snapshot.ps1", "Watch-Patches.ps1")
$allowedVendoredSupportScripts = @("PatchWorkflow.Common.ps1")
$preferredVerbs = @(
    "Get",
    "Set",
    "New",
    "Show",
    "Start",
    "Stop",
    "Install",
    "Invoke",
    "Test",
    "Move",
    "Publish",
    "Update",
    "Watch"
)

if (-not (Test-Path -LiteralPath $repoRootFull -PathType Container)) {
    throw "Repo root does not exist: $repoRootFull"
}

Get-ChildItem -LiteralPath $repoRootFull -File -Filter "*.ps1" |
    Sort-Object Name |
    ForEach-Object {
        if ($allowedRootEntryPoints -contains $_.Name) {
            return
        }

        $findings.Add("Root PowerShell script should be an approved entry-point exception or move under scripts/: $($_.Name)")
    }

if (Test-Path -LiteralPath $scriptsRoot -PathType Container) {
    Get-ChildItem -LiteralPath $scriptsRoot -File -Filter "*.ps1" |
        Sort-Object Name |
        ForEach-Object {
            if ($_.Name -in @("verify.ps1", "test.ps1")) {
                return
            }

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if ($baseName -cnotmatch "^(?<Verb>[A-Z][A-Za-z0-9]*)-(?<Noun>[A-Z][A-Za-z0-9]*)$") {
                $findings.Add("Script should normally be PascalCase Verb-Noun.ps1: scripts/$($_.Name)")
                return
            }

            $verb = $Matches["Verb"]
            if ($preferredVerbs -notcontains $verb) {
                $findings.Add("Script uses non-preferred PowerShell verb '$verb': scripts/$($_.Name)")
            }
        }
}

if (Test-Path -LiteralPath $vendoredScriptsRoot -PathType Container) {
    Get-ChildItem -LiteralPath $vendoredScriptsRoot -File -Filter "*.ps1" |
        Sort-Object Name |
        ForEach-Object {
            $relativePath = "tools/ai-repo-workflow/scripts/$($_.Name)"

            if ($allowedVendoredEntryPoints -contains $_.Name) {
                $wrapperText = Get-Content -LiteralPath $_.FullName -Raw
                if ($wrapperText -notmatch "Compatibility wrapper" -or $wrapperText -notmatch "@PSBoundParameters") {
                    $findings.Add("Vendored legacy entry point should be a thin compatibility wrapper: $relativePath")
                }

                return
            }

            if ($allowedVendoredSupportScripts -contains $_.Name) {
                return
            }

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if ($baseName -cnotmatch "^(?<Verb>[A-Z][A-Za-z0-9]*)-(?<Noun>[A-Z][A-Za-z0-9]*)$") {
                $findings.Add("Vendored workflow script should normally be PascalCase Verb-Noun.ps1: $relativePath")
                return
            }

            $verb = $Matches["Verb"]
            if ($preferredVerbs -notcontains $verb) {
                $findings.Add("Vendored workflow script uses non-preferred PowerShell verb '$verb': $relativePath")
            }
        }
}


$gitattributesPath = Join-Path -Path $repoRootFull -ChildPath ".gitattributes"
$requiredGitattributesRules = @(
    "* text=auto eol=lf",
    "*.ps1 text eol=lf",
    "*.psm1 text eol=lf",
    "*.psd1 text eol=lf",
    "*.md text eol=lf",
    "*.json text eol=lf",
    "*.jsonc text eol=lf",
    "*.yml text eol=lf",
    "*.yaml text eol=lf",
    "*.bat text eol=crlf",
    "*.cmd text eol=crlf",
    "*.zip binary",
    "*.png binary",
    "*.jpg binary",
    "*.pdf binary"
)

if (-not (Test-Path -LiteralPath $gitattributesPath -PathType Leaf)) {
    $findings.Add("Missing .gitattributes; repo line endings should be controlled by committed rules, not developer global Git settings.")
}
else {
    $gitattributesLines = @(Get-Content -LiteralPath $gitattributesPath | ForEach-Object { $_.Trim() })
    foreach ($rule in $requiredGitattributesRules) {
        if ($gitattributesLines -notcontains $rule) {
            $findings.Add(".gitattributes is missing expected line-ending/binary rule: $rule")
        }
    }
}

if ($findings.Count -gt 0) {
    $message = "Repo convention check found polish issues:$([Environment]::NewLine) - " + ($findings -join "$([Environment]::NewLine) - ")
    if ($Strict) {
        throw $message
    }

    Write-Warning $message
    Write-Host "Repo convention check completed with warnings."
}
else {
    Write-Host "Repo convention check passed."
}

Write-Host "Repo root: $repoRootFull"
