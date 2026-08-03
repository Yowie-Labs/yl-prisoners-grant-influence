<#
.SYNOPSIS
Shows the AI Repo Workflow Tools menu.

.DESCRIPTION
Provides a small, dependency-free launcher for common ai-repo-workflow tasks.
Missing future commands are reported as planned instead of failing.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoToolsRoot {
    param(
        [Parameter()]
        [string] $CandidateRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($CandidateRoot)) {
        return [System.IO.Path]::GetFullPath($CandidateRoot)
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $git) {
        $gitRoot = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
            return [System.IO.Path]::GetFullPath($gitRoot)
        }
    }

    return [System.IO.Path]::GetFullPath((Split-Path -Path $PSScriptRoot -Parent))
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

    return ""
}

function Resolve-RepoToolsScript {
    param(
        [Parameter(Mandatory)]
        [string[]] $RelativePaths
    )

    foreach ($relativePath in $RelativePaths) {
        $fullPath = Join-Path -Path $script:RepoRootFull -ChildPath $relativePath
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            return $fullPath
        }
    }

    return ""
}


function Test-RepoToolsSourceRepo {
    param([Parameter(Mandatory)] [string] $Path)

    return (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath "scripts/Publish-WorkflowPackage.ps1") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath "docs/specifications/ai-repo-workflow-commands.md") -PathType Leaf)
}

function Invoke-RepoToolsScript {
    param(
        [Parameter(Mandatory)]
        [string] $Label,

        [Parameter(Mandatory)]
        [string[]] $RelativePaths,

        [Parameter()]
        [string[]] $Arguments = @(),

        [Parameter()]
        [string] $MissingMessage = "not available yet"
    )

    $scriptPath = Resolve-RepoToolsScript -RelativePaths $RelativePaths
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        Write-Host "$Label`: $MissingMessage"
        return
    }

    if ([string]::IsNullOrWhiteSpace($script:PowerShellExe)) {
        Write-Host "$Label`: not available because neither pwsh nor powershell.exe was found"
        return
    }

    Write-Host ""
    Write-Host "Running: $Label"
    Push-Location -LiteralPath $script:RepoRootFull
    try {
        & $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments
    }
    finally {
        Pop-Location
    }
}

function Read-RepoToolsJsonc {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $commonScript = Resolve-RepoToolsScript -RelativePaths @("tools/ai-repo-workflow/scripts/PatchWorkflow.Common.ps1")
    if (-not [string]::IsNullOrWhiteSpace($commonScript)) {
        . $commonScript
        return Read-PatchWorkflowJsoncFile -Path $Path
    }

    $text = Get-Content -LiteralPath $Path -Raw
    $text = [regex]::Replace($text, "(?m)//.*$", "")
    return $text | ConvertFrom-Json
}

function Show-RepoToolsPaths {
    Write-Host ""
    Write-Host "Configured paths"
    Write-Host ""
    Write-Host "Repo root: $script:RepoRootFull"
    Write-Host "Package path: $(Join-Path -Path $script:RepoRootFull -ChildPath 'tools/ai-repo-workflow')"

    $configPaths = @(
        "tools/ai-repo-workflow/config/patch-config.jsonc",
        "tools/ai-repo-workflow/config/snapshot-config.jsonc",
        "tools/ai-repo-workflow/config/watcher-config.jsonc"
    )

    foreach ($relativePath in $configPaths) {
        $configPath = Join-Path -Path $script:RepoRootFull -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            continue
        }

        Write-Host ""
        Write-Host $relativePath
        try {
            $config = Read-RepoToolsJsonc -Path $configPath
            $pathsProperty = $config.PSObject.Properties["paths"]
            if ($null -ne $pathsProperty) {
                $pathsProperty.Value.PSObject.Properties |
                    ForEach-Object { Write-Host "  $($_.Name): $($_.Value)" }
            }
        }
        catch {
            Write-Host "  Unable to read config: $($_.Exception.Message)"
        }
    }
}

