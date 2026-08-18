Describe 'YL Prisoners: Captured Lords Grant Influence policy' {
    BeforeAll {
        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:SourceRoot = Join-Path $script:RepoRoot 'src'
        $script:ModuleRoot = Join-Path $script:RepoRoot 'module'
    }

    It 'ships half-strength configurable defaults and AI parity by default' {
        $calculator = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceCalculator.cs') -Raw
        $interface = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'IImprisonedLordInfluenceCalculator.cs') -Raw
        $breakdown = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceBreakdown.cs') -Raw
        [xml] $settings = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'config/CapturedLordsGrantInfluence.xml') -Raw

        $calculator | Should -Match 'DefaultLordInfluencePerDay\s*=\s*0\.5f'
        $calculator | Should -Match 'DefaultClanLeaderInfluencePerDay\s*=\s*1f'
        $calculator | Should -Match 'DefaultKingdomRulerInfluencePerDay\s*=\s*1\.5f'
        $calculator | Should -Match 'DefaultApplyToAiClans\s*=\s*true'
        $calculator | Should -Match 'lordCount \* LordInfluencePerDay'
        $calculator | Should -Match 'clanLeaderCount \* ClanLeaderInfluencePerDay'
        $calculator | Should -Match 'kingdomRulerCount \* KingdomRulerInfluencePerDay'
        $calculator | Should -Match 'hero\.IsKingdomLeader'
        $calculator | Should -Match 'hero\.IsClanLeader'
        $calculator | Should -Match '!hero\.IsLord'
        $calculator | Should -Match 'HashSet<Hero>'
        $calculator | Should -Match 'CalculateBreakdown'
        $interface | Should -Match 'bool ApplyToAiClans \{ get; \}'
        $breakdown | Should -Match 'TotalInfluence\s*=>\s*LordInfluence\s*\+\s*ClanLeaderInfluence\s*\+\s*KingdomRulerInfluence'

        $settings.CapturedLordsGrantInfluenceSettings.ApplyToAiClans | Should -Be 'true'
        $settings.CapturedLordsGrantInfluenceSettings.InfluencePerDay.OrdinaryLord.value | Should -Be '0.5'
        $settings.CapturedLordsGrantInfluenceSettings.InfluencePerDay.ClanLeader.value | Should -Be '1.0'
        $settings.CapturedLordsGrantInfluenceSettings.InfluencePerDay.KingdomRuler.value | Should -Be '1.5'
    }

    It 'loads the canonical XML safely without adding save state' {
        $calculator = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceCalculator.cs') -Raw
        $settingsPath = Join-Path $script:ModuleRoot 'config/CapturedLordsGrantInfluence.xml'
        [xml] $settings = Get-Content -LiteralPath $settingsPath -Raw

        Test-Path -LiteralPath $settingsPath -PathType Leaf | Should -BeTrue
        $settings.CapturedLordsGrantInfluenceSettings.InfluencePerDay.OrdinaryLord | Should -Not -BeNullOrEmpty
        $settings.CapturedLordsGrantInfluenceSettings.InfluencePerDay.ClanLeader | Should -Not -BeNullOrEmpty
        $settings.CapturedLordsGrantInfluenceSettings.InfluencePerDay.KingdomRuler | Should -Not -BeNullOrEmpty

        $calculator | Should -Match 'SettingsFileName\s*=\s*"CapturedLordsGrantInfluence\.xml"'
        $calculator | Should -Match 'XmlDocument'
        $calculator | Should -Match 'CultureInfo\.InvariantCulture'
        $calculator | Should -Match 'float\.TryParse'
        $calculator | Should -Match 'parsedValue < 0f'
        $calculator | Should -Match 'float\.IsNaN\(parsedValue\)'
        $calculator | Should -Match 'float\.IsInfinity\(parsedValue\)'
        $calculator | Should -Match 'ReadBooleanAttribute\(root, "ApplyToAiClans", DefaultApplyToAiClans\)'
        $calculator | Should -Match 'bool\.TryParse'
        $calculator | Should -Match 'InformationManager\.DisplayMessage'
        $calculator | Should -Match 'using defaults'
    }

    It 'scans the evaluated clan native custody locations and deduplicates heroes' {
        $provider = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ClanImprisonedLordProvider.cs') -Raw

        $provider | Should -Match 'class ClanImprisonedLordProvider'
        $provider | Should -Match 'GetImprisonedLords\(Clan clan\)'
        $provider | Should -Match 'MobileParty\.All'
        $provider | Should -Match 'party\.ActualClan\s*!=\s*clan'
        $provider | Should -Match 'clan\s*==\s*Clan\.PlayerClan\s*&&\s*party\s*==\s*MobileParty\.MainParty'
        $provider | Should -Match 'party\.PrisonRoster\.GetTroopRoster\(\)'
        $provider | Should -Match 'clan\.DungeonPrisonersOfClan'
        $provider | Should -Match 'hero\?\.IsLord\s*==\s*true'
        $provider | Should -Match 'HashSet<Hero>'
        $provider | Should -Not -Match 'party\.ActualClan\s*!=\s*playerClan'
    }

    It 'applies captured-lord influence to AI clans unless XML disables AI parity' {
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'CapturedLordsGrantInfluenceClanPoliticsModel.cs') -Raw

        $model | Should -Match 'Clan\? playerClan = Clan\.PlayerClan'
        $model | Should -Match 'bool isPlayerClan = playerClan != null && clan == playerClan'
        $model | Should -Match 'if \(!isPlayerClan && !calculator\.ApplyToAiClans\)'
        $model | Should -Match 'prisonerProvider\.GetImprisonedLords\(clan\)'
        $model | Should -Not -Match 'if \(playerClan == null \|\| clan != playerClan\)'
    }

    It 'mutates the ExplainedNumber by reference so tooltip rows and the numeric total cannot diverge' {
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'CapturedLordsGrantInfluenceClanPoliticsModel.cs') -Raw
        $subModule = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'CapturedLordsGrantInfluenceSubModule.cs') -Raw

        $model | Should -Match 'class CapturedLordsGrantInfluenceClanPoliticsModel\s*:\s*ClanPoliticsModel'
        $model | Should -Match 'BaseModel\.CalculateInfluenceChange\(clan, includeDescriptions\)'
        $model | Should -Match 'Captured lords \(\{COUNT\}\)'
        $model | Should -Match 'Captured clan leaders \(\{COUNT\}\)'
        $model | Should -Match 'Captured kingdom rulers \(\{COUNT\}\)'
        $model | Should -Match 'AddInfluenceLine\(\s*ref result,'
        $model | Should -Match 'private static void AddInfluenceLine\(\s*ref ExplainedNumber result,'
        $model | Should -Match 'result\.Add\(influence, description, null\)'
        $model | Should -Not -Match 'private static void AddInfluenceLine\(\s*ExplainedNumber result,'
        $model | Should -Match 'ExplainedNumber.*value type'
        $model | Should -Match 'BaseModel\.CalculateSupportForPolicyInClan'
        $model | Should -Match 'BaseModel\.CalculateRelationshipChangeWithSponsor'
        $model | Should -Match 'BaseModel\.GetInfluenceRequiredToOverrideKingdomDecision'
        $model | Should -Match 'BaseModel\.CanHeroBeGovernor'
        $subModule | Should -Match 'campaignGameStarter\.AddModel'
    }

    It 'uses the Captured Lords identity consistently across runtime and project surfaces' {
        [xml] $module = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'SubModule.xml') -Raw
        [xml] $project = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'YL.Prisoners.CapturedLordsGrantInfluence.csproj') -Raw
        $allSource = Get-ChildItem -LiteralPath $script:SourceRoot -Filter '*.cs' -File |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
            Out-String

        $module.Module.Id.value | Should -Be 'YL.Prisoners.CapturedLordsGrantInfluence'
        $module.Module.Name.value | Should -Be 'YL Prisoners: Captured Lords Grant Influence'
        $module.Module.Version.value | Should -Be 'v0.1.0'
        $module.Module.SubModules.SubModule.DLLName.value | Should -Be 'YL.Prisoners.CapturedLordsGrantInfluence.dll'
        $module.Module.SubModules.SubModule.SubModuleClassType.value | Should -Be 'YL.Prisoners.CapturedLordsGrantInfluence.CapturedLordsGrantInfluenceSubModule'

        $project.Project.PropertyGroup.RootNamespace | Should -Be 'YL.Prisoners.CapturedLordsGrantInfluence'
        $project.Project.PropertyGroup.AssemblyName | Should -Be 'YL.Prisoners.CapturedLordsGrantInfluence'
        $allSource | Should -Not -Match 'namespace YL\.Prisoners\.LordsGrantInfluence'
        $allSource | Should -Match 'namespace YL\.Prisoners\.CapturedLordsGrantInfluence'
        $project.OuterXml | Should -Match 'RemovePreRenameAssemblyOutput'
        $project.OuterXml | Should -Match 'YL\.Prisoners\.LordsGrantInfluence\.dll'
        $project.OuterXml | Should -Not -Match '<Delete Files="\$\(TargetDir\)YL\.Prisoners\.CapturedLordsGrantInfluence\.dll'
    }

    It 'warns once when the final active politics model does not reach this model' {
        $behavior = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'CapturedLordsGrantInfluenceCampaignBehavior.cs') -Raw
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'CapturedLordsGrantInfluenceClanPoliticsModel.cs') -Raw

        $behavior | Should -Match 'CampaignEvents\.HourlyTickEvent'
        $behavior | Should -Match 'Campaign\.Current\?\.Models\?\.ClanPoliticsModel'
        $behavior | Should -Match 'CapturedLordsGrantInfluenceClanPoliticsModel\.InvocationCount'
        $behavior | Should -Match 'activeModel\.CalculateInfluenceChange\(playerClan, false\)'
        $behavior | Should -Match 'compatibilityCheckCompleted\s*=\s*true'
        $behavior | Should -Match 'YL Prisoners: Captured Lords Grant Influence compatibility warning'
        $behavior | Should -Match 'InformationManager\.DisplayMessage\(new InformationMessage\(message\)\)'
        $behavior | Should -Match 'activeModel\.GetType\(\)\.FullName'
        $model | Should -Match 'Interlocked\.Increment\(ref invocationCount\)'
    }

    It 'does not award influence from a parallel daily event or add custom saved state' {
        $behavior = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'CapturedLordsGrantInfluenceCampaignBehavior.cs') -Raw
        $allSource = Get-ChildItem -LiteralPath $script:SourceRoot -Filter '*.cs' -File |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
            Out-String

        $behavior | Should -Match 'public override void SyncData\(IDataStore dataStore\)\s*\{\s*\}'
        $allSource | Should -Not -Match 'DailyTickClanEvent|GainKingdomInfluenceAction\.ApplyForDefault'
        $allSource | Should -Not -Match 'CampaignStateStore|SaveableField'
        $allSource | Should -Not -Match 'HarmonyLib|HarmonyPatch'
    }

    It 'documents AI parity, rename safety, configuration, and the ExplainedNumber invariant' {
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'CapturedLordsGrantInfluenceClanPoliticsModel.cs') -Raw
        $calculator = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceCalculator.cs') -Raw
        $specification = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs/specifications/Captured_Lords_Grant_Influence.md') -Raw
        $architecture = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs/Architecture.md') -Raw

        $model | Should -Match '/// <summary>'
        $model | Should -Match 'BaseModel'
        $calculator | Should -Match 'module/config/CapturedLordsGrantInfluence\.xml'
        $specification | Should -Match 'ApplyToAiClans'
        $specification | Should -Match 'NPC clans'
        $specification | Should -Match 'ExplainedNumber.*value type'
        $specification | Should -Match '0\.5 / 1\.0 / 1\.5'
        $specification | Should -Match 'module set changed'
        $architecture | Should -Match 'AI'
    }

    It 'uses only the canonical repository and configuration filenames' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'YL.Prisoners.CapturedLordsGrantInfluence.sln') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:SourceRoot 'YL.Prisoners.CapturedLordsGrantInfluence.csproj') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:ModuleRoot 'config/CapturedLordsGrantInfluence.xml') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'docs/specifications/Captured_Lords_Grant_Influence.md') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tests/CapturedLordsGrantInfluence.Tests.ps1') -PathType Leaf | Should -BeTrue

        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'YL.Prisoners.LordsGrantInfluence.sln') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:SourceRoot 'YL.Prisoners.LordsGrantInfluence.csproj') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:ModuleRoot 'config/LordsGrantInfluence.xml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tests/LordsGrantInfluence.Tests.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceClanPoliticsModel.cs') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceCampaignBehavior.cs') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceSubModule.cs') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:SourceRoot 'PlayerClanImprisonedLordProvider.cs') | Should -BeFalse
    }

}
