using System;
using System.Collections.Generic;
using TaleWorlds.CampaignSystem;

namespace YL.Prisoners.LordsGrantInfluence
{
    /// <summary>
    /// Applies the module's one-, two-, and three-influence prisoner policy.
    /// </summary>
    /// <remarks>
    /// The policy is intentionally small and mechanical: an ordinary lord grants 1 influence per day, a clan
    /// leader grants 2, and a kingdom ruler grants 3. Only the highest matching tier applies. The calculator does
    /// not care about war state, faction hostility, whether the hero is alive, or how the prisoner was acquired;
    /// those exclusions are deliberate product rules rather than missing checks.
    /// </remarks>
    public sealed class ImprisonedLordInfluenceCalculator : IImprisonedLordInfluenceCalculator
    {
        /// <summary>Daily influence granted by an ordinary imprisoned lord.</summary>
        public const float LordInfluencePerDay = 1f;

        /// <summary>Daily influence granted by an imprisoned clan leader who is not a kingdom ruler.</summary>
        public const float ClanLeaderInfluencePerDay = 2f;

        /// <summary>Daily influence granted by an imprisoned kingdom ruler.</summary>
        public const float KingdomRulerInfluencePerDay = 3f;

        /// <inheritdoc />
        public ImprisonedLordInfluenceBreakdown CalculateBreakdown(IEnumerable<Hero> imprisonedHeroes)
        {
            if (imprisonedHeroes == null)
            {
                throw new ArgumentNullException(nameof(imprisonedHeroes));
            }

            // A prisoner may be discoverable through more than one Bannerlord collection. The HashSet makes the
            // "one unique imprisoned lord, once per day" rule true regardless of how the game exposes custody.
            HashSet<Hero> uniqueHeroes = new HashSet<Hero>();
            int lordCount = 0;
            int clanLeaderCount = 0;
            int kingdomRulerCount = 0;

            foreach (Hero hero in imprisonedHeroes)
            {
                if (hero == null || !uniqueHeroes.Add(hero) || !hero.IsLord)
                {
                    continue;
                }

                // Check the most valuable tier first. Kingdom rulers are normally also clan leaders, so reversing
                // this order would incorrectly reduce a ruler from 3 influence to 2 influence.
                if (hero.IsKingdomLeader)
                {
                    kingdomRulerCount++;
                }
                else if (hero.IsClanLeader)
                {
                    clanLeaderCount++;
                }
                else
                {
                    lordCount++;
                }
            }

            return new ImprisonedLordInfluenceBreakdown(
                lordCount,
                lordCount * LordInfluencePerDay,
                clanLeaderCount,
                clanLeaderCount * ClanLeaderInfluencePerDay,
                kingdomRulerCount,
                kingdomRulerCount * KingdomRulerInfluencePerDay);
        }

        /// <inheritdoc />
        public float CalculateDailyInfluence(IEnumerable<Hero> imprisonedHeroes)
        {
            return CalculateBreakdown(imprisonedHeroes).TotalInfluence;
        }

        /// <inheritdoc />
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
