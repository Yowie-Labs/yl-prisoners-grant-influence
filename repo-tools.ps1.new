<#
.SYNOPSIS
Thin launcher for the installed ai-repo-workflow package.

.DESCRIPTION
Target repos do not vendor ai-repo-workflow implementation files. This launcher
resolves the deployed package path from config/ai-repo-workflow.reference.jsonc
and optional config/ai-repo-workflow.local.jsonc, then calls the package scripts
with this repo's config files.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Menu','PatchWatcher','ApplyPatch','Snapshot','AiPatchZip','GitReviewPatch','ReviewReset','Verify','Test','Hygiene','Conventions','Paths','Update','Status')]
    [string] $Command = 'Menu',

    [Parameter()]
    [string] $PatchPath,

    [Parameter()]
    [switch] $Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)

function Remove-RepoToolsJsoncComments {
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

function Read-RepoToolsJsonc {
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [ordered] @{}
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $json = Remove-RepoToolsJsoncComments -Text $raw
    if ([string]::IsNullOrWhiteSpace($json)) {
        return [ordered] @{}
    }

    return $json | ConvertFrom-Json -Depth 32
}

function Resolve-AiRepoWorkflowPackageRoot {
    $referencePath = Join-Path -Path $script:RepoRoot -ChildPath 'config/ai-repo-workflow.reference.jsonc'
    $localPath = Join-Path -Path $script:RepoRoot -ChildPath 'config/ai-repo-workflow.local.jsonc'

    $packageRoot = ''

    foreach ($path in @($referencePath, $localPath)) {
        $config = Read-RepoToolsJsonc -Path $path
        $property = $config.PSObject.Properties['packageRoot']
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string] $property.Value)) {
            $packageRoot = ([string] $property.Value).Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($packageRoot)) {
        throw "ai-repo-workflow package root is not configured. Set packageRoot in ignored config/ai-repo-workflow.local.jsonc."
    }

    $resolved = [System.IO.Path]::GetFullPath($packageRoot)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "ai-repo-workflow package is not installed at '$resolved'. Publish/install it from the ai-repo-workflow source repo, or set config/ai-repo-workflow.local.jsonc."
    }

    return $resolved
}

function Resolve-AiRepoWorkflowScript {
    param([Parameter(Mandatory)] [string] $RelativePath)

    $scriptPath = Join-Path -Path $script:PackageRoot -ChildPath $RelativePath
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "ai-repo-workflow script not found: $scriptPath"
    }

    return $scriptPath
}

function Get-RepoToolsShell {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwsh) {
        return $pwsh.Source
    }

    $powershell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -ne $powershell) {
        return $powershell.Source
    }

    throw "Could not find pwsh or powershell.exe to run ai-repo-workflow package scripts."
}

function Invoke-AiRepoWorkflowScript {
    param(
        [Parameter(Mandatory)] [string] $RelativePath,
        [Parameter()] [string[]] $ArgumentList = @()
    )

    $scriptPath = Resolve-AiRepoWorkflowScript -RelativePath $RelativePath
    $powerShellExe = Get-RepoToolsShell
    Push-Location -LiteralPath $script:RepoRoot
    try {
        $output = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @ArgumentList 2>&1)
        $exitCode = $LASTEXITCODE
        foreach ($line in $output) {
            Write-Host $line
        }
        if ($exitCode -ne 0) {
            $finalStatus = ''
            foreach ($line in $output) {
                $lineText = [string] $line
                if ($lineText -match '^\s*Final status\s*:\s*(?<status>\S+)') {
                    $finalStatus = [string] $Matches['status']
                }
            }

            $message = if ([string]::IsNullOrWhiteSpace($finalStatus)) {
                "ai-repo-workflow command exited with code $exitCode. Complete output is shown above; inspect the generated diagnostics and snapshot."
            }
            else {
                "ai-repo-workflow completed with status '$finalStatus' and exit code $exitCode. Complete output is shown above; inspect the generated diagnostics and snapshot."
            }
            throw $message
        }
    }
    finally {
        Pop-Location
    }
}

function Get-RepoConfigPath {
    param([Parameter(Mandatory)] [string] $Name)
    return Join-Path -Path $script:RepoRoot -ChildPath "config/ai-repo-workflow/$Name"
}

