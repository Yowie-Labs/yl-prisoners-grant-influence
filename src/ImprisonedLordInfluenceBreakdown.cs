namespace YL.Prisoners.CapturedLordsGrantInfluence
{
    /// <summary>
    /// Describes one complete daily prisoner-influence calculation for one evaluated clan.
    /// </summary>
    /// <remarks>
    /// Bannerlord's influence model ultimately needs a single numeric result, but the user interface is much
    /// more useful when it can explain where that number came from. This value object keeps the three mutually
    /// exclusive prisoner tiers separate so the gameplay calculation and the influence tooltip can consume the
    /// exact same data. A hero is counted in only one tier: kingdom ruler first, then clan leader, then ordinary
    /// lord. That preserves the module's "highest tier only" rule and prevents a ruler from also being counted as
    /// a clan leader and an ordinary lord.
    /// </remarks>
    public sealed class ImprisonedLordInfluenceBreakdown
    {
        /// <summary>
        /// Initializes an immutable breakdown of the influence earned from imprisoned lords.
        /// </summary>
        /// <param name="lordCount">Number of unique ordinary lords who are neither clan leaders nor kingdom rulers.</param>
        /// <param name="lordInfluence">Total daily influence contributed by <paramref name="lordCount"/>.</param>
        /// <param name="clanLeaderCount">Number of unique imprisoned clan leaders who are not kingdom rulers.</param>
        /// <param name="clanLeaderInfluence">Total daily influence contributed by <paramref name="clanLeaderCount"/>.</param>
        /// <param name="kingdomRulerCount">Number of unique imprisoned kingdom rulers.</param>
        /// <param name="kingdomRulerInfluence">Total daily influence contributed by <paramref name="kingdomRulerCount"/>.</param>
        public ImprisonedLordInfluenceBreakdown(
            int lordCount,
            float lordInfluence,
            int clanLeaderCount,
            float clanLeaderInfluence,
            int kingdomRulerCount,
            float kingdomRulerInfluence)
        {
            LordCount = lordCount;
            LordInfluence = lordInfluence;
            ClanLeaderCount = clanLeaderCount;
            ClanLeaderInfluence = clanLeaderInfluence;
            KingdomRulerCount = kingdomRulerCount;
            KingdomRulerInfluence = kingdomRulerInfluence;
        }

        /// <summary>Gets the number of unique ordinary imprisoned lords.</summary>
        public int LordCount { get; }

        /// <summary>Gets the total daily influence produced by ordinary imprisoned lords.</summary>
        public float LordInfluence { get; }

        /// <summary>Gets the number of unique imprisoned clan leaders who are not kingdom rulers.</summary>
        public int ClanLeaderCount { get; }

        /// <summary>Gets the total daily influence produced by imprisoned clan leaders.</summary>
        public float ClanLeaderInfluence { get; }

        /// <summary>Gets the number of unique imprisoned kingdom rulers.</summary>
        public int KingdomRulerCount { get; }

        /// <summary>Gets the total daily influence produced by imprisoned kingdom rulers.</summary>
        public float KingdomRulerInfluence { get; }

        /// <summary>
        /// Gets the complete daily influence bonus represented by this breakdown.
        /// </summary>
        /// <remarks>
        /// This is the value Bannerlord will ultimately add to the player's normal daily influence change. The
        /// individual category totals above are retained only so Bannerlord's normal influence tooltip can explain
        /// the total without running a second, potentially divergent calculation.
        /// </remarks>
        public float TotalInfluence => LordInfluence + ClanLeaderInfluence + KingdomRulerInfluence;
    }
}
