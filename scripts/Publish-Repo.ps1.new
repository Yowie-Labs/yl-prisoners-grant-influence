<#
.SYNOPSIS
Safely exports allowlisted current files from a private repo to a public/client repo.

.DESCRIPTION
This command treats private Git history as untrusted. It copies only allowlisted
current working-tree files and never copies .git. By default it is a dry run.
Use -Execute to write files. Existing public files are written as .new review
copies unless -Force is passed.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()] [string] $PrivateRepoRoot,
    [Parameter(Mandatory)] [string] $PublicRepoRoot,
    [Parameter()] [string[]] $IncludePath = @("README.md", "AGENTS.md", ".gitignore", ".gitattributes", "docs", "src", "scripts", "tests", "examples", "templates", "tools/ai-repo-workflow", ".github/workflows", "repo-hygiene.example.jsonc", "repo-tools.ps1"),
    [Parameter()] [switch] $Execute,
    [Parameter()] [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PublishRelativePath {
    param([string] $RootPath, [string] $FullPath)
    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $fullPathNormalized = [System.IO.Path]::GetFullPath($FullPath)
    $rootUri = [System.Uri]::new($rootFullPath + [System.IO.Path]::DirectorySeparatorChar)
    $fullUri = [System.Uri]::new($fullPathNormalized)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fullUri).ToString()).Replace('/', '/')
}

function Test-PublishExcludedPath {
    param([string] $RelativePath)
    $normalized = $RelativePath.Replace('\\', '/').TrimStart('/')
    if ($normalized -eq ".git" -or $normalized.StartsWith(".git/", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($normalized -match '(^|/)(downloads|snapshots|logs)/') { return $true }
    if ($normalized -match '(^|/)repo-hygiene\.local\.jsonc$') { return $true }
    if ($normalized -match '\.code-workspace$') { return $true }
    if ($normalized.StartsWith(".vscode/", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($normalized -match '\.(zip|7z|tar|gz|tgz|tmp|bak|log)$') { return $true }
    if ($normalized.EndsWith(".new", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

if ([string]::IsNullOrWhiteSpace($PrivateRepoRoot)) {
    $gitRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) { throw "Unable to determine private repo root. Run inside the private repo or pass -PrivateRepoRoot." }
    $PrivateRepoRoot = $gitRoot
}
$privateRootFull = [System.IO.Path]::GetFullPath($PrivateRepoRoot)
$publicRootFull = [System.IO.Path]::GetFullPath($PublicRepoRoot)
if (-not (Test-Path -LiteralPath $privateRootFull -PathType Container)) { throw "Private repo root does not exist: $privateRootFull" }
if (-not (Test-Path -LiteralPath $publicRootFull -PathType Container)) { throw "Public repo root does not exist: $publicRootFull" }

$filesToCopy = [System.Collections.Generic.List[object]]::new()
foreach ($include in $IncludePath) {
    $sourcePath = Join-Path -Path $privateRootFull -ChildPath $include
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        $relative = Get-PublishRelativePath -RootPath $privateRootFull -FullPath $sourcePath
        if (-not (Test-PublishExcludedPath -RelativePath $relative)) { $filesToCopy.Add([pscustomobject] @{ Source = $sourcePath; Relative = $relative }) }
    }
    elseif (Test-Path -LiteralPath $sourcePath -PathType Container) {
        Get-ChildItem -LiteralPath $sourcePath -File -Recurse -Force | ForEach-Object {
            $relative = Get-PublishRelativePath -RootPath $privateRootFull -FullPath $_.FullName
            if (-not (Test-PublishExcludedPath -RelativePath $relative)) { $filesToCopy.Add([pscustomobject] @{ Source = $_.FullName; Relative = $relative }) }
        }
    }
}

Write-Host "Clean export plan"
[pscustomobject] @{ PrivateRepoRoot = $privateRootFull; PublicRepoRoot = $publicRootFull; FileCount = $filesToCopy.Count; Execute = [bool] $Execute; Force = [bool] $Force } | Format-List

if (-not $Execute) {
    Write-Host "Dry run only. Re-run with -Execute to write files. Existing differing files will become .new review files unless -Force is passed."
    return
}

foreach ($item in $filesToCopy) {
    $destinationPath = Join-Path -Path $publicRootFull -ChildPath $item.Relative
    $destinationDirectory = Split-Path -Path $destinationPath -Parent
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) { New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null }

    if ((Test-Path -LiteralPath $destinationPath -PathType Leaf) -and -not $Force) {
        $existingHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
        $sourceHash = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash
        if ($existingHash -ne $sourceHash) {
            Copy-Item -LiteralPath $item.Source -Destination "$destinationPath.new" -Force
            continue
        }
    }

    if ($PSCmdlet.ShouldProcess($destinationPath, "Export clean public file")) { Copy-Item -LiteralPath $item.Source -Destination $destinationPath -Force }
}

Write-Host "Clean export completed. Review the public repo diff before committing."
