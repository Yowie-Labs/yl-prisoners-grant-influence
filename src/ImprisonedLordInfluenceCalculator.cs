using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Xml;
using TaleWorlds.CampaignSystem;
using TaleWorlds.Library;

namespace YL.Prisoners.LordsGrantInfluence
{
    /// <summary>
    /// Applies the module's configurable prisoner-influence policy.
    /// </summary>
    /// <remarks>
    /// The shipped defaults grant 0.5 influence per day for an ordinary lord, 1.0 for a clan leader, and 1.5 for
    /// a kingdom ruler. Players can change those values in <c>module/config/LordsGrantInfluence.xml</c>. Only the
    /// highest matching tier applies. The calculator does not care about war state, faction hostility, whether the
    /// hero is alive, or how the prisoner was acquired; those exclusions are deliberate product rules rather than
    /// missing checks.
    ///
    /// Configuration is loaded once when Bannerlord creates this calculator for a campaign session. Nothing from
    /// the XML is written into the save. A missing or invalid file therefore cannot make the save dependent on the
    /// module; the calculator falls back to the documented defaults and displays one startup warning instead.
    /// </remarks>
    public sealed class ImprisonedLordInfluenceCalculator : IImprisonedLordInfluenceCalculator
    {
        /// <summary>Default daily influence granted by an ordinary imprisoned lord.</summary>
        public const float DefaultLordInfluencePerDay = 0.5f;

        /// <summary>Default daily influence granted by an imprisoned clan leader who is not a kingdom ruler.</summary>
        public const float DefaultClanLeaderInfluencePerDay = 1f;

        /// <summary>Default daily influence granted by an imprisoned kingdom ruler.</summary>
        public const float DefaultKingdomRulerInfluencePerDay = 1.5f;

        private const string SettingsFileName = "LordsGrantInfluence.xml";

        /// <summary>
        /// Initializes the calculator from the player-editable module XML, falling back to shipped defaults if the
        /// file cannot be read or contains an invalid value.
        /// </summary>
        public ImprisonedLordInfluenceCalculator()
        {
            LordInfluencePerDay = DefaultLordInfluencePerDay;
            ClanLeaderInfluencePerDay = DefaultClanLeaderInfluencePerDay;
            KingdomRulerInfluencePerDay = DefaultKingdomRulerInfluencePerDay;

            TryLoadConfiguredValues();
        }

        /// <summary>Gets the configured daily influence granted by an ordinary imprisoned lord.</summary>
        public float LordInfluencePerDay { get; private set; }

        /// <summary>Gets the configured daily influence granted by an imprisoned clan leader.</summary>
        public float ClanLeaderInfluencePerDay { get; private set; }

        /// <summary>Gets the configured daily influence granted by an imprisoned kingdom ruler.</summary>
        public float KingdomRulerInfluencePerDay { get; private set; }

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
                // this order would incorrectly reduce a ruler to the clan-leader value.
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

        /// <summary>
        /// Attempts to replace the shipped defaults with values from the module's XML configuration file.
        /// </summary>
        /// <remarks>
        /// The assembly is installed at <c>module/bin/Win64_Shipping_Client</c>, so walking up two directories from
        /// the DLL directory reaches the module root. This avoids hard-coding a Steam path and also works when the
        /// module is copied to another Bannerlord installation. Parsing uses invariant culture because the XML is a
        /// portable data file: decimal values always use a dot regardless of the player's Windows locale.
        /// </remarks>
        private void TryLoadConfiguredValues()
        {
            string settingsPath = "<unresolved>";

            try
            {
                settingsPath = GetSettingsPath();

                if (!File.Exists(settingsPath))
                {
                    throw new FileNotFoundException("The settings file is missing.", settingsPath);
                }

                XmlDocument document = new XmlDocument();
                document.Load(settingsPath);

                XmlElement? root = document.DocumentElement;
                if (root == null || root.Name != "LordsGrantInfluenceSettings")
                {
                    throw new InvalidDataException(
                        "Expected root element <LordsGrantInfluenceSettings>.");
                }

                LordInfluencePerDay = ReadInfluenceValue(root, "OrdinaryLord");
                ClanLeaderInfluencePerDay = ReadInfluenceValue(root, "ClanLeader");
                KingdomRulerInfluencePerDay = ReadInfluenceValue(root, "KingdomRuler");
            }
            catch (Exception exception) when (
                exception is IOException ||
                exception is UnauthorizedAccessException ||
                exception is XmlException ||
                exception is InvalidDataException)
            {
                LordInfluencePerDay = DefaultLordInfluencePerDay;
                ClanLeaderInfluencePerDay = DefaultClanLeaderInfluencePerDay;
                KingdomRulerInfluencePerDay = DefaultKingdomRulerInfluencePerDay;

                string message =
                    "YL Prisoners: Lords Grant Influence could not load its XML settings and is using defaults " +
                    $"({DefaultLordInfluencePerDay.ToString(CultureInfo.InvariantCulture)}/" +
                    $"{DefaultClanLeaderInfluencePerDay.ToString(CultureInfo.InvariantCulture)}/" +
                    $"{DefaultKingdomRulerInfluencePerDay.ToString(CultureInfo.InvariantCulture)}). " +
                    $"File: {settingsPath}. {exception.Message}";

                InformationManager.DisplayMessage(new InformationMessage(message));
            }
        }

        /// <summary>
        /// Reads one non-negative influence value from the <c>&lt;InfluencePerDay&gt;</c> section.
        /// </summary>
        /// <param name="root">Validated configuration root element.</param>
        /// <param name="elementName">Tier element to read, such as <c>OrdinaryLord</c>.</param>
        /// <returns>The configured influence value.</returns>
        private static float ReadInfluenceValue(XmlElement root, string elementName)
        {
            XmlElement? element = root.SelectSingleNode($"InfluencePerDay/{elementName}") as XmlElement;
            if (element == null)
            {
                throw new InvalidDataException(
                    $"Missing <{elementName}> inside <InfluencePerDay>.");
            }

            string rawValue = element.GetAttribute("value");
            if (!float.TryParse(
                    rawValue,
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out float parsedValue) ||
                parsedValue < 0f ||
                float.IsNaN(parsedValue) ||
                float.IsInfinity(parsedValue))
            {
                throw new InvalidDataException(
                    $"<{elementName} value=\"{rawValue}\"> must contain a finite number greater than or equal to zero.");
            }

            return parsedValue;
        }

        /// <summary>
        /// Resolves the player-editable settings file relative to this module's installed DLL.
        /// </summary>
        private static string GetSettingsPath()
        {
            string assemblyPath = typeof(ImprisonedLordInfluenceCalculator).Assembly.Location;
            string? binDirectory = Path.GetDirectoryName(assemblyPath);
            if (string.IsNullOrWhiteSpace(binDirectory))
            {
                throw new InvalidDataException("Could not determine the module DLL directory.");
            }

            string moduleRoot = Path.GetFullPath(Path.Combine(binDirectory, "..", ".."));
            return Path.Combine(moduleRoot, "config", SettingsFileName);
        }
    }
}
