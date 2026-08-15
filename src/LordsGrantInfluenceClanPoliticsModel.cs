using System;
using System.Threading;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.ComponentInterfaces;
using TaleWorlds.CampaignSystem.Election;
using TaleWorlds.Localization;

namespace YL.Prisoners.LordsGrantInfluence
{
    /// <summary>
    /// Adds captured-lord influence to Bannerlord's normal <see cref="ClanPoliticsModel"/> calculation.
    /// </summary>
    /// <remarks>
    /// Bannerlord composes game-model replacements as a chain. When this model is registered with
    /// <c>CampaignGameStarter.AddModel</c>, its protected <c>BaseModel</c> points at the previously active
    /// <see cref="ClanPoliticsModel"/>. Calling <c>BaseModel</c> first therefore preserves vanilla calculations,
    /// War Sails calculations, and well-behaved calculations from other mods before this module adds its own
    /// contribution.
    ///
    /// This integration is preferable to awarding influence from a separate daily event because Bannerlord uses
    /// <see cref="ClanPoliticsModel.CalculateInfluenceChange(Clan, bool)"/> for both the native daily influence tick and native influence tooltip.
    /// One model calculation therefore drives the gameplay result and the UI explanation, eliminating the possibility
    /// that the tooltip and the awarded amount disagree.
    /// </remarks>
    public sealed class LordsGrantInfluenceClanPoliticsModel : ClanPoliticsModel
    {
        private readonly IImprisonedLordInfluenceCalculator calculator;
        private readonly PlayerClanImprisonedLordProvider prisonerProvider;
        private static long invocationCount;

        /// <summary>
        /// Initializes the model with the prisoner-policy calculator and custody provider it will use.
        /// </summary>
        /// <param name="calculator">Policy component that applies the configured highest-tier-only influence rule.</param>
        /// <param name="prisonerProvider">Component that finds unique lords held anywhere by the player clan.</param>
        public LordsGrantInfluenceClanPoliticsModel(
            IImprisonedLordInfluenceCalculator calculator,
            PlayerClanImprisonedLordProvider prisonerProvider)
        {
            this.calculator = calculator ?? throw new ArgumentNullException(nameof(calculator));
            this.prisonerProvider = prisonerProvider ?? throw new ArgumentNullException(nameof(prisonerProvider));
        }

        /// <summary>
        /// Gets the number of times Bannerlord's active model chain has reached this model during this process.
        /// </summary>
        /// <remarks>
        /// The compatibility behavior samples this counter before and after invoking the currently active
        /// <see cref="ClanPoliticsModel"/>. If the counter does not advance during that synchronous call, another
        /// model above this one replaced the calculation without delegating to its <c>BaseModel</c>. A counter is
        /// used instead of checking class names because it detects the actual broken behavior regardless of which
        /// mod introduced it. <see cref="Interlocked"/> keeps the diagnostic safe even if a UI query and campaign
        /// query ever occur on different threads.
        /// </remarks>
        internal static long InvocationCount => Interlocked.Read(ref invocationCount);

        /// <summary>
        /// Calculates the normal clan influence change and then adds the player's captured-lord contribution.
        /// </summary>
        /// <param name="clan">Clan whose influence change Bannerlord is evaluating.</param>
        /// <param name="includeDescriptions">
        /// True when Bannerlord wants explanation text, such as for the influence tooltip; false when only the
        /// numeric result is required for simulation.
        /// </param>
        /// <returns>
        /// The chained base calculation plus this module's prisoner influence for the player clan. Other clans are
        /// returned unchanged.
        /// </returns>
        public override ExplainedNumber CalculateInfluenceChange(Clan clan, bool includeDescriptions)
        {
            Interlocked.Increment(ref invocationCount);

            // Always call the previous model first. This is the compatibility contract used by Bannerlord's model
            // chain; constructing a fresh ExplainedNumber here would erase every contribution below this model.
            ExplainedNumber result = BaseModel.CalculateInfluenceChange(clan, includeDescriptions);

            Clan playerClan = Clan.PlayerClan;
            if (playerClan == null || clan != playerClan)
            {
                return result;
            }

            ImprisonedLordInfluenceBreakdown breakdown =
                calculator.CalculateBreakdown(prisonerProvider.GetImprisonedLords(playerClan));

            AddInfluenceLine(
                ref result,
                breakdown.LordInfluence,
                breakdown.LordCount,
                "{=YL_LGI_CapturedLords}Captured lords ({COUNT})",
                includeDescriptions);

            AddInfluenceLine(
                ref result,
                breakdown.ClanLeaderInfluence,
                breakdown.ClanLeaderCount,
                "{=YL_LGI_CapturedClanLeaders}Captured clan leaders ({COUNT})",
                includeDescriptions);

            AddInfluenceLine(
                ref result,
                breakdown.KingdomRulerInfluence,
                breakdown.KingdomRulerCount,
                "{=YL_LGI_CapturedKingdomRulers}Captured kingdom rulers ({COUNT})",
                includeDescriptions);

            return result;
        }

