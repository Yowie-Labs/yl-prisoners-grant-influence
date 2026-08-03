<#
.SYNOPSIS
Runs an external command with durable stdout and stderr diagnostics.

.DESCRIPTION
Defines Invoke-AiRepoDiagnosticCommand for verification, test, build, and
patch.after.ps1 workflows. The helper writes command metadata plus complete
stdout and stderr under artifacts/diagnostics/latest, appends a structured
summary to README.md, echoes captured output to the console, and returns a
structured result. Commands may declare a verification stage so the patch
runner can distinguish verification, test, and build failures after files were
already applied. Nonzero exits throw by default after diagnostics are saved;
-AllowFailure returns the failed result so callers can continue and aggregate
multiple failures.
#>

Set-StrictMode -Version Latest

function Get-AiRepoDiagnosticCommandSafeName {
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

function ConvertTo-AiRepoDiagnosticCommandLineArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Argument
    )

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $escaped = [regex]::Replace($Argument, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Add-AiRepoDiagnosticCommandSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SummaryPath,

        [Parameter(Mandatory)]
        [object] $Result
    )

    if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
        @(
            '# Latest command diagnostics',
            '',
            'AI agents should inspect these files before asking the user to paste terminal output.'
        ) | Set-Content -LiteralPath $SummaryPath -Encoding utf8
    }

    $status = if ([bool] $Result.Succeeded) { 'PASS' } else { 'FAILURE' }
    @(
        '',
        "## $($Result.Name)",
        '',
        "Status: $status",
        "Stage: $($Result.Stage)",
        "Exit code: $($Result.ExitCode)",
        "Started: $($Result.StartedAt.ToString('yyyy-MM-dd HH:mm:ss K'))",
        "Completed: $($Result.CompletedAt.ToString('yyyy-MM-dd HH:mm:ss K'))",
        "Duration ms: $($Result.DurationMilliseconds)",
        "Working directory: $($Result.WorkingDirectory)",
        "Command: $($Result.CommandLine)",
        "Log: $([System.IO.Path]::GetFileName([string] $Result.LogPath))"
    ) | Add-Content -LiteralPath $SummaryPath -Encoding utf8
}


function Add-AiRepoPatchCommandResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Result
    )

    $summaryPath = [Environment]::GetEnvironmentVariable('AI_REPO_PATCH_COMMAND_SUMMARY_PATH')
    if ([string]::IsNullOrWhiteSpace($summaryPath)) {
        return
    }

    $summaryDirectory = Split-Path -Path $summaryPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($summaryDirectory)) {
        New-Item -ItemType Directory -Path $summaryDirectory -Force | Out-Null
    }

    $commands = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
        try {
            $existing = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
            foreach ($command in @($existing.commands)) {
                if ($null -ne $command) {
                    [void] $commands.Add($command)
                }
            }
        }
        catch {
            throw "Patch command summary is invalid JSON: $summaryPath. $($_.Exception.Message)"
        }
    }

    [void] $commands.Add([ordered] @{
        name = [string] $Result.Name
        stage = [string] $Result.Stage
        succeeded = [bool] $Result.Succeeded
        exitCode = [int] $Result.ExitCode
        logPath = [string] $Result.LogPath
        startedUtc = $Result.StartedAt.ToUniversalTime().ToString('o')
        completedUtc = $Result.CompletedAt.ToUniversalTime().ToString('o')
    })

    $failedStages = @(
        $commands |
            Where-Object { -not [bool] $_.succeeded } |
            ForEach-Object { [string] $_.stage } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    [ordered] @{
        schemaVersion = 1
        updatedUtc = [System.DateTimeOffset]::UtcNow.ToString('o')
        failedStages = [string[]] $failedStages
        commands = [object[]] $commands.ToArray()
    } |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $summaryPath -Encoding utf8
}

