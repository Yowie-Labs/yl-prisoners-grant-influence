<#
.SYNOPSIS
Runs repository verification for a reference-mode ai-repo-workflow target repo.

.DESCRIPTION
Checks the thin repo-local workflow scaffold, runs repository hygiene,
runs repository conventions as warnings unless StrictConventions is set, and runs
Pester tests when present. Full terminal output is also captured under
artifacts/diagnostics/latest when the artifact transcript helper is available.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepoRoot,

    [Parameter()]
    [switch] $StrictConventions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
$artifactTranscriptScript = Join-Path -Path $repoRootFull -ChildPath 'scripts/Start-ArtifactTranscript.ps1'
$artifactTranscript = $null

if (Test-Path -LiteralPath $artifactTranscriptScript -PathType Leaf) {
    . $artifactTranscriptScript
    $artifactTranscript = Start-AiRepoArtifactTranscript -RepoRoot $repoRootFull -Name 'verify'
}

try {
    $requiredPaths = @(
        'AGENTS.md',
        'repo-tools.ps1',
        '.gitignore',
        '.gitattributes',
        '.githooks/pre-commit',
        '.githooks/pre-merge-commit',
        '.githooks/pre-applypatch',
        '.githooks/pre-rebase',
        '.githooks/pre-push',
        'config/ai-repo-workflow.reference.jsonc',
        'config/ai-repo-workflow/patch-config.jsonc',
        'config/ai-repo-workflow/snapshot-config.jsonc',
        'config/ai-repo-workflow/watcher-config.jsonc',
        'config/ai-repo-workflow/test-config.jsonc',
        'scripts/Show-RepoToolsMenu.ps1',
        'scripts/Start-ArtifactTranscript.ps1',
        'scripts/Invoke-RepoDiagnosticCommand.ps1',
        'scripts/Test-RepoHygiene.ps1',
        'scripts/Test-RepoConventions.ps1',
        'scripts/Test-CSharpSourceLayout.ps1',
        'scripts/test.ps1'
    )

    $missing = @(
        foreach ($relativePath in $requiredPaths) {
            $candidate = Join-Path -Path $repoRootFull -ChildPath $relativePath
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $relativePath
            }
        }
    )

    if ($missing.Count -gt 0) {
        throw "Missing required reference-mode files: $($missing -join ', ')"
    }

    $vendoredWorkflowPath = Join-Path -Path $repoRootFull -ChildPath 'tools/ai-repo-workflow'
    if (Test-Path -LiteralPath $vendoredWorkflowPath -PathType Container) {
        Write-Warning 'Legacy vendored workflow folder still exists: tools/ai-repo-workflow'
        Write-Warning 'Reference-mode repos should use config/ai-repo-workflow.reference.jsonc and the deployed package root.'
    }

    & (Join-Path -Path $repoRootFull -ChildPath 'scripts/Test-RepoHygiene.ps1') -RepoRoot $repoRootFull

    $conventionsScript = Join-Path -Path $repoRootFull -ChildPath 'scripts/Test-RepoConventions.ps1'
    if ($StrictConventions) {
        & $conventionsScript -RepoRoot $repoRootFull -Strict
    }
    else {
        try {
            & $conventionsScript -RepoRoot $repoRootFull
        }
        catch {
            Write-Warning "Repo convention check failed but StrictConventions was not set: $($_.Exception.Message)"
        }
    }

    & (Join-Path -Path $repoRootFull -ChildPath 'scripts/Test-CSharpSourceLayout.ps1') -RepoRoot $repoRootFull

    $testScriptPath = Join-Path -Path $repoRootFull -ChildPath 'scripts/test.ps1'
    & $testScriptPath -RepoRoot $repoRootFull

    Write-Host 'Repository verification passed.'
    Write-Host "Repo root: $repoRootFull"
}
finally {
    if (Get-Command Stop-AiRepoArtifactTranscript -ErrorAction SilentlyContinue) {
        Stop-AiRepoArtifactTranscript -State $artifactTranscript
    }
}
