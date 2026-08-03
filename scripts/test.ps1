<#
.SYNOPSIS
Runs repository tests.

.DESCRIPTION
Locates the repository root, runs Pester tests under the tests directory when
present, and runs repo-owned external test commands from ai-repo-workflow
configuration when present. External commands are captured through
Invoke-RepoDiagnosticCommand.ps1 so stdout, stderr, exit code, and command
metadata are available in artifacts/diagnostics/latest. The script intentionally
does not install PowerShell modules.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepoRoot,

    [Parameter()]
    [string] $Profile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Remove-AiRepoTestJsoncComments {
    param([Parameter(Mandatory)] [string] $Text)

    $builder = [System.Text.StringBuilder]::new()
    $inString = $false
    $escape = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]
        $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char] 0 }

        if ($inLineComment) {
            if ($char -eq "`r" -or $char -eq "`n") {
                $inLineComment = $false
                [void] $builder.Append($char)
            }
            continue
        }

        if ($inBlockComment) {
            if ($char -eq '*' -and $next -eq '/') {
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
            elseif ($char -eq '\') { $escape = $true }
            elseif ($char -eq '"') { $inString = $false }
            continue
        }

        if ($char -eq '"') {
            $inString = $true
            [void] $builder.Append($char)
            continue
        }

        if ($char -eq '/' -and $next -eq '/') {
            $inLineComment = $true
            $index++
            continue
        }

        if ($char -eq '/' -and $next -eq '*') {
            $inBlockComment = $true
            $index++
            continue
        }

        [void] $builder.Append($char)
    }

    return $builder.ToString()
}

function ConvertTo-AiRepoTestArray {
    param([Parameter()] [AllowNull()] $Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @()
        foreach ($item in $Value) { $items += ,$item }
        return $items
    }
    return @($Value)
}

function Get-AiRepoTestPropertyValue {
    param(
        [Parameter()] [object] $Object,
        [Parameter(Mandatory)] [string[]] $Names
    )

    if ($null -eq $Object) { return $null }
    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property) { return $property.Value }
    }
    return $null
}

function Read-AiRepoTestConfig {
    param([Parameter(Mandatory)] [string] $RepoRootFull)

    $candidatePaths = @(
        (Join-Path -Path $RepoRootFull -ChildPath "config/ai-repo-workflow/test-config.jsonc"),
        (Join-Path -Path $RepoRootFull -ChildPath "tools/ai-repo-workflow/config/test-config.jsonc"),
        (Join-Path -Path $RepoRootFull -ChildPath "config/test-config.jsonc")
    )

    foreach ($candidatePath in $candidatePaths) {
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }
        $rawText = Get-Content -LiteralPath $candidatePath -Raw
        $jsonText = Remove-AiRepoTestJsoncComments -Text $rawText
        if ([string]::IsNullOrWhiteSpace($jsonText)) { continue }
        return [pscustomobject] @{
            Path = $candidatePath
            Config = ($jsonText | ConvertFrom-Json -Depth 64)
        }
    }

    return $null
}

function Resolve-AiRepoTestPath {
    param(
        [Parameter(Mandatory)] [string] $RepoRootFull,
        [Parameter()] [AllowEmptyString()] [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $RepoRootFull }
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRootFull -ChildPath $Path))
}

