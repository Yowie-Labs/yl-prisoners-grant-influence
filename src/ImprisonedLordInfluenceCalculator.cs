using System;
using System.Collections.Generic;
using TaleWorlds.CampaignSystem;

namespace YL.Prisoners.LordsGrantInfluence
{
    /// <summary>Applies the module's one, two, and three influence policy.</summary>
    public sealed class ImprisonedLordInfluenceCalculator : IImprisonedLordInfluenceCalculator
    {
        public const float LordInfluencePerDay = 1f;
        public const float ClanLeaderInfluencePerDay = 2f;
        public const float KingdomRulerInfluencePerDay = 3f;

        public float CalculateDailyInfluence(IEnumerable<Hero> imprisonedHeroes)
        {
            if (imprisonedHeroes == null)
            {
                throw new ArgumentNullException(nameof(imprisonedHeroes));
            }

            HashSet<Hero> uniqueHeroes = new HashSet<Hero>();
            float influence = 0f;

            foreach (Hero hero in imprisonedHeroes)
            {
                if (hero != null && uniqueHeroes.Add(hero))
                {
                    influence += GetDailyInfluence(hero);
                }
            }

            return influence;
        }

        public float GetDailyInfluence(Hero imprisonedHero)
        {
            if (imprisonedHero == null)
            {
                throw new ArgumentNullException(nameof(imprisonedHero));
            }

            if (!imprisonedHero.IsLord)
            {
                return 0f;
            }

            if (imprisonedHero.IsKingdomLeader)
            {
                return KingdomRulerInfluencePerDay;
            }

            if (imprisonedHero.IsClanLeader)
            {
                return ClanLeaderInfluencePerDay;
            }

            return LordInfluencePerDay;
        }
    }
}
