<#
.SYNOPSIS
Checks the public source repo for obvious accidental runtime or private content.

.DESCRIPTION
Fails when runtime folders, zip artifacts, local workspace files, large files,
generic private path indicators, locally configured deny terms, or common
secret-looking patterns appear in Git source candidates. By default, source
candidates are tracked files plus untracked files that are not ignored by Git.
Ignored generated output such as bin/, obj/, node_modules/, and runtime caches
is excluded from the normal verification gate. Use -IncludeIgnored for an
opt-in deep scan of every physical file and directory on disk.

Private names and project-specific terms belong in repo-hygiene.local.jsonc,
which is intentionally ignored by Git.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepoRoot,

    [Parameter()]
    [string] $HygieneConfigPath,

    [Parameter()]
    [long] $MaxFileSizeBytes = 5MB,

    [Parameter()]
    [switch] $IncludeIgnored,

    [Parameter()]
    [string[]] $AllowPath = @(),

    [Parameter()]
    [string[]] $AllowZipPath = @(),

    [Parameter()]
    [string[]] $AllowLargeFilePath = @(),

    [Parameter()]
    [string[]] $AllowDenyTermPath = @(),

    [Parameter()]
    [string[]] $AllowSecretPatternPath = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Get-HygieneRelativePath {
    param(
        [Parameter(Mandatory)]
        [string] $RootPath,

        [Parameter(Mandatory)]
        [string] $FullPath
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $fullPathNormalized = [System.IO.Path]::GetFullPath($FullPath)
    $rootUri = [System.Uri]::new($rootFullPath + [System.IO.Path]::DirectorySeparatorChar)
    $fullUri = [System.Uri]::new($fullPathNormalized)

    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fullUri).ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function ConvertTo-HygieneSlashPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return $Path.Replace('\', '/')
}

function Test-HygieneAllowedPath {
    param(
        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter()]
        [string[]] $Patterns = @()
    )

    $normalized = ConvertTo-HygieneSlashPath -Path $RelativePath

    foreach ($pattern in @($script:AllowPath + $Patterns)) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        $normalizedPattern = ConvertTo-HygieneSlashPath -Path $pattern
        if ([System.Management.Automation.WildcardPattern]::new($normalizedPattern, [System.Management.Automation.WildcardOptions]::IgnoreCase).IsMatch($normalized)) {
            return $true
        }
    }

    return $false
}