function Test-AiRepoConfiguredCommandSelected {
    param(
        [Parameter()] [object] $Command,
        [Parameter()] [AllowEmptyString()] [string] $Profile
    )

    $enabled = Get-AiRepoTestPropertyValue -Object $Command -Names @('enabled')
    if ($null -ne $enabled -and -not [bool] $enabled) { return $false }

    if ([string]::IsNullOrWhiteSpace($Profile)) {
        $runByDefault = Get-AiRepoTestPropertyValue -Object $Command -Names @('runByDefault')
        if ($null -ne $runByDefault -and -not [bool] $runByDefault) { return $false }
        return $true
    }

    $profiles = @(ConvertTo-AiRepoTestArray -Value (Get-AiRepoTestPropertyValue -Object $Command -Names @('profiles', 'profile')) |
        ForEach-Object { ([string] $_).Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($profiles.Count -eq 0) { return $true }
    return ($profiles -contains $Profile) -or ($profiles -contains 'all')
}

function Invoke-AiRepoConfiguredTestCommand {
    param(
        [Parameter(Mandatory)] [string] $RepoRootFull,
        [Parameter(Mandatory)] [object] $Command,
        [Parameter(Mandatory)] [int] $Index
    )

    $nameValue = Get-AiRepoTestPropertyValue -Object $Command -Names @('name')
    $name = if ([string]::IsNullOrWhiteSpace([string] $nameValue)) { "command-$Index" } else { ([string] $nameValue).Trim() }
    $commandValue = Get-AiRepoTestPropertyValue -Object $Command -Names @('command', 'executable')
    if ([string]::IsNullOrWhiteSpace([string] $commandValue)) {
        throw "Configured test command '$name' is missing required property 'command'."
    }

    $arguments = @(ConvertTo-AiRepoTestArray -Value (Get-AiRepoTestPropertyValue -Object $Command -Names @('arguments', 'args')) |
        ForEach-Object { [string] $_ })
    $workingDirectory = Resolve-AiRepoTestPath -RepoRootFull $RepoRootFull -Path ([string] (Get-AiRepoTestPropertyValue -Object $Command -Names @('workingDirectory', 'cwd')))
    $allowFailure = [bool] (Get-AiRepoTestPropertyValue -Object $Command -Names @('allowFailure'))

    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
        throw "Configured test command '$name' workingDirectory does not exist: $workingDirectory"
    }

    $result = Invoke-AiRepoDiagnosticCommand `
        -RepoRoot $RepoRootFull `
        -Name "test-$Index-$name" `
        -FilePath ([string] $commandValue) `
        -Arguments ([string[]] $arguments) `
        -WorkingDirectory $workingDirectory `
        -AllowFailure:$allowFailure

    if (-not [bool] $result.Succeeded) {
        $message = "Configured test command '$name' failed with exit code $($result.ExitCode). See: $($result.LogPath)"
        if ($allowFailure) {
            Write-Warning $message
            return
        }

        throw $message
    }

    Write-Host "Configured test command passed: $name"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
$diagnosticCommandScript = Join-Path -Path $repoRootFull -ChildPath "scripts/Invoke-RepoDiagnosticCommand.ps1"
if (-not (Test-Path -LiteralPath $diagnosticCommandScript -PathType Leaf)) {
    throw "Diagnostic command helper not found: $diagnosticCommandScript"
}
. $diagnosticCommandScript

$artifactTranscriptScript = Join-Path -Path $repoRootFull -ChildPath "scripts/Start-ArtifactTranscript.ps1"
$artifactTranscript = $null
if (Test-Path -LiteralPath $artifactTranscriptScript -PathType Leaf) {
    . $artifactTranscriptScript
    $artifactTranscript = Start-AiRepoArtifactTranscript -RepoRoot $repoRootFull -Name "test"
}

try {
$testsRoot = Join-Path -Path $repoRootFull -ChildPath "tests"
$testFiles = @()

if (Test-Path -LiteralPath $testsRoot -PathType Container) {
    $testFiles = @(Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Filter "*.Tests.ps1")
}

$pesterRan = $false
if ($testFiles.Count -eq 0) {
    Write-Host "No Pester tests found under: $testsRoot"
    Write-Host "Pester tests skipped."
}
else {
    $minimumPesterVersion = [version] "5.0.0"
    $pesterModule = Get-Module -ListAvailable -Name Pester |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $pesterModule -or $pesterModule.Version -lt $minimumPesterVersion) {
        Write-Host "Pester 5 is required to run repository tests."
        Write-Host "Install for the current user with:"
        Write-Host "  Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber"
        throw "Missing required PowerShell module: Pester 5"
    }

    Import-Module Pester -MinimumVersion $minimumPesterVersion -ErrorAction Stop

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = @($testsRoot)
    $configuration.Run.Exit = $false
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = "Detailed"

    $result = Invoke-Pester -Configuration $configuration

    if ($result.FailedCount -gt 0) {
        throw "Pester tests failed. Failed: $($result.FailedCount); Passed: $($result.PassedCount); Skipped: $($result.SkippedCount)"
    }

    $pesterRan = $true
    Write-Host "Pester tests passed."
    Write-Host "Repo root: $repoRootFull"
}

$configResult = Read-AiRepoTestConfig -RepoRootFull $repoRootFull
$configuredCommands = @()
if ($null -ne $configResult) {
    $commandsValue = Get-AiRepoTestPropertyValue -Object $configResult.Config -Names @('commands', 'testCommands')
    $configuredCommands = @(ConvertTo-AiRepoTestArray -Value $commandsValue)
    Write-Host "Test command config: $($configResult.Path)"
}

$selectedCommands = @()
$commandIndex = 0
foreach ($configuredCommand in $configuredCommands) {
    $commandIndex++
    if (Test-AiRepoConfiguredCommandSelected -Command $configuredCommand -Profile $Profile) {
        $selectedCommands += ,$configuredCommand
    }
}

if ($selectedCommands.Count -eq 0) {
    if ([string]::IsNullOrWhiteSpace($Profile)) {
        Write-Host "No configured test commands selected."
    }
    else {
        Write-Host "No configured test commands selected for profile '$Profile'."
    }
}
else {
    $selectedIndex = 0
    foreach ($selectedCommand in $selectedCommands) {
        $selectedIndex++
        Invoke-AiRepoConfiguredTestCommand -RepoRootFull $repoRootFull -Command $selectedCommand -Index $selectedIndex
    }
    Write-Host "Configured test commands passed. Count: $($selectedCommands.Count)"
}

if (-not $pesterRan -and $selectedCommands.Count -eq 0) {
    Write-Host "Repository tests skipped because no Pester tests or configured test commands were found."
}
else {
    Write-Host "Repository tests passed."
}

}
finally {
    if (Get-Command Stop-AiRepoArtifactTranscript -ErrorAction SilentlyContinue) {
        Stop-AiRepoArtifactTranscript -State $artifactTranscript
    }
}
