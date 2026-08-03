<#
.SYNOPSIS
Generates public-facing release notes from meaningful conventional commits.
#>

[CmdletBinding()]
param(
    [Parameter()] [string] $RepoRoot,
    [Parameter()] [string] $Since,
    [Parameter()] [string] $Until = "HEAD",
    [Parameter()] [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $gitRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) { throw "Unable to determine repo root. Run inside a Git repository or pass -RepoRoot." }
    $RepoRoot = $gitRoot
}
$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
if ([string]::IsNullOrWhiteSpace($Since)) {
    $Since = & git -C $repoRootFull describe --tags --abbrev=0 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Since)) { $Since = "" }
}

$range = if ([string]::IsNullOrWhiteSpace($Since)) { $Until } else { "$Since..$Until" }
$subjects = @(& git -C $repoRootFull log --pretty=format:%s $range 2>$null)
if ($LASTEXITCODE -ne 0) { throw "git log failed for range: $range" }

$groups = [ordered] @{
    "Features" = @()
    "Fixes" = @()
    "Docs" = @()
    "Tests" = @()
    "Maintenance" = @()
}

foreach ($subject in $subjects) {
    if ([string]::IsNullOrWhiteSpace($subject)) { continue }
    if ($subject -match '(?i)\b(wip|checkpoint|temp|debug)\b') { continue }
    if ($subject -match '^(?<type>feat|fix|docs|test|tests|chore|refactor|perf|ci)(\([^)]+\))?:\s*(?<text>.+)$') {
        $text = $Matches['text'].Trim()
        $type = $Matches['type']
        if ($type -eq 'feat') {
            $groups['Features'] += $text
        }
        elseif ($type -eq 'fix') {
            $groups['Fixes'] += $text
        }
        elseif ($type -eq 'docs') {
            $groups['Docs'] += $text
        }
        elseif ($type -in @('test', 'tests')) {
            $groups['Tests'] += $text
        }
        else {
            $groups['Maintenance'] += $text
        }
    }
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Release Notes")
$lines.Add("")
$lines.Add("Range: $range")
$lines.Add("")
foreach ($groupName in $groups.Keys) {
    if ($groups[$groupName].Count -eq 0) { continue }
    $lines.Add("## $groupName")
    $lines.Add("")
    foreach ($item in $groups[$groupName]) { $lines.Add("- $item") }
    $lines.Add("")
}
if ($lines.Count -le 4) { $lines.Add("No conventional public-facing changes found for this range.") }

$text = $lines -join [Environment]::NewLine
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Output $text
}
else {
    $outputPathFull = [System.IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Path $outputPathFull -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $text | Set-Content -LiteralPath $outputPathFull -Encoding utf8
    Write-Host "Release changelog written: $outputPathFull"
}