function Show-RepoToolsManualCommands {
    Write-Host ""
    Write-Host "Common manual commands"
    Write-Host ""
    Write-Host ".\repo-tools.ps1"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -StrictConventions"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\repo-tools.ps1 -Command PatchWatcher"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\repo-tools.ps1 -Command ApplyPatch"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\repo-tools.ps1 -Command Snapshot"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\repo-tools.ps1 -Command AiPatchZip"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\repo-tools.ps1 -Command GitReviewPatch"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\repo-tools.ps1 -Command ReviewReset"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-RepoHygiene.ps1"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-RepoConventions.ps1"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GitHooks.ps1"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GitHooks.ps1 -ConfigureIdentityGuard"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\repo-tools.ps1 -Command Update"
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\repo-tools.ps1 -Command Status"
    if ($script:IsWorkflowSourceRepo) {
        Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Publish-WorkflowPackage.ps1"
        Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-UpdateRegisteredWorkflowPackagesWizard.ps1"
        Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-UpdateGitIgnoreWizard.ps1"
    }
}

function Show-RepoToolsMenu {
    Write-Host ""
    Write-Host "AI Repo Workflow Tools"
    Write-Host ""
    Write-Host "AI review / approval workflow:"
    Write-Host "  R. Create review-reset packet"
    Write-Host "     Generate a review-only prompt, decision ledger, and approval checkpoint before patching."
    Write-Host ""
    Write-Host "Patch / snapshot workflow:"
    Write-Host "  1. Start patch watcher"
    Write-Host "     Start watching the patch downloads folder so patches can be applied automatically."
    Write-Host "  2. Apply patch"
    Write-Host "     Apply a patch zip from the configured downloads folder or explicit path."
    Write-Host "  3. Create snapshot / review archive"
    Write-Host "     Create a compact snapshot/review zip for ChatGPT or code review."
    Write-Host "  4. Create AI patch zip"
    Write-Host "     Create a repo-relative changed-files zip for the patch workflow."
    Write-Host "  5. Create Git review patch"
    Write-Host "     Create a clean git diff patch file for review."
    Write-Host "  6. Show patch/snapshot/runtime folders"
    Write-Host "     Print configured downloads, snapshots, logs, runtime, and package paths."
    Write-Host ""
    Write-Host "Daily checks:"
    Write-Host "  7. Verify repo"
    Write-Host "     Run the standard repo verification command."
    Write-Host "  8. Check repo hygiene"
    Write-Host "     Scan for private strings, runtime junk, zips, workspace files, large files, and other safety issues."
    Write-Host "  9. Check repo conventions / polish"
    Write-Host "     Check PowerShell naming and repo polish rules. Warning by default."
    Write-Host ""
    Write-Host "Repo setup:"
    Write-Host "  10. Start/bootstrap a repo"
    Write-Host "     Add ai-repo-workflow structure to a new or existing repo."
    Write-Host "  11. Install Git hooks"
    Write-Host "     Install commit-identity and pre-push verification hooks, optionally with the Git identity guard."
    Write-Host ""
    Write-Host "Package management:"
    if ($script:IsWorkflowSourceRepo) {
        Write-Host "  12. Deploy ai-repo-workflow to _tools"
        Write-Host "      Publish this source repo as the deployed package."
        Write-Host "  13. Update repos with deployed ai-repo-workflow"
        Write-Host "      Update registered repos using the deployed package updater."
        Write-Host "  14. Update GitIgnore in a registered repo"
        Write-Host "      Pick a registered repo, merge managed .gitignore defaults, optionally untrack ignored files, and optionally verify."
        Write-Host "  15. Show ai-repo-workflow status/paths"
        Write-Host "      Print status and configured workflow paths."
        Write-Host ""
        Write-Host "Public release workflow:"
        Write-Host "  16. Prepare public release"
        Write-Host "      Planned. Prepare a clean public/client release branch."
        Write-Host "  17. Publish private repo to public repo"
        Write-Host "      Clean export from untrusted private working tree to public repo."
        Write-Host "  18. Generate release changelog"
        Write-Host "      Generate public release notes from meaningful conventional commits."
        Write-Host ""
        Write-Host "Help:"
        Write-Host "  19. Show common manual commands"
    }
    else {
        Write-Host "  12. Update ai-repo-workflow"
        Write-Host "      Get the newest deployed ai-repo-workflow package and update this repo safely."
        Write-Host "  13. Show ai-repo-workflow status/paths"
        Write-Host "      Print status and configured workflow paths."
        Write-Host ""
        Write-Host "Public release workflow:"
        Write-Host "  14. Prepare public release"
        Write-Host "      Planned. Prepare a clean public/client release branch."
        Write-Host "  15. Publish private repo to public repo"
        Write-Host "      Clean export from untrusted private working tree to public repo."
        Write-Host "  16. Generate release changelog"
        Write-Host "      Generate public release notes from meaningful conventional commits."
        Write-Host ""
        Write-Host "Help:"
        Write-Host "  17. Show common manual commands"
    }
    Write-Host "  0. Exit"
    Write-Host ""
}

