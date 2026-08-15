Describe 'YL Prisoners: Lords Grant Influence policy' {
    BeforeAll {
        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:SourceRoot = Join-Path $script:RepoRoot 'src'
        $script:ModuleRoot = Join-Path $script:RepoRoot 'module'
    }

    It 'ships half-strength configurable defaults and exposes one shared breakdown' {
        $calculator = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceCalculator.cs') -Raw
        $breakdown = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceBreakdown.cs') -Raw
        [xml] $settings = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'config/LordsGrantInfluence.xml') -Raw

        $calculator | Should -Match 'DefaultLordInfluencePerDay\s*=\s*0\.5f'
        $calculator | Should -Match 'DefaultClanLeaderInfluencePerDay\s*=\s*1f'
        $calculator | Should -Match 'DefaultKingdomRulerInfluencePerDay\s*=\s*1\.5f'
        $calculator | Should -Match 'lordCount \* LordInfluencePerDay'
        $calculator | Should -Match 'clanLeaderCount \* ClanLeaderInfluencePerDay'
        $calculator | Should -Match 'kingdomRulerCount \* KingdomRulerInfluencePerDay'
        $calculator | Should -Match 'hero\.IsKingdomLeader'
        $calculator | Should -Match 'hero\.IsClanLeader'
        $calculator | Should -Match '!hero\.IsLord'
        $calculator | Should -Match 'HashSet<Hero>'
        $calculator | Should -Match 'CalculateBreakdown'
        $breakdown | Should -Match 'TotalInfluence\s*=>\s*LordInfluence\s*\+\s*ClanLeaderInfluence\s*\+\s*KingdomRulerInfluence'

        $settings.LordsGrantInfluenceSettings.InfluencePerDay.OrdinaryLord.value | Should -Be '0.5'
        $settings.LordsGrantInfluenceSettings.InfluencePerDay.ClanLeader.value | Should -Be '1.0'
        $settings.LordsGrantInfluenceSettings.InfluencePerDay.KingdomRuler.value | Should -Be '1.5'
    }

    It 'loads player-editable XML safely without adding save state' {
        $calculator = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceCalculator.cs') -Raw
        $settingsPath = Join-Path $script:ModuleRoot 'config/LordsGrantInfluence.xml'
        [xml] $settings = Get-Content -LiteralPath $settingsPath -Raw

        Test-Path -LiteralPath $settingsPath -PathType Leaf | Should -BeTrue
        $settings.LordsGrantInfluenceSettings.InfluencePerDay.OrdinaryLord | Should -Not -BeNullOrEmpty
        $settings.LordsGrantInfluenceSettings.InfluencePerDay.ClanLeader | Should -Not -BeNullOrEmpty
        $settings.LordsGrantInfluenceSettings.InfluencePerDay.KingdomRuler | Should -Not -BeNullOrEmpty

        $calculator | Should -Match 'LordsGrantInfluence\.xml'
        $calculator | Should -Match 'XmlDocument'
        $calculator | Should -Match 'CultureInfo\.InvariantCulture'
        $calculator | Should -Match 'float\.TryParse'
        $calculator | Should -Match 'parsedValue < 0f'
        $calculator | Should -Match 'float\.IsNaN\(parsedValue\)'
        $calculator | Should -Match 'float\.IsInfinity\(parsedValue\)'
        $calculator | Should -Match 'InformationManager\.DisplayMessage'
        $calculator | Should -Match 'using defaults'
    }

    It 'scans every player-clan custody location and deduplicates heroes' {
        $provider = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'PlayerClanImprisonedLordProvider.cs') -Raw

        $provider | Should -Match 'MobileParty\.All'
        $provider | Should -Match 'party\s*!=\s*MobileParty\.MainParty'
        $provider | Should -Match 'party\.ActualClan\s*!=\s*playerClan'
        $provider | Should -Match 'party\.PrisonRoster\.GetTroopRoster\(\)'
        $provider | Should -Match 'playerClan\.DungeonPrisonersOfClan'
        $provider | Should -Match 'hero\?\.IsLord\s*==\s*true'
        $provider | Should -Match 'HashSet<Hero>'
    }

    It 'mutates the ExplainedNumber by reference so tooltip rows and the numeric total cannot diverge' {
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceClanPoliticsModel.cs') -Raw
        $subModule = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceSubModule.cs') -Raw

        $model | Should -Match 'class LordsGrantInfluenceClanPoliticsModel\s*:\s*ClanPoliticsModel'
        $model | Should -Match 'BaseModel\.CalculateInfluenceChange\(clan, includeDescriptions\)'
        $model | Should -Match 'Captured lords \(\{COUNT\}\)'
        $model | Should -Match 'Captured clan leaders \(\{COUNT\}\)'
        $model | Should -Match 'Captured kingdom rulers \(\{COUNT\}\)'
        $model | Should -Match 'AddInfluenceLine\(\s*ref result,'
        $model | Should -Match 'private static void AddInfluenceLine\(\s*ref ExplainedNumber result,'
        $model | Should -Match 'result\.Add\(influence, description, null\)'
        $model | Should -Match 'if \(count <= 0 \|\| influence == 0f\)'
        $model | Should -Not -Match 'private static void AddInfluenceLine\(\s*ExplainedNumber result,'
        $model | Should -Match 'ExplainedNumber.*value type'
        $model | Should -Match 'BaseModel\.CalculateSupportForPolicyInClan'
        $model | Should -Match 'BaseModel\.CalculateRelationshipChangeWithSponsor'
        $model | Should -Match 'BaseModel\.GetInfluenceRequiredToOverrideKingdomDecision'
        $model | Should -Match 'BaseModel\.CanHeroBeGovernor'
        $subModule | Should -Match 'campaignGameStarter\.AddModel'
        $subModule | Should -Match 'new LordsGrantInfluenceClanPoliticsModel\(calculator, prisonerProvider\)'
    }

    It 'warns once when the final active politics model does not reach this model' {
        $behavior = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceCampaignBehavior.cs') -Raw
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceClanPoliticsModel.cs') -Raw

        $behavior | Should -Match 'CampaignEvents\.HourlyTickEvent'
        $behavior | Should -Match 'Campaign\.Current\?\.Models\?\.ClanPoliticsModel'
        $behavior | Should -Match 'LordsGrantInfluenceClanPoliticsModel\.InvocationCount'
        $behavior | Should -Match 'activeModel\.CalculateInfluenceChange\(playerClan, false\)'
        $behavior | Should -Match 'compatibilityCheckCompleted\s*=\s*true'
        $behavior | Should -Match 'InformationManager\.DisplayMessage\(new InformationMessage\(message\)\)'
        $behavior | Should -Match 'activeModel\.GetType\(\)\.FullName'
        $model | Should -Match 'Interlocked\.Increment\(ref invocationCount\)'
    }

    It 'does not award influence from a parallel daily event or add unrelated eligibility or saved state' {
        $behavior = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceCampaignBehavior.cs') -Raw
        $allSource = Get-ChildItem -LiteralPath $script:SourceRoot -Filter '*.cs' -File |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
            Out-String

        $behavior | Should -Match 'public override void SyncData\(IDataStore dataStore\)\s*\{\s*\}'
        $allSource | Should -Not -Match 'DailyTickClanEvent|GainKingdomInfluenceAction\.ApplyForDefault'
        $allSource | Should -Not -Match 'IsAtWar|FactionManager|MapFaction|IsAlive|IsDead|CampaignStateStore|SaveableField'
    }

    It 'documents the model-chain configuration and compatibility behavior for modders' {
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceClanPoliticsModel.cs') -Raw
        $calculator = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceCalculator.cs') -Raw
        $behavior = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceCampaignBehavior.cs') -Raw
        $provider = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'PlayerClanImprisonedLordProvider.cs') -Raw
        $specification = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs/specifications/Lords_Grant_Influence.md') -Raw

        $model | Should -Match '/// <summary>'
        $model | Should -Match '/// <remarks>'
        $model | Should -Match 'BaseModel'
        $model | Should -Match 'native daily influence tick and native influence tooltip'
        $calculator | Should -Match 'module/config/LordsGrantInfluence\.xml'
        $calculator | Should -Match 'Configuration is loaded once'
        $behavior | Should -Match '/// <summary>'
        $behavior | Should -Match '/// <remarks>'
        $behavior | Should -Match 'one-time runtime check'
        $provider | Should -Match '/// <summary>'
        $provider | Should -Match 'Bannerlord stores prisoners in more than one place'
        $specification | Should -Match 'ExplainedNumber.*value type'
        $specification | Should -Match '0\.5 / 1\.0 / 1\.5'
    }
}
