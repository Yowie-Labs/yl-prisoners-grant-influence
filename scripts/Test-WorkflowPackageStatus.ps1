<#
.SYNOPSIS
Reports whether the vendored ai-repo-workflow copy is current.
#>

[CmdletBinding()]
param(
    [Parameter()] [string] $RepoRoot,
    [Parameter()] [string] $SourceRoot = "",
    [Parameter()] [string] $TargetInstallPath = "tools/ai-repo-workflow"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-WorkflowStatusJsonc {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    $json = $raw -replace '(?m)//.*$', ''
    if ([string]::IsNullOrWhiteSpace($json)) { return $null }
    return $json | ConvertFrom-Json -Depth 32
}

function Resolve-WorkflowStatusSourceRoot {
    param([Parameter()] [string] $ConfiguredSourceRoot)
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredSourceRoot)) { return [System.IO.Path]::GetFullPath($ConfiguredSourceRoot) }
    foreach ($relativePath in @('config/ai-repo-workflow.local.jsonc', 'config/ai-repo-workflow.reference.jsonc')) {
        $path = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath $relativePath
        $config = Read-WorkflowStatusJsonc -Path $path
        if ($null -eq $config) { continue }
        $property = $config.PSObject.Properties['packageRoot']
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value)) {
            return [System.IO.Path]::GetFullPath(([string] $property.Value).Trim())
        }
    }
    throw 'SourceRoot is required. Pass -SourceRoot or set packageRoot in ignored config/ai-repo-workflow.local.jsonc.'
}

$SourceRoot = Resolve-WorkflowStatusSourceRoot -ConfiguredSourceRoot $SourceRoot

$script:TargetOwnedWorkflowConfigPaths = @(
    "config/agent-workflow-summary.jsonc",
    "config/patch-config.jsonc",
    "config/snapshot-config.jsonc",
    "config/watcher-config.jsonc",
    "config/test-config.jsonc"
)

function Test-TargetOwnedWorkflowConfigPath {
    param([Parameter(Mandatory)] [string] $RelativePath)
    $normalized = $RelativePath.Replace('\', '/')
    return $script:TargetOwnedWorkflowConfigPaths -contains $normalized
}

function Get-WorkflowRelativePath {
    param(
        [Parameter(Mandatory)] [string] $RootPath,
        [Parameter(Mandatory)] [string] $FullPath
    )
    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $fullPathNormalized = [System.IO.Path]::GetFullPath($FullPath)
    $rootUri = [System.Uri]::new($rootFullPath + [System.IO.Path]::DirectorySeparatorChar)
    $fullUri = [System.Uri]::new($fullPathNormalized)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fullUri).ToString()).Replace('/', '/')
}

function Get-WorkflowSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-WorkflowTextSha256 {
    param([Parameter(Mandatory)] [string] $Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}


function ConvertTo-WorkflowArray {
    param([Parameter()] [AllowNull()] $Value)

    if ($null -eq $Value) { return @() }

    if ($Value -is [System.Array]) { return @($Value) }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,$item
        }
        return @($items)
    }

    return @($Value)
}

function Get-WorkflowItemCount {
    param([Parameter()] [AllowNull()] $Value)

    return @((ConvertTo-WorkflowArray -Value $Value)).Count
}

function New-WorkflowManifestObject {
    param(
        [Parameter(Mandatory)] [string] $PackageRoot,
        [Parameter()] [string] $SourceCommit = "",
        [Parameter()] [bool] $SourceDirty = $false
    )

    $packageRootFull = [System.IO.Path]::GetFullPath($PackageRoot)
    $files = @(
        Get-ChildItem -LiteralPath $packageRootFull -File -Recurse -Force |
            Where-Object { $_.Name -ne '.ai-repo-workflow-manifest.json' } |
            Sort-Object FullName |
            ForEach-Object {
                [pscustomobject] @{
                    path = Get-WorkflowRelativePath -RootPath $packageRootFull -FullPath $_.FullName
                    sha256 = Get-WorkflowSha256 -Path $_.FullName
                    sizeBytes = $_.Length
                }
            }
    )

    $hashInput = ($files | ForEach-Object { "$($_.path)|$($_.sha256)|$($_.sizeBytes)" }) -join "`n"
    $packageHash = Get-WorkflowTextSha256 -Text $hashInput

    return [ordered] @{
        schemaVersion = 1
        packageName = "ai-repo-workflow"
        publishedAtLocal = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
        publishedAtUtc = [System.DateTimeOffset]::UtcNow.ToString("o")
        sourceCommit = $SourceCommit
        sourceDirty = $SourceDirty
        packageHash = $packageHash
        fileCount = Get-WorkflowItemCount -Value $files
        files = @($files)
    }
}

