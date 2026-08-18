using BannerCord.Core;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.ComponentInterfaces;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace YL.Prisoners.CapturedLordsGrantInfluence
{
    /// <summary>
    /// Bannerlord submodule entry point for YL Prisoners: Captured Lords Grant Influence.
    /// </summary>
    /// <remarks>
    /// The submodule performs only composition. It ensures BannerCord is loaded, constructs the small policy and
    /// custody services owned by this module, registers the chained politics model, and registers the diagnostic
    /// campaign behavior. Gameplay logic intentionally remains outside the entry point so each responsibility is
    /// understandable and testable on its own.
    /// </remarks>
    public sealed class CapturedLordsGrantInfluenceSubModule : MBSubModuleBase
    {
        /// <summary>
        /// Ensures the shared BannerCord runtime assembly is available when this optional module loads.
        /// </summary>
        protected override void OnSubModuleLoad()
        {
            base.OnSubModuleLoad();
            BannerCordAssemblyMarker.EnsureLoaded();
        }

        /// <summary>
        /// Registers the prisoner-influence game model and its compatibility diagnostic for campaign games.
        /// </summary>
        /// <param name="game">Bannerlord game instance being started.</param>
        /// <param name="gameStarter">Starter used by the current game type to collect models and behaviors.</param>
        /// <remarks>
        /// <c>AddModel</c> is the important integration point. Bannerlord links MBGameModel replacements through
        /// their inherited <c>BaseModel</c> property, allowing this model to augment the previously registered
        /// ClanPoliticsModel instead of discarding it. The campaign behavior is diagnostic only and awards no
        /// influence itself.
        /// </remarks>
        protected override void OnGameStart(Game game, IGameStarter gameStarter)
        {
            base.OnGameStart(game, gameStarter);

            if (game.GameType is Campaign && gameStarter is CampaignGameStarter campaignGameStarter)
            {
                IImprisonedLordInfluenceCalculator calculator = new ImprisonedLordInfluenceCalculator();
                ClanImprisonedLordProvider prisonerProvider = new ClanImprisonedLordProvider();

                campaignGameStarter.AddModel<ClanPoliticsModel>(
                    new CapturedLordsGrantInfluenceClanPoliticsModel(calculator, prisonerProvider));

                campaignGameStarter.AddBehavior(new CapturedLordsGrantInfluenceCampaignBehavior());
            }
        }
    }
}
