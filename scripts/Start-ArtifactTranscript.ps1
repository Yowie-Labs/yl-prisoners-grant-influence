<#
.SYNOPSIS
Starts and stops short-lived artifact transcripts for repo commands.

.DESCRIPTION
Entry-point scripts such as verify.ps1, test.ps1, publish, and update commands
can dot-source this helper to mirror PowerShell activity into
artifacts/diagnostics/latest. Native/external command output must additionally use
Invoke-RepoDiagnosticCommand.ps1; Start-Transcript alone is not accepted as
complete build/test evidence. The latest diagnostics directory is cleared at the
start of a top-level command so AI agents read current logs instead of stale output.
#>

Set-StrictMode -Version Latest

function Get-AiRepoSafeArtifactName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $safeName = [regex]::Replace($Name.Trim(), '[^A-Za-z0-9._-]+', '-')
    $safeName = $safeName.Trim('-', '.', '_')
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        return 'command'
    }

    return $safeName
}

function Start-AiRepoArtifactTranscript {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $RepoRoot,

        [Parameter()]
        [string] $Name = 'command'
    )

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    }

    $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)

    if ($env:AI_REPO_ARTIFACT_TRANSCRIPT_ACTIVE -eq '1') {
        return [pscustomobject] @{
            Started = $false
            Path = $env:AI_REPO_ARTIFACT_TRANSCRIPT_PATH
            Directory = $env:AI_REPO_ARTIFACT_TRANSCRIPT_DIR
        }
    }

    $latestRoot = Join-Path -Path $repoRootFull -ChildPath 'artifacts/diagnostics/latest'

    if (Test-Path -LiteralPath $latestRoot) {
        Remove-Item -LiteralPath $latestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $latestRoot -Force | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeName = Get-AiRepoSafeArtifactName -Name $Name
    $logPath = Join-Path -Path $latestRoot -ChildPath "$safeName-$timestamp.log"
    $summaryPath = Join-Path -Path $latestRoot -ChildPath 'README.md'

    @(
        '# Latest command diagnostics',
        '',
        'This directory is intentionally short-lived and is cleared at the start of each top-level ai-repo-workflow command.',
        'AI agents should inspect these files before asking the user to paste terminal output.',
        'This transcript is supplemental; native command output requires explicit diagnostic-command capture.',
        '',
        "Command: $Name",
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
        "Log: $([System.IO.Path]::GetFileName($logPath))"
    ) | Set-Content -LiteralPath $summaryPath -Encoding utf8

    try {
        Start-Transcript -LiteralPath $logPath -Force | Out-Null
        $env:AI_REPO_ARTIFACT_TRANSCRIPT_ACTIVE = '1'
        $env:AI_REPO_ARTIFACT_TRANSCRIPT_PATH = $logPath
        $env:AI_REPO_ARTIFACT_TRANSCRIPT_DIR = $latestRoot
        Write-Host "Artifact log: $logPath"
        return [pscustomobject] @{
            Started = $true
            Path = $logPath
            Directory = $latestRoot
        }
    }
    catch {
        Write-Warning "Could not start artifact transcript at '$logPath': $($_.Exception.Message)"
        return [pscustomobject] @{
            Started = $false
            Path = $logPath
            Directory = $latestRoot
        }
    }
}

function Stop-AiRepoArtifactTranscript {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object] $State
    )

    if ($null -eq $State -or -not ([bool] $State.Started)) {
        return
    }

    try {
        Stop-Transcript | Out-Null
    }
    catch {
        Write-Warning "Could not stop artifact transcript cleanly: $($_.Exception.Message)"
    }
    finally {
        Remove-Item Env:AI_REPO_ARTIFACT_TRANSCRIPT_ACTIVE -ErrorAction SilentlyContinue
        Remove-Item Env:AI_REPO_ARTIFACT_TRANSCRIPT_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:AI_REPO_ARTIFACT_TRANSCRIPT_DIR -ErrorAction SilentlyContinue
    }

    if (-not [string]::IsNullOrWhiteSpace([string] $State.Path)) {
        Write-Host "Artifact log saved: $($State.Path)"
    }
}