function Write-WorkflowManifest {
    param(
        [Parameter(Mandatory)] [string] $PackageRoot,
        [Parameter()] [string] $SourceCommit = "",
        [Parameter()] [bool] $SourceDirty = $false
    )
    $manifest = New-WorkflowManifestObject -PackageRoot $PackageRoot -SourceCommit $SourceCommit -SourceDirty:$SourceDirty
    $manifestPath = Join-Path -Path $PackageRoot -ChildPath ".ai-repo-workflow-manifest.json"
    ($manifest | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $manifestPath -Encoding utf8
    return $manifest
}

function Read-WorkflowManifest {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
}

function Remove-WorkflowJsoncComments {
    param([Parameter(Mandatory)] [string] $Text)

    $builder = [System.Text.StringBuilder]::new()
    $inString = $false
    $escape = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]
        $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($char -eq "`r" -or $char -eq "`n") {
                $inLineComment = $false
                [void] $builder.Append($char)
            }
            continue
        }

        if ($inBlockComment) {
            if ($char -eq "*" -and $next -eq "/") {
                $inBlockComment = $false
                $index++
            }
            elseif ($char -eq "`r" -or $char -eq "`n") {
                [void] $builder.Append($char)
            }
            continue
        }

        if ($inString) {
            [void] $builder.Append($char)
            if ($escape) { $escape = $false }
            elseif ($char -eq "\") { $escape = $true }
            elseif ($char -eq '"') { $inString = $false }
            continue
        }

        if ($char -eq '"') {
            $inString = $true
            [void] $builder.Append($char)
            continue
        }

        if ($char -eq "/" -and $next -eq "/") {
            $inLineComment = $true
            $index++
            continue
        }

        if ($char -eq "/" -and $next -eq "*") {
            $inBlockComment = $true
            $index++
            continue
        }

        [void] $builder.Append($char)
    }

    return $builder.ToString()
}

function ConvertTo-WorkflowHashtable {
    param([Parameter(ValueFromPipeline)] $InputObject)

    process {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $hash = [ordered] @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = ConvertTo-WorkflowHashtable -InputObject $property.Value
            }
            return $hash
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $hash = [ordered] @{}
            foreach ($key in $InputObject.Keys) {
                $hash[$key] = ConvertTo-WorkflowHashtable -InputObject $InputObject[$key]
            }
            return $hash
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $items = @()
            foreach ($item in $InputObject) {
                $items += ,(ConvertTo-WorkflowHashtable -InputObject $item)
            }
            return $items
        }

        return $InputObject
    }
}

function Read-WorkflowJsoncHashtable {
    param([Parameter(Mandatory)] [string] $Path)
    $rawText = Get-Content -LiteralPath $Path -Raw
    $jsonText = Remove-WorkflowJsoncComments -Text $rawText
    if ([string]::IsNullOrWhiteSpace($jsonText)) { return [ordered] @{} }
    return ConvertTo-WorkflowHashtable -InputObject ($jsonText | ConvertFrom-Json -Depth 100)
}

function Get-WorkflowMissingConfigFields {
    param(
        [Parameter(Mandatory)] [string] $TargetPackageRoot,
        [Parameter(Mandatory)] [string] $SourcePackageRoot
    )

    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($relativePath in $script:TargetOwnedWorkflowConfigPaths) {
        $targetPath = Join-Path -Path $TargetPackageRoot -ChildPath $relativePath

        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf) -or
            -not ((Get-WorkflowItemCount -Value @(Get-WorkflowConfigDefaultPaths -SourcePackageRoot $SourcePackageRoot -RelativePath $relativePath | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) -gt 0)) {
            continue
        }

        try {
            $targetConfig = Read-WorkflowJsoncHashtable -Path $targetPath

            foreach ($sourcePath in (Get-WorkflowConfigDefaultPaths -SourcePackageRoot $SourcePackageRoot -RelativePath $relativePath)) {
                if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    continue
                }

                $sourceConfig = Read-WorkflowJsoncHashtable -Path $sourcePath

                foreach ($key in $sourceConfig.Keys) {
                    if (-not $targetConfig.Contains($key)) {
                        $entry = "${relativePath}: $key"
                        if (-not $missing.Contains($entry)) {
                            $missing.Add($entry)
                        }
                    }
                }
            }
        }
        catch {
            $missing.Add("${relativePath}: unable to compare schema fields ($($_.Exception.Message))")
        }
    }

    return [string[]] $missing.ToArray()
}