        /// <summary>
        /// Delegates policy-support calculation to the previously active politics model unchanged.
        /// </summary>
        /// <param name="clan">Clan evaluating the policy.</param>
        /// <param name="policy">Policy being evaluated.</param>
        /// <returns>The base model's policy-support score.</returns>
        public override float CalculateSupportForPolicyInClan(Clan clan, PolicyObject policy)
        {
            return BaseModel.CalculateSupportForPolicyInClan(clan, policy);
        }

        /// <summary>
        /// Delegates sponsor relationship calculation to the previously active politics model unchanged.
        /// </summary>
        /// <param name="clan">Clan whose relationship change is being calculated.</param>
        /// <param name="sponsorClan">Clan sponsoring the relevant political action.</param>
        /// <returns>The base model's relationship change.</returns>
        public override float CalculateRelationshipChangeWithSponsor(Clan clan, Clan sponsorClan)
        {
            return BaseModel.CalculateRelationshipChangeWithSponsor(clan, sponsorClan);
        }

        /// <summary>
        /// Delegates kingdom-decision override cost calculation to the previously active politics model unchanged.
        /// </summary>
        /// <param name="popularOutcome">Outcome favored by the decision process.</param>
        /// <param name="overriddenOutcome">Outcome the ruler wants to choose instead.</param>
        /// <param name="kingdomDecision">Kingdom decision being overridden.</param>
        /// <returns>The base model's required influence cost.</returns>
        public override int GetInfluenceRequiredToOverrideKingdomDecision(
            DecisionOutcome popularOutcome,
            DecisionOutcome overriddenOutcome,
            KingdomDecision kingdomDecision)
        {
            return BaseModel.GetInfluenceRequiredToOverrideKingdomDecision(
                popularOutcome,
                overriddenOutcome,
                kingdomDecision);
        }

        /// <summary>
        /// Delegates governor eligibility to the previously active politics model unchanged.
        /// </summary>
        /// <param name="hero">Hero whose governor eligibility is being checked.</param>
        /// <returns>The base model's governor-eligibility result.</returns>
        public override bool CanHeroBeGovernor(Hero hero)
        {
            return BaseModel.CanHeroBeGovernor(hero);
        }

        /// <summary>
        /// Adds one non-zero prisoner category to Bannerlord's explained influence result.
        /// </summary>
        /// <param name="result">The chained influence result being augmented in place.</param>
        /// <param name="influence">Influence subtotal for the category.</param>
        /// <param name="count">Number of unique imprisoned lords in the category.</param>
        /// <param name="descriptionTemplate">Localized tooltip label containing a <c>{COUNT}</c> variable.</param>
        /// <param name="includeDescriptions">Whether Bannerlord requested explanation text.</param>
        /// <remarks>
        /// Categories with a zero count or zero subtotal are intentionally omitted. This keeps the native tooltip
        /// concise: a player with two ordinary captured lords sees only one prisoner row rather than two additional
        /// zero-value rows for clan leaders and kingdom rulers.
        ///
        /// <see cref="ExplainedNumber"/> is a value type. The <paramref name="result"/> parameter must therefore be
        /// passed by <c>ref</c>. Passing it by value mutates only a copy of the numeric total. Because the copied value
        /// can still share explanation backing data, that bug can produce a deceptive tooltip that shows prisoner
        /// rows while Bannerlord's actual Expected Change omits their influence. Keeping the mutation by-reference is
        /// required for the UI explanation and the gameplay number to remain identical.
        /// </remarks>
        private static void AddInfluenceLine(
            ref ExplainedNumber result,
            float influence,
            int count,
            string descriptionTemplate,
            bool includeDescriptions)
        {
            if (count <= 0 || influence == 0f)
            {
                return;
            }

            TextObject? description = null;
            if (includeDescriptions)
            {
                description = new TextObject(descriptionTemplate);
                description.SetTextVariable("COUNT", count);
            }

            result.Add(influence, description, null);
        }
    }
}
