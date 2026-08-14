Describe 'YL Prisoners: Lords Grant Influence policy' {
    BeforeAll {
        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:SourceRoot = Join-Path $script:RepoRoot 'src'
    }

    It 'uses the approved one two three highest-tier values and exposes one shared breakdown' {
        $calculator = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceCalculator.cs') -Raw
        $breakdown = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceBreakdown.cs') -Raw

        $calculator | Should -Match 'LordInfluencePerDay\s*=\s*1f'
        $calculator | Should -Match 'ClanLeaderInfluencePerDay\s*=\s*2f'
        $calculator | Should -Match 'KingdomRulerInfluencePerDay\s*=\s*3f'
        $calculator | Should -Match 'hero\.IsKingdomLeader'
        $calculator | Should -Match 'hero\.IsClanLeader'
        $calculator | Should -Match '!hero\.IsLord'
        $calculator | Should -Match 'HashSet<Hero>'
        $calculator | Should -Match 'CalculateBreakdown'
        $breakdown | Should -Match 'TotalInfluence\s*=>\s*LordInfluence\s*\+\s*ClanLeaderInfluence\s*\+\s*KingdomRulerInfluence'
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

    It 'adds prisoner influence through the native chained ClanPoliticsModel and tooltip explanations' {
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceClanPoliticsModel.cs') -Raw
        $subModule = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceSubModule.cs') -Raw

        $model | Should -Match 'class LordsGrantInfluenceClanPoliticsModel\s*:\s*ClanPoliticsModel'
        $model | Should -Match 'BaseModel\.CalculateInfluenceChange\(clan, includeDescriptions\)'
        $model | Should -Match 'Captured nobles \(\{COUNT\}\)'
        $model | Should -Match 'Captured clan leaders \(\{COUNT\}\)'
        $model | Should -Match 'Captured kingdom rulers \(\{COUNT\}\)'
        $model | Should -Match 'result\.Add\(influence, description, null\)'
        $model | Should -Match 'if \(count <= 0 \|\| influence == 0f\)'
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

    It 'documents the model-chain and compatibility behavior for modders' {
        $model = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceClanPoliticsModel.cs') -Raw
        $behavior = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceCampaignBehavior.cs') -Raw
        $provider = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'PlayerClanImprisonedLordProvider.cs') -Raw

        $model | Should -Match '/// <summary>'
        $model | Should -Match '/// <remarks>'
        $model | Should -Match 'BaseModel'
        $model | Should -Match 'native daily influence tick and native influence tooltip'
        $behavior | Should -Match '/// <summary>'
        $behavior | Should -Match '/// <remarks>'
        $behavior | Should -Match 'one-time runtime check'
        $provider | Should -Match '/// <summary>'
        $provider | Should -Match 'Bannerlord stores prisoners in more than one place'
    }
}