function Get-WorkflowConfigDefaultPaths {
    param(
        [Parameter(Mandatory)] [string] $SourcePackageRoot,
        [Parameter(Mandatory)] [string] $RelativePath
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    $paths.Add((Join-Path -Path $SourcePackageRoot -ChildPath $RelativePath))

    $templateName = switch ($RelativePath.Replace('\', '/')) {
        "config/patch-config.jsonc" { "patch-config.template.jsonc" }
        "config/snapshot-config.jsonc" { "snapshot-config.template.jsonc" }
        "config/watcher-config.jsonc" { "watcher-config.template.jsonc" }
        default { "" }
    }

    if (-not [string]::IsNullOrWhiteSpace($templateName)) {
        $paths.Add((Join-Path -Path $SourcePackageRoot -ChildPath "templates/$templateName"))
    }

    return [string[]] $paths.ToArray()
}

function Test-WorkflowPackageRoot {
    param([Parameter(Mandatory)] [string] $Path)

    return (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath "scripts") -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath "templates") -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath "config") -PathType Container)
}

function Resolve-WorkflowPackageRoot {
    param([Parameter(Mandatory)] [string] $SourceRoot)

    $sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
    $nestedPackageRoot = Join-Path -Path $sourceRootFull -ChildPath "tools/ai-repo-workflow"

    if (Test-WorkflowPackageRoot -Path $nestedPackageRoot) {
        return [System.IO.Path]::GetFullPath($nestedPackageRoot)
    }

    if (Test-WorkflowPackageRoot -Path $sourceRootFull) {
        return $sourceRootFull
    }

    throw "Could not resolve ai-repo-workflow package root from '$SourceRoot'. Expected either a package root with config/scripts/templates or an outer root containing tools/ai-repo-workflow."
}

function Resolve-WorkflowRepoRoot {
    param(
        [Parameter()] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $TargetInstallPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        return [System.IO.Path]::GetFullPath($RepoRoot)
    }

    if ([System.IO.Path]::IsPathRooted($TargetInstallPath)) {
        $targetFullPath = [System.IO.Path]::GetFullPath($TargetInstallPath)
        $targetLeaf = Split-Path -Path $targetFullPath -Leaf
        $targetParent = Split-Path -Path $targetFullPath -Parent
        $targetParentLeaf = if ([string]::IsNullOrWhiteSpace($targetParent)) { "" } else { Split-Path -Path $targetParent -Leaf }

        if ($targetLeaf -ieq "ai-repo-workflow" -and $targetParentLeaf -ieq "tools") {
            return [System.IO.Path]::GetFullPath((Split-Path -Path $targetParent -Parent))
        }
    }

    return [System.IO.Path]::GetFullPath((Get-Location).ProviderPath)
}

function Resolve-WorkflowTargetPackageRoot {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $TargetInstallPath
    )

    if ([System.IO.Path]::IsPathRooted($TargetInstallPath)) {
        return [System.IO.Path]::GetFullPath($TargetInstallPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRoot -ChildPath $TargetInstallPath))
}

function Get-WorkflowLocalChanges {
    param(
        [Parameter(Mandatory)] [string] $PackageRoot,
        [Parameter()] $Manifest
    )
    $changes = [System.Collections.Generic.List[string]]::new()
    $configChanges = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Manifest) {
        if (Test-Path -LiteralPath $PackageRoot -PathType Container) { $changes.Add("Installed manifest is missing; local changes cannot be proven safe.") }
        return [pscustomobject] @{ SuspiciousChanges = [string[]] $changes.ToArray(); ConfigChanges = [string[]] $configChanges.ToArray() }
    }

    $manifestPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in (ConvertTo-WorkflowArray -Value $Manifest.files)) {
        [void] $manifestPaths.Add([string] $file.path)
        $targetFile = Join-Path -Path $PackageRoot -ChildPath ([string] $file.path)
        if (-not (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
            if (Test-TargetOwnedWorkflowConfigPath -RelativePath ([string] $file.path)) {
                $configChanges.Add("Missing target config file: $($file.path)")
            }
            else {
                $changes.Add("Missing installed file: $($file.path)")
            }
            continue
        }
        $currentHash = Get-WorkflowSha256 -Path $targetFile
        if ($currentHash -ne ([string] $file.sha256).ToLowerInvariant()) {
            if (Test-TargetOwnedWorkflowConfigPath -RelativePath ([string] $file.path)) {
                $configChanges.Add("Customized target config file: $($file.path)")
            }
            else {
                $changes.Add("Modified installed file: $($file.path)")
            }
        }
    }

    Get-ChildItem -LiteralPath $PackageRoot -File -Recurse -Force |
        Where-Object { $_.Name -ne ".ai-repo-workflow-manifest.json" } |
        ForEach-Object {
            $relative = Get-WorkflowRelativePath -RootPath $PackageRoot -FullPath $_.FullName
            if (-not $manifestPaths.Contains($relative)) {
                if (Test-TargetOwnedWorkflowConfigPath -RelativePath $relative) {
                    $configChanges.Add("Extra target config file: $relative")
                }
                else {
                    $changes.Add("Extra installed file: $relative")
                }
            }
        }
    return [pscustomobject] @{ SuspiciousChanges = [string[]] $changes.ToArray(); ConfigChanges = [string[]] $configChanges.ToArray() }
}

