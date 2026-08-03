using System.Collections.Generic;
using TaleWorlds.CampaignSystem;

namespace YL.Prisoners.LordsGrantInfluence
{
    /// <summary>Calculates influence earned from unique imprisoned lords.</summary>
    public interface IImprisonedLordInfluenceCalculator
    {
        float CalculateDailyInfluence(IEnumerable<Hero> imprisonedHeroes);

        float GetDailyInfluence(Hero imprisonedHero);
    }
}
