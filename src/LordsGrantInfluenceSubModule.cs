using BannerCord.Core;
using TaleWorlds.CampaignSystem;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace YL.Prisoners.LordsGrantInfluence
{
    /// <summary>Installs the optional campaign behavior when this module is enabled.</summary>
    public sealed class LordsGrantInfluenceSubModule : MBSubModuleBase
    {
        protected override void OnSubModuleLoad()
        {
            base.OnSubModuleLoad();
            BannerCordAssemblyMarker.EnsureLoaded();
        }

        protected override void OnGameStart(Game game, IGameStarter gameStarter)
        {
            base.OnGameStart(game, gameStarter);

            if (game.GameType is Campaign && gameStarter is CampaignGameStarter campaignGameStarter)
            {
                IImprisonedLordInfluenceCalculator calculator = new ImprisonedLordInfluenceCalculator();
                campaignGameStarter.AddBehavior(new LordsGrantInfluenceCampaignBehavior(calculator));
            }
        }
    }
}