function Invoke-AiRepoDiagnosticCommand {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter()]
        [string[]] $Arguments = @(),

        [Parameter()]
        [string] $WorkingDirectory,

        [Parameter()]
        [string] $LogFileName,

        [Parameter()]
        [ValidateSet('verification', 'tests', 'build', 'clean', 'other')]
        [string] $Stage = 'verification',

        [Parameter()]
        [switch] $AllowFailure,

        [Parameter()]
        [switch] $NoConsoleEcho
    )

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    }

    $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
    $workingDirectoryFull = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $repoRootFull
    }
    else {
        [System.IO.Path]::GetFullPath($WorkingDirectory)
    }

    if (-not (Test-Path -LiteralPath $workingDirectoryFull -PathType Container)) {
        throw "Diagnostic command '$Name' working directory does not exist: $workingDirectoryFull"
    }

    $latestRoot = Join-Path -Path $repoRootFull -ChildPath 'artifacts/diagnostics/latest'
    New-Item -ItemType Directory -Path $latestRoot -Force | Out-Null

    $safeName = Get-AiRepoDiagnosticCommandSafeName -Name $Name
    $resolvedLogFileName = if ([string]::IsNullOrWhiteSpace($LogFileName)) {
        "$safeName.log"
    }
    else {
        $candidateName = [System.IO.Path]::GetFileName($LogFileName)
        if ([string]::IsNullOrWhiteSpace($candidateName)) {
            "$safeName.log"
        }
        else {
            $candidateName
        }
    }

    $logPath = Join-Path -Path $latestRoot -ChildPath $resolvedLogFileName
    $summaryPath = Join-Path -Path $latestRoot -ChildPath 'README.md'
    $startedAt = Get-Date
    $completedAt = $startedAt
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $exitCode = -1
    $stdout = ''
    $stderr = ''
    $startFailure = $null

    $displayArguments = @(
        foreach ($argument in $Arguments) {
            ConvertTo-AiRepoDiagnosticCommandLineArgument -Argument ([string] $argument)
        }
    )
    $commandLine = (@($FilePath) + $displayArguments) -join ' '

    Write-Host "Running diagnostic command: $Name"
    Write-Host "  Working directory: $workingDirectoryFull"
    Write-Host "  Command          : $commandLine"
    Write-Host "  Artifact log     : $logPath"

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.WorkingDirectory = $workingDirectoryFull
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
            foreach ($argument in $Arguments) {
                [void] $startInfo.ArgumentList.Add([string] $argument)
            }
        }
        else {
            $startInfo.Arguments = $displayArguments -join ' '
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo

        if (-not $process.Start()) {
            throw "Failed to start external command: $FilePath"
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = [int] $process.ExitCode
    }
    catch {
        $startFailure = $_
        $stderr = $_ | Out-String
    }
    finally {
        $stopwatch.Stop()
        $completedAt = Get-Date
    }

    $succeeded = ($null -eq $startFailure -and $exitCode -eq 0)
    $result = [pscustomobject] @{
        Name = $Name
        Stage = $Stage
        FilePath = $FilePath
        Arguments = [string[]] $Arguments
        WorkingDirectory = $workingDirectoryFull
        CommandLine = $commandLine
        StartedAt = $startedAt
        CompletedAt = $completedAt
        DurationMilliseconds = [long] $stopwatch.ElapsedMilliseconds
        ExitCode = $exitCode
        Succeeded = $succeeded
        LogPath = $logPath
        StandardOutput = $stdout
        StandardError = $stderr
    }

    @(
        "Name: $Name",
        "Stage: $Stage",
        "Command: $commandLine",
        "Working directory: $workingDirectoryFull",
        "Started: $($startedAt.ToString('yyyy-MM-dd HH:mm:ss K'))",
        "Completed: $($completedAt.ToString('yyyy-MM-dd HH:mm:ss K'))",
        "Duration ms: $($result.DurationMilliseconds)",
        "Exit code: $exitCode",
        "Status: $(if ($succeeded) { 'PASS' } else { 'FAILURE' })",
        '',
        'STDOUT',
        '------',
        $stdout,
        '',
        'STDERR',
        '------',
        $stderr
    ) | Set-Content -LiteralPath $logPath -Encoding utf8

    Add-AiRepoDiagnosticCommandSummary -SummaryPath $summaryPath -Result $result
    Add-AiRepoPatchCommandResult -Result $result

    if (-not $NoConsoleEcho) {
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Write-Host $stdout
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Host $stderr
        }
    }

    if (-not $succeeded -and -not $AllowFailure) {
        if ($null -ne $startFailure) {
            throw "Diagnostic command '$Name' could not start. See: $logPath"
        }

        throw "Diagnostic command '$Name' failed with exit code $exitCode. See: $logPath"
    }

    return $result
}
