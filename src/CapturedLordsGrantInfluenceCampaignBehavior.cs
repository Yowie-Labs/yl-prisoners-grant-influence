using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.ComponentInterfaces;
using TaleWorlds.Library;

namespace YL.Prisoners.CapturedLordsGrantInfluence
{
    /// <summary>
    /// Performs a one-time runtime check that the active politics-model chain still reaches this module.
    /// </summary>
    /// <remarks>
    /// This behavior does not award influence. The actual gameplay rule lives entirely in
    /// <see cref="CapturedLordsGrantInfluenceClanPoliticsModel"/> so Bannerlord's native daily influence tick and native
    /// influence tooltip share one calculation.
    ///
    /// Bannerlord allows multiple mods to extend a game model by calling their inherited <c>BaseModel</c>. A mod
    /// loaded above this one can accidentally break the chain by returning its own calculation without delegating.
    /// That failure is impossible to prevent safely from here, but it can be detected. On the first suitable hourly
    /// tick we invoke the currently active model once and verify that our model's invocation counter advanced. If it
    /// did not, the player receives one diagnostic message naming the active model so they know why the bonus is not
    /// functioning.
    /// </remarks>
    public sealed class CapturedLordsGrantInfluenceCampaignBehavior : CampaignBehaviorBase
    {
        private bool compatibilityCheckCompleted;

        /// <summary>
        /// Registers the one-time compatibility probe on Bannerlord's ordinary hourly campaign tick.
        /// </summary>
        /// <remarks>
        /// The hourly tick is intentionally used instead of checking during module loading. By the time campaign
        /// simulation starts, every enabled module has had an opportunity to register its game models, so the check
        /// observes the final active <see cref="ClanPoliticsModel"/> rather than an incomplete startup chain.
        /// </remarks>
        public override void RegisterEvents()
        {
            CampaignEvents.HourlyTickEvent.AddNonSerializedListener(this, OnHourlyTick);
        }

        /// <summary>
        /// Intentionally persists no custom data.
        /// </summary>
        /// <param name="dataStore">Bannerlord save-game data store supplied to campaign behaviors.</param>
        /// <remarks>
        /// The compatibility flag is session-only and may safely run again after loading a save in a later session.
        /// Keeping this method empty also preserves the module's rule that it must not create custom save data.
        /// </remarks>
        public override void SyncData(IDataStore dataStore)
        {
        }

        /// <summary>
        /// Runs the compatibility probe once after a player clan and active politics model are available.
        /// </summary>
        private void OnHourlyTick()
        {
            if (compatibilityCheckCompleted)
            {
                return;
            }

            Clan? playerClan = Clan.PlayerClan;
            ClanPoliticsModel? activeModel = Campaign.Current?.Models?.ClanPoliticsModel;
            if (playerClan == null || activeModel == null)
            {
                // Campaign startup can briefly exist without all runtime objects. Leave the check pending and try
                // again on the next hour instead of producing a false incompatibility warning.
                return;
            }

            long invocationCountBefore = CapturedLordsGrantInfluenceClanPoliticsModel.InvocationCount;

            // This call is intentionally read-only. CalculateInfluenceChange computes an ExplainedNumber; it does
            // not itself grant influence. Calling the final active model synchronously lets us observe whether that
            // model delegates through BaseModel far enough to reach CapturedLordsGrantInfluenceClanPoliticsModel.
            activeModel.CalculateInfluenceChange(playerClan, false);

            long invocationCountAfter = CapturedLordsGrantInfluenceClanPoliticsModel.InvocationCount;
            compatibilityCheckCompleted = true;

            if (invocationCountAfter != invocationCountBefore)
            {
                return;
            }

            string activeModelName = activeModel.GetType().FullName ?? activeModel.GetType().Name;
            string message =
                "YL Prisoners: Captured Lords Grant Influence compatibility warning: the active ClanPoliticsModel (" +
                activeModelName +
                ") did not call the existing Bannerlord model chain. Captured-lord influence bonuses will not " +
                "work while that model is active. Check other mods that replace clan or influence calculations.";

            InformationManager.DisplayMessage(new InformationMessage(message));
        }
    }
}
