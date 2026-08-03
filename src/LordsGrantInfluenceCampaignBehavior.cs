using System;
using System.Collections.Generic;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;
using TaleWorlds.Core;

namespace YL.Prisoners.LordsGrantInfluence
{
    /// <summary>Awards daily influence for lords held anywhere by the player clan.</summary>
    public sealed class LordsGrantInfluenceCampaignBehavior : CampaignBehaviorBase
    {
        private readonly IImprisonedLordInfluenceCalculator calculator;

        public LordsGrantInfluenceCampaignBehavior(IImprisonedLordInfluenceCalculator calculator)
        {
            this.calculator = calculator ?? throw new ArgumentNullException(nameof(calculator));
        }

        public override void RegisterEvents()
        {
            CampaignEvents.DailyTickClanEvent.AddNonSerializedListener(this, OnDailyTickClan);
        }

        public override void SyncData(IDataStore dataStore)
        {
        }

        private void OnDailyTickClan(Clan clan)
        {
            Clan playerClan = Clan.PlayerClan;
            if (playerClan == null || clan != playerClan)
            {
                return;
            }

            HashSet<Hero> imprisonedLords = new HashSet<Hero>();
            AddPartyPrisoners(playerClan, imprisonedLords);
            AddDungeonPrisoners(playerClan, imprisonedLords);

            float influence = calculator.CalculateDailyInfluence(imprisonedLords);
            if (influence > 0f)
            {
                GainKingdomInfluenceAction.ApplyForDefault(Hero.MainHero, influence);
            }
        }

        private static void AddPartyPrisoners(Clan playerClan, ISet<Hero> imprisonedLords)
        {
            foreach (MobileParty party in MobileParty.All)
            {
                if (party == null || (party != MobileParty.MainParty && party.ActualClan != playerClan))
                {
                    continue;
                }

                foreach (TroopRosterElement element in party.PrisonRoster.GetTroopRoster())
                {
                    AddLord(element.Character, imprisonedLords);
                }
            }
        }

        private static void AddDungeonPrisoners(Clan playerClan, ISet<Hero> imprisonedLords)
        {
            foreach (CharacterObject prisoner in playerClan.DungeonPrisonersOfClan)
            {
                AddLord(prisoner, imprisonedLords);
            }
        }

        private static void AddLord(CharacterObject prisoner, ISet<Hero> imprisonedLords)
        {
            if (prisoner?.IsHero != true)
            {
                return;
            }

            Hero hero = prisoner.HeroObject;
            if (hero?.IsLord == true)
            {
                imprisonedLords.Add(hero);
            }
        }
    }
}