$repoRootFull = Resolve-WorkflowRepoRoot -RepoRoot $RepoRoot -TargetInstallPath $TargetInstallPath
$sourcePackageRoot = Resolve-WorkflowPackageRoot -SourceRoot $SourceRoot
$targetPackageRoot = Resolve-WorkflowTargetPackageRoot -RepoRoot $repoRootFull -TargetInstallPath $TargetInstallPath
$sourceManifestPath = Join-Path -Path $sourcePackageRoot -ChildPath ".ai-repo-workflow-manifest.json"
$targetManifestPath = Join-Path -Path $targetPackageRoot -ChildPath ".ai-repo-workflow-manifest.json"
$sourceManifest = Read-WorkflowManifest -Path $sourceManifestPath
$targetManifest = Read-WorkflowManifest -Path $targetManifestPath

$status = "Unknown"
if ($null -eq $sourceManifest) { $status = "SourceManifestMissing" }
elseif ($null -eq $targetManifest) { $status = "TargetManifestMissing" }
elseif ($sourceManifest.packageHash -eq $targetManifest.packageHash) { $status = "Current" }
else { $status = "UpdateAvailable" }

$localChangeSummary = Get-WorkflowLocalChanges -PackageRoot $targetPackageRoot -Manifest $targetManifest
$localChanges = ConvertTo-WorkflowArray -Value $localChangeSummary.SuspiciousChanges
$configChanges = ConvertTo-WorkflowArray -Value $localChangeSummary.ConfigChanges
$missingConfigFields = if ($null -ne $sourceManifest -and (Test-Path -LiteralPath $sourcePackageRoot -PathType Container)) {
    ConvertTo-WorkflowArray -Value (Get-WorkflowMissingConfigFields -TargetPackageRoot $targetPackageRoot -SourcePackageRoot $sourcePackageRoot)
}
else {
    @()
}

[pscustomobject] @{
    Status = $status
    RepoRoot = $repoRootFull
    SourcePackageRoot = $sourcePackageRoot
    TargetPackageRoot = $targetPackageRoot
    SourcePublishedAtUtc = if ($null -ne $sourceManifest) { $sourceManifest.publishedAtUtc } else { "" }
    TargetPublishedAtUtc = if ($null -ne $targetManifest) { $targetManifest.publishedAtUtc } else { "" }
    SourceHash = if ($null -ne $sourceManifest) { $sourceManifest.packageHash } else { "" }
    TargetHash = if ($null -ne $targetManifest) { $targetManifest.packageHash } else { "" }
    LocalChangeCount = Get-WorkflowItemCount -Value $localChanges
    LocalChanges = $localChanges
    TargetConfigDifferenceCount = Get-WorkflowItemCount -Value $configChanges
    TargetConfigDifferences = $configChanges
    MissingConfigSchemaFieldCount = Get-WorkflowItemCount -Value $missingConfigFields
    MissingConfigSchemaFields = $missingConfigFields
} | Format-List

if ($status -eq "UpdateAvailable") { Write-Warning "ai-repo-workflow update available." }
if ((Get-WorkflowItemCount -Value $configChanges) -gt 0) { Write-Warning "Target-owned workflow config differs from the deployed package; this is expected and will be preserved during update." }
if ((Get-WorkflowItemCount -Value $missingConfigFields) -gt 0) { Write-Warning "Target workflow config is missing deployed schema fields; update will try to merge them." }
if ((Get-WorkflowItemCount -Value $localChanges) -gt 0) { Write-Warning "Suspicious local vendored workflow changes detected. Update will require -Force after review." }