function Test-HygieneInsideGitDirectory {
    param(
        [Parameter(Mandatory)]
        [string] $FullPath
    )

    $relativePath = ConvertTo-HygieneSlashPath -Path (Get-HygieneRelativePath -RootPath $repoRootFull -FullPath $FullPath)
    return $relativePath -eq ".git" -or $relativePath.StartsWith(".git/", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-HygienePhysicalFileRelativePaths {
    return @(Get-ChildItem -LiteralPath $repoRootFull -File -Recurse -Force |
        Where-Object { -not (Test-HygieneInsideGitDirectory -FullPath $_.FullName) } |
        ForEach-Object { Get-HygieneRelativePath -RootPath $repoRootFull -FullPath $_.FullName } |
        Where-Object { -not (Test-HygieneExcludedSourceCandidate -RelativePath $_) })
}

function Test-HygieneExcludedSourceCandidate {
    param(
        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    $normalized = ConvertTo-HygieneSlashPath -Path $RelativePath

    return $normalized -like "*.local.jsonc" -or
        $normalized -eq "repo-hygiene.local.jsonc" -or
        $normalized -eq "repo-identity.local.jsonc" -or
        $normalized.StartsWith("artifacts/diagnostics/latest/", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-HygieneCandidatePaths {
    param(
        [Parameter()]
        [switch] $IncludeIgnored
    )

    if ($IncludeIgnored) {
        return Get-HygienePhysicalFileRelativePaths
    }

    $git = Get-Command git -ErrorAction SilentlyContinue

    if ($null -ne $git) {
        $paths = @(& git -C $repoRootFull ls-files --cached --others --exclude-standard 2>$null)
        if ($LASTEXITCODE -eq 0) {
            return @($paths | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                -not (Test-HygieneExcludedSourceCandidate -RelativePath $_)
            })
        }
    }

    return Get-HygienePhysicalFileRelativePaths
}

function Get-HygieneCandidateFiles {
    param(
        [Parameter()]
        [string[]] $RelativePaths = @()
    )

    foreach ($candidateRelativePath in @($RelativePaths | Sort-Object -Unique)) {
        $candidateFullPath = Join-Path -Path $repoRootFull -ChildPath $candidateRelativePath
        if (Test-Path -LiteralPath $candidateFullPath -PathType Leaf) {
            Get-Item -LiteralPath $candidateFullPath
        }
    }
}

function Get-HygieneCandidateDirectoryPaths {
    param(
        [Parameter()]
        [string[]] $RelativePaths = @(),

        [Parameter()]
        [switch] $IncludeIgnored
    )

    if ($IncludeIgnored) {
        return @(Get-ChildItem -LiteralPath $repoRootFull -Directory -Recurse -Force |
            Where-Object { -not (Test-HygieneInsideGitDirectory -FullPath $_.FullName) } |
            ForEach-Object { Get-HygieneRelativePath -RootPath $repoRootFull -FullPath $_.FullName })
    }

    $directories = [System.Collections.Generic.List[string]]::new()

    foreach ($candidateRelativePath in $RelativePaths) {
        $normalized = ConvertTo-HygieneSlashPath -Path $candidateRelativePath
        $segments = @($normalized -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        for ($index = 1; $index -lt $segments.Count; $index++) {
            $directories.Add(($segments[0..($index - 1)] -join "/"))
        }
    }

    return @($directories | Sort-Object -Unique)
}

function Test-HygieneAllowedVscodePath {
    param(
        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    $normalized = ConvertTo-HygieneSlashPath -Path $RelativePath
    return $normalized.Equals(".vscode/tasks.json", [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-HygieneSourceTextFile {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo] $File
    )

    $sourceExtensions = @(
        ".cs", ".css", ".gitignore", ".html", ".js", ".json", ".jsonc",
        ".jsx", ".md", ".ps1", ".psd1", ".psm1", ".template", ".ts",
        ".tsx", ".txt", ".xml", ".yaml", ".yml"
    )

    if ($sourceExtensions -contains $File.Extension.ToLowerInvariant()) {
        return $true
    }

    return $File.Name -in @(".gitignore", "AGENTS.md", "README.md")
}

function Remove-HygieneJsoncComments {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $result = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]
        $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char] 0 }

        if ($inLineComment) {
            if ($char -eq "`r" -or $char -eq "`n") {
                $inLineComment = $false
                [void] $result.Append($char)
            }
            continue
        }

        if ($inBlockComment) {
            if ($char -eq "*" -and $next -eq "/") {
                $inBlockComment = $false
                $index++
            }
            elseif ($char -eq "`r" -or $char -eq "`n") {
                [void] $result.Append($char)
            }
            continue
        }

        if ($inString) {
            [void] $result.Append($char)
            if ($escaped) {
                $escaped = $false
            }
            elseif ($char -eq "\") {
                $escaped = $true
            }
            elseif ($char -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($char -eq '"') {
            $inString = $true
            [void] $result.Append($char)
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

        [void] $result.Append($char)
    }

    return $result.ToString()
}

function Read-HygieneJsoncFile {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $text = Get-Content -LiteralPath $Path -Raw
    $json = Remove-HygieneJsoncComments -Text $text
    return $json | ConvertFrom-Json
}

function Get-HygieneStringArray {
    param(
        [Parameter()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    return @($Value) |
        Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string] $_) } |
        ForEach-Object { [string] $_ }
}

function Get-HygieneConfigValue {
    param(
        [Parameter(Mandatory)]
        [object] $Config,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-HygieneAllowedTerm {
    param(
        [Parameter(Mandatory)]
        [string] $Term,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter()]
        [string[]] $AllowTerms = @(),

        [Parameter()]
        [string[]] $AllowPatterns = @()
    )

    foreach ($allowTerm in $AllowTerms) {
        if ($Term.Equals($allowTerm, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    foreach ($allowPattern in $AllowPatterns) {
        if ([string]::IsNullOrWhiteSpace($allowPattern)) {
            continue
        }

        if ($Text -match $allowPattern) {
            return $true
        }
    }

    return $false
}

function Get-HygieneLineColumn {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [int] $Index
    )

    $safeIndex = [Math]::Min([Math]::Max(0, $Index), $Text.Length)
    $line = 1
    $column = 1

    for ($position = 0; $position -lt $safeIndex; $position++) {
        if ($Text[$position] -eq "`n") {
            $line++
            $column = 1
        }
        else {
            $column++
        }
    }

    return [pscustomobject] @{
        Line = $line
        Column = $column
    }
}

function ConvertTo-HygieneVisibleSnippet {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [int] $Index,

        [Parameter(Mandatory)]
        [int] $Length,

        [Parameter()]
        [switch] $RedactMatch
    )

    $contextLength = 48
    $safeIndex = [Math]::Min([Math]::Max(0, $Index), $Text.Length)
    $safeLength = [Math]::Min([Math]::Max(0, $Length), $Text.Length - $safeIndex)
    $startIndex = [Math]::Max(0, $safeIndex - $contextLength)
    $endIndex = [Math]::Min($Text.Length, $safeIndex + $safeLength + $contextLength)

    $before = $Text.Substring($startIndex, $safeIndex - $startIndex)
    if ($RedactMatch) {
        $matchText = "<redacted>"
    }
    else {
        $matchText = $Text.Substring($safeIndex, $safeLength)
    }

    $afterStart = $safeIndex + $safeLength
    $after = $Text.Substring($afterStart, $endIndex - $afterStart)
    $snippet = $before + $matchText + $after
    $snippet = $snippet.Replace("`r", "\r").Replace("`n", "\n").Replace("`t", "\t")

    if ($startIndex -gt 0) {
        $snippet = "..." + $snippet
    }

    if ($endIndex -lt $Text.Length) {
        $snippet = $snippet + "..."
    }

    return $snippet
}

function Add-HygieneTextMatchFailure {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]] $Failures,

        [Parameter(Mandatory)]
        [string] $Rule,

        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [int] $MatchIndex,

        [Parameter(Mandatory)]
        [int] $MatchLength,

        [Parameter()]
        [string] $MatchLabel,

        [Parameter()]
        [switch] $RedactMatch
    )

    $location = Get-HygieneLineColumn -Text $Text -Index $MatchIndex
    $snippet = ConvertTo-HygieneVisibleSnippet -Text $Text -Index $MatchIndex -Length $MatchLength -RedactMatch:$RedactMatch
    $message = "${Rule} appears in source candidate: ${RelativePath}:$($location.Line):$($location.Column)"

    if (-not [string]::IsNullOrWhiteSpace($MatchLabel)) {
        $message += " ($MatchLabel)"
    }

    $message += " -> $snippet"
    $Failures.Add($message)
}

if (-not (Test-Path -LiteralPath $repoRootFull -PathType Container)) {
    throw "Repo root does not exist: $repoRootFull"
}

if ([string]::IsNullOrWhiteSpace($HygieneConfigPath)) {
    $defaultConfigPath = Join-Path -Path $repoRootFull -ChildPath "repo-hygiene.local.jsonc"
    if (Test-Path -LiteralPath $defaultConfigPath -PathType Leaf) {
        $HygieneConfigPath = $defaultConfigPath
    }
}

$localConfig = $null
if (-not [string]::IsNullOrWhiteSpace($HygieneConfigPath)) {
    $localConfigFull = [System.IO.Path]::GetFullPath($HygieneConfigPath)
    if (-not (Test-Path -LiteralPath $localConfigFull -PathType Leaf)) {
        throw "Repo hygiene config does not exist: $localConfigFull"
    }

    $localConfig = Read-HygieneJsoncFile -Path $localConfigFull
}

$localDenyTerms = @()
$localAllowTerms = @()
$localAllowPatterns = @()
if ($null -ne $localConfig) {
    $localDenyTerms = Get-HygieneStringArray -Value (Get-HygieneConfigValue -Config $localConfig -Name "denyTerms")
    $localAllowTerms = Get-HygieneStringArray -Value (Get-HygieneConfigValue -Config $localConfig -Name "allowTerms")
    $localAllowPatterns = Get-HygieneStringArray -Value (Get-HygieneConfigValue -Config $localConfig -Name "allowPatterns")

    $configuredMaxFileSizeMB = Get-HygieneConfigValue -Config $localConfig -Name "maxFileSizeMB"
    if ($null -ne $configuredMaxFileSizeMB) {
        $MaxFileSizeBytes = [long] ([double] $configuredMaxFileSizeMB * 1MB)
    }

    $AllowPath += Get-HygieneStringArray -Value (Get-HygieneConfigValue -Config $localConfig -Name "allowPaths")
    $AllowZipPath += Get-HygieneStringArray -Value (Get-HygieneConfigValue -Config $localConfig -Name "allowZipPaths")
    $AllowLargeFilePath += Get-HygieneStringArray -Value (Get-HygieneConfigValue -Config $localConfig -Name "allowLargeFilePaths")
    $AllowDenyTermPath += Get-HygieneStringArray -Value (Get-HygieneConfigValue -Config $localConfig -Name "allowDenyTermPaths")
    $AllowSecretPatternPath += Get-HygieneStringArray -Value (Get-HygieneConfigValue -Config $localConfig -Name "allowSecretPatternPaths")
}

# These files intentionally document/sample hygiene deny terms. They must not
# fail deny-term checks merely because placeholder terms appear in examples.
# Secret-pattern checks still run unless separately allowed.
$builtInAllowDenyTermPaths = @(
    "repo-hygiene.example.jsonc",
    "docs/guides/repo-hygiene.md"
)
$AllowDenyTermPath += $builtInAllowDenyTermPaths

$candidateRelativePaths = Get-HygieneCandidatePaths -IncludeIgnored:$IncludeIgnored
$candidateFiles = @(Get-HygieneCandidateFiles -RelativePaths $candidateRelativePaths)
$candidateDirectoryRelativePaths = Get-HygieneCandidateDirectoryPaths -RelativePaths $candidateRelativePaths -IncludeIgnored:$IncludeIgnored

$runtimeFolderNames = @("downloads", "snapshots", "logs")
$localWorkspaceFolderNames = @(".idea")
foreach ($directoryRelativePath in $candidateDirectoryRelativePaths) {
    $normalizedDirectoryPath = ConvertTo-HygieneSlashPath -Path $directoryRelativePath
    $directoryName = @($normalizedDirectoryPath -split "/")[-1]
    $displayDirectoryPath = $normalizedDirectoryPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)

    if ($directoryName -in $runtimeFolderNames -and -not (Test-HygieneAllowedPath -RelativePath $normalizedDirectoryPath)) {
        $failures.Add("Runtime folder must not live in source repo: $displayDirectoryPath")
    }

    if ($directoryName -in $localWorkspaceFolderNames -and -not (Test-HygieneAllowedPath -RelativePath $normalizedDirectoryPath)) {
        $failures.Add("Local workspace folder must not live in source repo: $displayDirectoryPath")
    }
}

foreach ($file in $candidateFiles) {
    $relativePath = Get-HygieneRelativePath -RootPath $repoRootFull -FullPath $file.FullName

    if ($file.Extension -ieq ".code-workspace" -and -not (Test-HygieneAllowedPath -RelativePath $relativePath)) {
        $failures.Add("Local workspace file must not live in source repo: $relativePath")
    }

    if ((ConvertTo-HygieneSlashPath -Path $relativePath).StartsWith(".vscode/", [System.StringComparison]::OrdinalIgnoreCase) -and
        -not (Test-HygieneAllowedVscodePath -RelativePath $relativePath) -and
        -not (Test-HygieneAllowedPath -RelativePath $relativePath)) {
        $failures.Add("Local VS Code workspace file must not live in source repo: $relativePath")
    }

    if ($file.Extension -ieq ".zip" -and -not (Test-HygieneAllowedPath -RelativePath $relativePath -Patterns $AllowZipPath)) {
        $failures.Add("Zip artifact must not live in source repo: $relativePath")
    }

    if ($file.Length -gt $MaxFileSizeBytes -and -not (Test-HygieneAllowedPath -RelativePath $relativePath -Patterns $AllowLargeFilePath)) {
        $sizeMb = [math]::Round($file.Length / 1MB, 2)
        $limitMb = [math]::Round($MaxFileSizeBytes / 1MB, 2)
        $failures.Add("Large file exceeds $limitMb MB: $relativePath ($sizeMb MB)")
    }
}

$genericDenyTerms = @(
    ("C:" + [char]92 + "Users" + [char]92),
    ("C:" + "/" + "Users" + "/"),
    ("/" + "Users" + "/"),
    ("One" + "Drive" + [char]92),
    ("One" + "Drive" + "/"),
    ("Steam" + [char]92 + "steamapps"),
    ("Steam" + "/" + "steamapps")
)

$placeholderDenyTerms = @(
    "YOUR_WINDOWS_USERNAME",
    "YOUR_PRIVATE_PROJECT_NAME",
    "YOUR_CLIENT_NAME",
    "YOUR_PUBLIC_SAMPLE_NAME"
)

$localDenyTerms = @($localDenyTerms | Where-Object { $placeholderDenyTerms -notcontains $_ })

$denyTermChecks = [System.Collections.Generic.List[object]]::new()
foreach ($term in $genericDenyTerms) {
    if (-not [string]::IsNullOrWhiteSpace($term)) {
        [void] $denyTermChecks.Add([pscustomobject] @{ Term = $term; Label = "built-in path indicator" })
    }
}

$localTermIndex = 0
foreach ($term in $localDenyTerms) {
    if (-not [string]::IsNullOrWhiteSpace($term)) {
        $localTermIndex++
        [void] $denyTermChecks.Add([pscustomobject] @{ Term = $term; Label = "local deny term #$localTermIndex" })
    }
}

$drivePrefixPattern = "[A-Z]:[" + [regex]::Escape([string] [char]92) + "/]"
$unixHomeRootPattern = "/" + "(?:home|Users|mnt)/"
$pathSeparatorPattern = "[" + [regex]::Escape([string] [char]92) + "/]"
$uncRootPattern = [regex]::Escape([string] [char]92 + [string] [char]92)
$uncSegmentTerminatorPattern = '(?=$|' + $pathSeparatorPattern + ')'
$uncPathSeparatorPattern = "(?:" + $pathSeparatorPattern + "{1,2})"
$uncPathSegmentPattern = '(?!x[0-9A-Fa-f]{2})(?!u[0-9A-Fa-f]{4})(?![trnfbva0]' + $uncSegmentTerminatorPattern + ')[A-Za-z0-9][A-Za-z0-9._$-]{1,}'
$uncServerSharePattern = $uncRootPattern + $uncPathSegmentPattern + $uncPathSeparatorPattern + $uncPathSegmentPattern + '(?:' + $uncPathSeparatorPattern + '[^"''\s)]{1,})?'
$absolutePathPatterns = @(
    ('(?i)(?<![A-Za-z0-9_<>$])(?:' + $drivePrefixPattern + ')[^"''\s)]{2,}'),
    ('(?i)(?<![A-Za-z0-9_<>$])(?:' + $unixHomeRootPattern + ')[^"''\s)]{2,}'),
    ('(?i)(?<![A-Za-z0-9_<>$.])' + $uncServerSharePattern)
)

$builtInAllowAbsolutePathPatterns = @(
    '^artifacts/diagnostics/latest/',
    '^artifacts/.*/latest/',
    '^repo-hygiene\.local\.jsonc$',
    '^repo-identity\.local\.jsonc$',
    '\.local\.jsonc$'
)

function Test-HygieneAllowedAbsolutePathLocation {
    param([Parameter(Mandatory)] [string] $RelativePath)
    $normalized = ConvertTo-HygieneSlashPath -Path $RelativePath
    foreach ($pattern in $builtInAllowAbsolutePathPatterns) {
        if ($normalized -match $pattern) { return $true }
    }
    return $false
}

$secretPatterns = @(
    ("AKIA" + "[0-9A-Z]{16}"),
    ("gh[pousr]_" + "[A-Za-z0-9_]{36,}"),
    ("-----BEGIN " + "(RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----"),
    ("(?i)\b(api[_-]?key|client[_-]?secret|password|secret|token)\b\s*[:=]\s*['""][^'""]{16,}['""]")
)

foreach ($file in $candidateFiles) {
    if (-not (Test-HygieneSourceTextFile -File $file)) {
        continue
    }

    $relativePath = Get-HygieneRelativePath -RootPath $repoRootFull -FullPath $file.FullName
    $rawText = Get-Content -LiteralPath $file.FullName -Raw
    if ($null -eq $rawText) {
        $text = ""
    }
    else {
        $text = [string] $rawText
    }

    if (-not (Test-HygieneAllowedPath -RelativePath $relativePath -Patterns $AllowDenyTermPath)) {
        foreach ($denyTermCheck in $denyTermChecks) {
            $term = [string] $denyTermCheck.Term
            if (Test-HygieneAllowedTerm -Term $term -Text $text -AllowTerms $localAllowTerms -AllowPatterns $localAllowPatterns) {
                continue
            }

            $searchStart = 0
            while ($searchStart -lt $text.Length) {
                $matchIndex = $text.IndexOf($term, $searchStart, [System.StringComparison]::OrdinalIgnoreCase)
                if ($matchIndex -lt 0) {
                    break
                }

                Add-HygieneTextMatchFailure `
                    -Failures $failures `
                    -Rule "Denied hygiene term" `
                    -RelativePath $relativePath `
                    -Text $text `
                    -MatchIndex $matchIndex `
                    -MatchLength $term.Length `
                    -MatchLabel ([string] $denyTermCheck.Label)

                $searchStart = $matchIndex + [Math]::Max(1, $term.Length)
            }
        }
    }

    if (-not (Test-HygieneAllowedAbsolutePathLocation -RelativePath $relativePath)) {
        foreach ($pattern in $absolutePathPatterns) {
            foreach ($match in [regex]::Matches($text, $pattern)) {
                Add-HygieneTextMatchFailure `
                    -Failures $failures `
                    -Rule "Hardcoded absolute path" `
                    -RelativePath $relativePath `
                    -Text $text `
                    -MatchIndex $match.Index `
                    -MatchLength $match.Length
            }
        }
    }

    if (-not (Test-HygieneAllowedPath -RelativePath $relativePath -Patterns $AllowSecretPatternPath)) {
        foreach ($pattern in $secretPatterns) {
            foreach ($match in [regex]::Matches($text, $pattern)) {
                Add-HygieneTextMatchFailure `
                    -Failures $failures `
                    -Rule "Secret-looking pattern" `
                    -RelativePath $relativePath `
                    -Text $text `
                    -MatchIndex $match.Index `
                    -MatchLength $match.Length `
                    -RedactMatch
            }
        }
    }
}

if ($failures.Count -gt 0) {
    $message = "Repo hygiene check failed:$([Environment]::NewLine) - " + ($failures -join "$([Environment]::NewLine) - ")
    throw $message
}

Write-Host "Repo hygiene check passed."
Write-Host "Repo root: $repoRootFull"
if ($IncludeIgnored) {
    Write-Host "Repo hygiene scan mode: all physical files and directories, including Git-ignored paths"
}
else {
    Write-Host "Repo hygiene scan mode: tracked files plus untracked files not ignored by Git"
}
if (-not [string]::IsNullOrWhiteSpace($HygieneConfigPath)) {
    Write-Host "Repo hygiene config: $([System.IO.Path]::GetFullPath($HygieneConfigPath))"
}
