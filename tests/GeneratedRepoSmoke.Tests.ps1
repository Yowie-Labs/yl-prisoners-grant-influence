Describe 'Generated repository scaffold' {
    BeforeAll {
        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    }

    It 'has reference-mode workflow entry points without vendored implementation files' {
        foreach ($relativePath in @(
            'repo-tools.ps1',
            'scripts/verify.ps1',
            'scripts/test.ps1',
            'config/ai-repo-workflow.reference.jsonc',
            'config/ai-repo-workflow/patch-config.jsonc',
            'config/ai-repo-workflow/snapshot-config.jsonc',
            'config/ai-repo-workflow/test-config.jsonc'
        )) {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot $relativePath) -PathType Leaf | Should -BeTrue
        }

        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tools/ai-repo-workflow') | Should -BeFalse
    }

    It 'is an independently installable BannerCord-dependent module' {
        $project = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'src/YL.Prisoners.LordsGrantInfluence.csproj') -Raw
        $manifest = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'module/SubModule.xml') -Raw
        $subModule = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'src/LordsGrantInfluenceSubModule.cs') -Raw

        $project | Should -Match 'PackageReference Include="BannerCord\.Core"'
        $project | Should -Match '<Version>0\.0\.5</Version>'
        $project | Should -Match '<ExcludeAssets>runtime</ExcludeAssets>'
        $project | Should -Match 'EnsureBannerCordRuntimeIsNotPrivatelyCopied'
        $manifest | Should -Match '<Id value="YLPrisonersLordsGrantInfluence" />'
        $manifest | Should -Match '<DependedModule Id="BannerCord" DependentVersion="v0\.0\.5" />'
        $subModule | Should -Match 'BannerCordAssemblyMarker\.EnsureLoaded\(\)'
        $subModule | Should -Match 'campaignGameStarter\.AddBehavior'
    }


    It 'builds only its own assembly into the canonical module directory' {
        $project = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'src/YL.Prisoners.LordsGrantInfluence.csproj') -Raw
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'module/SubModule.xml') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'content/SubModule.xml') | Should -BeFalse
        $project | Should -Match '\.\.\\module\\bin\\Win64_Shipping_Client'
        $project | Should -Match '<ExcludeAssets>runtime</ExcludeAssets>'
        $project | Should -Match 'EnsureBannerCordRuntimeIsNotPrivatelyCopied'
    }
}