function Show-RepoToolPaths {
    Write-Host ''
    Write-Host 'AI Repo Workflow reference mode'
    Write-Host ''
    Write-Host "Repo root    : $script:RepoRoot"
    Write-Host "Package root : $script:PackageRoot"
    Write-Host "Patch config : $(Get-RepoConfigPath -Name 'patch-config.jsonc')"
    Write-Host "Snapshot config: $(Get-RepoConfigPath -Name 'snapshot-config.jsonc')"
    Write-Host "Watcher config : $(Get-RepoConfigPath -Name 'watcher-config.jsonc')"
    Write-Host ''
    Write-Host 'Target repos do not edit or vendor tools/ai-repo-workflow. Package fixes go to the ai-repo-workflow source repo, then publish/install to the package root above.'
}

$script:PackageRoot = Resolve-AiRepoWorkflowPackageRoot

switch ($Command) {
    'Menu' {
        $menuScript = Join-Path -Path $script:RepoRoot -ChildPath 'scripts/Show-RepoToolsMenu.ps1'
        if (-not (Test-Path -LiteralPath $menuScript -PathType Leaf)) {
            throw "Missing menu script: $menuScript"
        }
        & $menuScript -RepoRoot $script:RepoRoot
    }
    'PatchWatcher' {
        $argumentList = @('-ConfigPath', (Get-RepoConfigPath -Name 'watcher-config.jsonc'))
        if ($Once) { $argumentList += '-Once' }
        Invoke-AiRepoWorkflowScript -RelativePath 'scripts/Start-PatchWatcher.ps1' -ArgumentList $argumentList
    }
    'ApplyPatch' {
        $argumentList = @('-ConfigPath', (Get-RepoConfigPath -Name 'patch-config.jsonc'))
        if (-not [string]::IsNullOrWhiteSpace($PatchPath)) {
            $argumentList += @('-PatchPath', $PatchPath)
        }
        Invoke-AiRepoWorkflowScript -RelativePath 'scripts/Invoke-RepoPatch.ps1' -ArgumentList $argumentList
    }
    'Snapshot' {
        Invoke-AiRepoWorkflowScript -RelativePath 'scripts/New-RepoSnapshot.ps1' -ArgumentList @('-ConfigPath', (Get-RepoConfigPath -Name 'snapshot-config.jsonc'))
    }
    'AiPatchZip' {
        Invoke-AiRepoWorkflowScript -RelativePath 'scripts/New-AiPatchZip.ps1' -ArgumentList @('-RepoRoot', $script:RepoRoot, '-IncludeUntracked')
    }
    'GitReviewPatch' {
        Invoke-AiRepoWorkflowScript -RelativePath 'scripts/New-GitReviewPatch.ps1' -ArgumentList @('-RepoRoot', $script:RepoRoot)
    }
    'ReviewReset' {
        Invoke-AiRepoWorkflowScript -RelativePath 'scripts/New-AiReviewPacket.ps1' -ArgumentList @('-RepoRoot', $script:RepoRoot)
    }
    'Verify' {
        & (Join-Path -Path $script:RepoRoot -ChildPath 'scripts/verify.ps1')
    }
    'Test' {
        & (Join-Path -Path $script:RepoRoot -ChildPath 'scripts/test.ps1')
    }
    'Hygiene' {
        & (Join-Path -Path $script:RepoRoot -ChildPath 'scripts/Test-RepoHygiene.ps1')
    }
    'Conventions' {
        & (Join-Path -Path $script:RepoRoot -ChildPath 'scripts/Test-RepoConventions.ps1')
    }
    'Paths' {
        Show-RepoToolPaths
    }
    'Update' {
        Invoke-AiRepoWorkflowScript -RelativePath 'scripts/Update-WorkflowPackage.ps1' -ArgumentList @('-RepoRoot', $script:RepoRoot, '-WorkflowMode', 'Reference', '-NoBootstrap')
    }
    'Status' {
        & (Join-Path -Path $script:RepoRoot -ChildPath 'scripts/Test-WorkflowPackageStatus.ps1')
    }
    default {
        throw "Unsupported command: $Command"
    }
}
