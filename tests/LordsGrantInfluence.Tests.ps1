Describe 'YL Prisoners: Lords Grant Influence policy' {
    BeforeAll {
        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:SourceRoot = Join-Path $script:RepoRoot 'src'
    }

    It 'uses the approved one two three highest-tier values' {
        $calculator = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'ImprisonedLordInfluenceCalculator.cs') -Raw

        $calculator | Should -Match 'LordInfluencePerDay\s*=\s*1f'
        $calculator | Should -Match 'ClanLeaderInfluencePerDay\s*=\s*2f'
        $calculator | Should -Match 'KingdomRulerInfluencePerDay\s*=\s*3f'
        $calculator | Should -Match 'imprisonedHero\.IsKingdomLeader'
        $calculator | Should -Match 'imprisonedHero\.IsClanLeader'
        $calculator | Should -Match '!imprisonedHero\.IsLord'
        $calculator | Should -Match 'HashSet<Hero>'
    }

    It 'scans every player-clan custody location and deduplicates heroes' {
        $behavior = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceCampaignBehavior.cs') -Raw

        $behavior | Should -Match 'CampaignEvents\.DailyTickClanEvent'
        $behavior | Should -Match 'clan\s*!=\s*playerClan'
        $behavior | Should -Match 'MobileParty\.All'
        $behavior | Should -Match 'party\s*!=\s*MobileParty\.MainParty'
        $behavior | Should -Match 'party\.ActualClan\s*!=\s*playerClan'
        $behavior | Should -Match 'party\.PrisonRoster\.GetTroopRoster\(\)'
        $behavior | Should -Match 'playerClan\.DungeonPrisonersOfClan'
        $behavior | Should -Match 'hero\?\.IsLord\s*==\s*true'
        $behavior | Should -Match 'HashSet<Hero>'
        $behavior | Should -Match 'GainKingdomInfluenceAction\.ApplyForDefault\(Hero\.MainHero, influence\)'
    }

    It 'does not add unrelated eligibility or saved state' {
        $behavior = Get-Content -LiteralPath (Join-Path $script:SourceRoot 'LordsGrantInfluenceCampaignBehavior.cs') -Raw
        $allSource = Get-ChildItem -LiteralPath $script:SourceRoot -Filter '*.cs' -File |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw } |
            Out-String

        $behavior | Should -Match 'public override void SyncData\(IDataStore dataStore\)\s*\{\s*\}'
        $allSource | Should -Not -Match 'IsAtWar|FactionManager|MapFaction|IsAlive|IsDead|CampaignStateStore|SaveableField'
    }
}
