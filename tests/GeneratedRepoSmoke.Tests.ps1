Describe "Generated repository scaffold" {
    BeforeAll {
        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath ".."))
    }

    It "has the reference-mode workflow entry points" {
        foreach ($relativePath in @(
            "repo-tools.ps1",
            "scripts/verify.ps1",
            "scripts/test.ps1",
            "config/ai-repo-workflow.reference.jsonc",
            "config/ai-repo-workflow/patch-config.jsonc",
            "config/ai-repo-workflow/snapshot-config.jsonc",
            "config/ai-repo-workflow/watcher-config.jsonc",
            "config/ai-repo-workflow/test-config.jsonc"
        )) {
            Test-Path -LiteralPath (Join-Path -Path $script:RepoRoot -ChildPath $relativePath) -PathType Leaf | Should -BeTrue
        }
    }

    It "does not vendor ai-repo-workflow implementation files" {
        Test-Path -LiteralPath (Join-Path -Path $script:RepoRoot -ChildPath "tools/ai-repo-workflow") | Should -BeFalse
    }
}
