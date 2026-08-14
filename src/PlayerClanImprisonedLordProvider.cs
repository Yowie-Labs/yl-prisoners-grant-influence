using System;
using System.Collections.Generic;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Roster;

namespace YL.Prisoners.LordsGrantInfluence
{
    /// <summary>
    /// Finds every unique lord currently imprisoned anywhere under the player clan's control.
    /// </summary>
    /// <remarks>
    /// Bannerlord stores prisoners in more than one place. A lord may be in the main party, another mobile party
    /// belonging to the player clan, or a dungeon in a settlement owned by the player clan. Keeping this traversal
    /// in one class makes it difficult for the influence model and the tooltip to accidentally use different
    /// definitions of "captured by the player clan".
    /// </remarks>
    public sealed class PlayerClanImprisonedLordProvider
    {
        /// <summary>
        /// Collects the unique imprisoned lords held by <paramref name="playerClan"/>.
        /// </summary>
        /// <param name="playerClan">The player's current clan.</param>
        /// <returns>
        /// A deduplicated set of hero objects. Only heroes whose <see cref="Hero.IsLord"/> flag is true are returned.
        /// </returns>
        public IReadOnlyCollection<Hero> GetImprisonedLords(Clan playerClan)
        {
            if (playerClan == null)
            {
                throw new ArgumentNullException(nameof(playerClan));
            }

            HashSet<Hero> imprisonedLords = new HashSet<Hero>();
            AddPartyPrisoners(playerClan, imprisonedLords);
            AddDungeonPrisoners(playerClan, imprisonedLords);
            return imprisonedLords;
        }

        /// <summary>
        /// Adds lord prisoners from the main party and every other mobile party belonging to the player clan.
        /// </summary>
        /// <param name="playerClan">Clan whose mobile-party custody should count.</param>
        /// <param name="imprisonedLords">Destination set used to deduplicate hero references.</param>
        private static void AddPartyPrisoners(Clan playerClan, ISet<Hero> imprisonedLords)
        {
            // MobileParty.All is used intentionally instead of only war parties. The product rule is every
            // player-clan mobile party, so caravans or other clan-owned party types must not be silently omitted.
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

        /// <summary>
        /// Adds lord prisoners from every dungeon owned by the player clan.
        /// </summary>
        /// <param name="playerClan">Clan whose settlement dungeons should count.</param>
        /// <param name="imprisonedLords">Destination set used to deduplicate hero references.</param>
        private static void AddDungeonPrisoners(Clan playerClan, ISet<Hero> imprisonedLords)
        {
            foreach (CharacterObject prisoner in playerClan.DungeonPrisonersOfClan)
            {
                AddLord(prisoner, imprisonedLords);
            }
        }

        /// <summary>
        /// Converts one prisoner character into a lord hero and adds it when eligible.
        /// </summary>
        /// <param name="prisoner">Bannerlord character record stored in a prisoner roster.</param>
        /// <param name="imprisonedLords">Destination set used to deduplicate hero references.</param>
        private static void AddLord(CharacterObject prisoner, ISet<Hero> imprisonedLords)
        {
            // Ordinary troops do not have Hero objects. Checking IsHero before HeroObject avoids treating troop
            // prisoners as candidates and makes the subsequent IsLord test explicit.
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