$script:RepoRootFull = Get-RepoToolsRoot -CandidateRoot $RepoRoot
$script:IsWorkflowSourceRepo = Test-RepoToolsSourceRepo -Path $script:RepoRootFull
$script:PowerShellExe = Get-RepoToolsShell

while ($true) {
    Show-RepoToolsMenu
    $choice = Read-Host "Choose an option"

    switch ($choice) {
        { $_ -match '^(r|R)$' } {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Create review-reset packet" -RelativePaths @("tools/ai-repo-workflow/scripts/New-AiReviewPacket.ps1") -Arguments @("-RepoRoot", $script:RepoRootFull)
            }
            else {
                & (Join-Path -Path $script:RepoRootFull -ChildPath "repo-tools.ps1") -Command ReviewReset
            }
        }
        "1" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Start patch watcher" -RelativePaths @(
                    "tools/ai-repo-workflow/scripts/Start-PatchWatcher.ps1",
                    "tools/ai-repo-workflow/scripts/Watch-Patches.ps1"
                ) -Arguments @("-ConfigPath", (Join-Path -Path $script:RepoRootFull -ChildPath "config/watcher-config.jsonc"))
            }
            else {
                & (Join-Path -Path $script:RepoRootFull -ChildPath "repo-tools.ps1") -Command PatchWatcher
            }
        }
        "2" {
            $patchPath = Read-Host "Patch path (blank = configured downloads folder)"
            if ($script:IsWorkflowSourceRepo) {
                $arguments = @("-ConfigPath", (Join-Path -Path $script:RepoRootFull -ChildPath "config/patch-config.jsonc"))
                if (-not [string]::IsNullOrWhiteSpace($patchPath)) {
                    $arguments += @("-PatchPath", $patchPath)
                }
                Invoke-RepoToolsScript -Label "Apply patch" -RelativePaths @(
                    "tools/ai-repo-workflow/scripts/Invoke-RepoPatch.ps1",
                    "tools/ai-repo-workflow/scripts/patch.ps1"
                ) -Arguments $arguments
            }
            else {
                $repoTools = Join-Path -Path $script:RepoRootFull -ChildPath "repo-tools.ps1"
                if (-not [string]::IsNullOrWhiteSpace($patchPath)) {
                    & $repoTools -Command ApplyPatch -PatchPath $patchPath
                }
                else {
                    & $repoTools -Command ApplyPatch
                }
            }
        }
        "3" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Create snapshot / review archive" -RelativePaths @(
                    "tools/ai-repo-workflow/scripts/New-RepoSnapshot.ps1",
                    "tools/ai-repo-workflow/scripts/snapshot.ps1"
                ) -Arguments @("-ConfigPath", (Join-Path -Path $script:RepoRootFull -ChildPath "config/snapshot-config.jsonc"))
            }
            else {
                & (Join-Path -Path $script:RepoRootFull -ChildPath "repo-tools.ps1") -Command Snapshot
            }
        }
        "4" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Create AI patch zip" -RelativePaths @("tools/ai-repo-workflow/scripts/New-AiPatchZip.ps1") -Arguments @("-IncludeUntracked")
            }
            else {
                & (Join-Path -Path $script:RepoRootFull -ChildPath "repo-tools.ps1") -Command AiPatchZip
            }
        }
        "5" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Create Git review patch" -RelativePaths @("tools/ai-repo-workflow/scripts/New-GitReviewPatch.ps1")
            }
            else {
                & (Join-Path -Path $script:RepoRootFull -ChildPath "repo-tools.ps1") -Command GitReviewPatch
            }
        }
        "6" {
            Show-RepoToolsPaths
        }
        "7" {
            Invoke-RepoToolsScript -Label "Verify repo" -RelativePaths @("scripts/verify.ps1")
        }
        "8" {
            Invoke-RepoToolsScript -Label "Check repo hygiene" -RelativePaths @(
                "scripts/Test-RepoHygiene.ps1",
                "scripts/check-repo-hygiene.ps1",
                "scripts/Check-RepoHygiene.ps1"
            )
        }
        "9" {
            Invoke-RepoToolsScript -Label "Check repo conventions / polish" -RelativePaths @("scripts/Test-RepoConventions.ps1")
        }
        "10" {
            Invoke-RepoToolsScript -Label "Start/bootstrap a repo" -RelativePaths @("scripts/Start-Repo.ps1") -MissingMessage "available from this package repo; run manually with required parameters"
        }
        "11" {
            $arguments = @()
            $configureIdentity = Read-Host "Configure Git identity guard too? [y/N]"
            if ($configureIdentity -match "^(y|yes)$") {
                $arguments += "-ConfigureIdentityGuard"

                $expectedName = Read-Host "Expected git user.name (blank = current repo config)"
                if (-not [string]::IsNullOrWhiteSpace($expectedName)) {
                    $arguments += @("-ExpectedUserName", $expectedName)
                }

                $expectedEmail = Read-Host "Expected git user.email (blank = current repo config)"
                if (-not [string]::IsNullOrWhiteSpace($expectedEmail)) {
                    $arguments += @("-ExpectedUserEmail", $expectedEmail)
                }

                $expectedOrigin = Read-Host "Expected origin URL (blank = current origin)"
                if (-not [string]::IsNullOrWhiteSpace($expectedOrigin)) {
                    $arguments += @("-ExpectedOriginUrl", $expectedOrigin)
                }
            }

            Invoke-RepoToolsScript -Label "Install Git hooks" -RelativePaths @(
                "scripts/Install-GitHooks.ps1",
                "scripts/install-git-hooks.ps1"
            ) -Arguments $arguments
        }
        "12" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Deploy ai-repo-workflow to _tools" -RelativePaths @("scripts/Publish-WorkflowPackage.ps1")
            }
            else {
                & (Join-Path -Path $script:RepoRootFull -ChildPath "repo-tools.ps1") -Command Update
            }
        }
        "13" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Update repos with deployed ai-repo-workflow" -RelativePaths @("scripts/Invoke-UpdateRegisteredWorkflowPackagesWizard.ps1")
            }
            else {
                & (Join-Path -Path $script:RepoRootFull -ChildPath "repo-tools.ps1") -Command Status
                Show-RepoToolsPaths
            }
        }
        "14" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Update GitIgnore in a registered repo" -RelativePaths @("scripts/Invoke-UpdateGitIgnoreWizard.ps1")
            }
            else {
                Invoke-RepoToolsScript -Label "Prepare public release" -RelativePaths @("scripts/Prepare-PublicRelease.ps1") -MissingMessage "not available yet; planned in roadmap"
            }
        }
        "15" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Show ai-repo-workflow status" -RelativePaths @("scripts/Test-WorkflowPackageStatus.ps1")
                Show-RepoToolsPaths
            }
            else {
                Invoke-RepoToolsScript -Label "Publish private repo to public repo" -RelativePaths @("scripts/Publish-Repo.ps1")
            }
        }
        "16" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Prepare public release" -RelativePaths @("scripts/Prepare-PublicRelease.ps1") -MissingMessage "not available yet; planned in roadmap"
            }
            else {
                Invoke-RepoToolsScript -Label "Generate release changelog" -RelativePaths @("scripts/New-ReleaseChangelog.ps1")
            }
        }
        "17" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Publish private repo to public repo" -RelativePaths @("scripts/Publish-Repo.ps1")
            }
            else {
                Show-RepoToolsManualCommands
            }
        }
        "18" {
            if ($script:IsWorkflowSourceRepo) {
                Invoke-RepoToolsScript -Label "Generate release changelog" -RelativePaths @("scripts/New-ReleaseChangelog.ps1")
            }
            else {
                Write-Host "Unknown option: $choice"
            }
        }
        "19" {
            if ($script:IsWorkflowSourceRepo) {
                Show-RepoToolsManualCommands
            }
            else {
                Write-Host "Unknown option: $choice"
            }
        }
        "19" {
            Write-Host "Unknown option: $choice"
        }
        "0" {
            return
        }
        default {
            Write-Host "Unknown option: $choice"
        }
    }

    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}
