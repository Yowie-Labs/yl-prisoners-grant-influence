<#
.SYNOPSIS
Creates a disposable Bannerlord module for Strategic Navies officer-lifecycle research.

.DESCRIPTION
This script is research/proof tooling for STRATEGIC-NAVIES-1. It generates a
small temporary Bannerlord/War Sails module under the shared ai-repo runtime
folder. The generated module mutates only native Bannerlord objects and writes
no custom campaign SyncData.

The spike is intentionally command-driven. Nothing creates, retires, disables,
or reactivates a hero merely because the module was loaded. Use only disposable
test campaigns/saves.

The first research questions are:

  * Can a native hero generated from an existing culture lord template survive
    save/reload and loading with this spike module removed?
  * Can DisableHeroAction safely put an idle generated officer into Bannerlord's
    native Disabled state, and can Hero.ChangeState(Active) bring that officer
    back before a normal lord party is spawned again?
  * Does the generated officer's lord party consume the host clan's ordinary
    WarPartyComponents / WarPartyLimit capacity?
  * Can a surplus officer be retired by native disband/disable operations rather
    than by killing the hero?

Usage examples:

  pwsh -NoProfile -File .\scripts\Invoke-StrategicNaviesOfficerSafetySpike.ps1 -Command Plan

  pwsh -NoProfile -File .\scripts\Invoke-StrategicNaviesOfficerSafetySpike.ps1 -Command Prepare

  pwsh -NoProfile -File .\scripts\Invoke-StrategicNaviesOfficerSafetySpike.ps1 -Command Build `
    -BannerlordGameRoot "<BannerlordGameRoot>" `
    -TaleWorldsAssemblyDir "<directory containing TaleWorlds.CampaignSystem.dll>"

  pwsh -NoProfile -File .\scripts\Invoke-StrategicNaviesOfficerSafetySpike.ps1 -Command Publish `
    -BannerlordGameRoot "<BannerlordGameRoot>" `
    -TaleWorldsAssemblyDir "<directory containing TaleWorlds.CampaignSystem.dll>"

  pwsh -NoProfile -File .\scripts\Invoke-StrategicNaviesOfficerSafetySpike.ps1 -Command EvidenceTemplate
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Plan', 'Prepare', 'Build', 'Publish', 'EvidenceTemplate', 'Clean')]
    [string] $Command = 'Plan',

    [Parameter()]
    [string] $RepoRoot,

    [Parameter()]
    [string] $RuntimeRoot,

    [Parameter()]
    [string] $BannerlordGameRoot,

    [Parameter()]
    [string] $TaleWorldsAssemblyDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)

function Get-DefaultAiRepoRuntimeRoot {
    param([Parameter(Mandatory)] [string] $WorkspaceRoot)

    $workspaceRootFull = [System.IO.Path]::GetFullPath($WorkspaceRoot)
    $workspaceParent = Split-Path -Path $workspaceRootFull -Parent
    $reposRoot = Split-Path -Path $workspaceParent -Parent

    if ([string]::IsNullOrWhiteSpace($reposRoot)) {
        return Join-Path -Path $workspaceRootFull -ChildPath 'artifacts/runtime'
    }

    return Join-Path -Path $reposRoot -ChildPath '_ai-repo-runtime'
}

if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
    $RuntimeRoot = Get-DefaultAiRepoRuntimeRoot -WorkspaceRoot $repoRootFull
}

$runtimeRootFull = [System.IO.Path]::GetFullPath($RuntimeRoot)
$spikeRoot = Join-Path -Path $runtimeRootFull -ChildPath 'spikes/strategic-navies-officer-safety'
$projectRoot = Join-Path -Path $spikeRoot -ChildPath 'source'
$moduleRoot = Join-Path -Path $spikeRoot -ChildPath 'module/StrategicNaviesOfficerSafetySpike'
$moduleBinRoot = Join-Path -Path $moduleRoot -ChildPath 'bin/Win64_Shipping_Client'
$artifactRoot = Join-Path -Path $repoRootFull -ChildPath 'artifacts/strategic-navies-officer-safety'
$evidenceRoot = Join-Path -Path $artifactRoot -ChildPath 'evidence'
$projectPath = Join-Path -Path $projectRoot -ChildPath 'StrategicNavies.OfficerSafetySpike.csproj'
$subModulePath = Join-Path -Path $moduleRoot -ChildPath 'SubModule.xml'
$moduleId = 'StrategicNaviesOfficerSafetySpike'

function New-SpikeDirectory {
    param([Parameter(Mandatory)] [string] $Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-Step {
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "[Strategic Navies officer spike] $Message" -ForegroundColor Cyan
}

function Resolve-BannerlordGameRoot {
    if (-not [string]::IsNullOrWhiteSpace($BannerlordGameRoot)) {
        return [System.IO.Path]::GetFullPath($BannerlordGameRoot)
    }

    $localPropsPath = Join-Path -Path $repoRootFull -ChildPath 'Skaldflow.Workspace.local.props'
    if (Test-Path -LiteralPath $localPropsPath) {
        $text = Get-Content -LiteralPath $localPropsPath -Raw
        $properties = @{}
        foreach ($match in [regex]::Matches($text, '<(?<name>[A-Za-z0-9_]+)>(?<value>[^<]+)</\k<name>>')) {
            $properties[$match.Groups['name'].Value] = $match.Groups['value'].Value
        }

        if ($properties.ContainsKey('BannerlordGameRoot')) {
            $value = [string] $properties['BannerlordGameRoot']
            foreach ($key in @($properties.Keys)) {
                $value = $value.Replace("`$($key)", [string] $properties[$key])
            }

            # The local props file is XML, so paths containing '&' are stored as
            # '&amp;'. The lightweight regex reader above returns the encoded text;
            # decode it before treating the value as a filesystem path.
            $value = [System.Net.WebUtility]::HtmlDecode($value)

            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return [System.IO.Path]::GetFullPath($value)
            }
        }
    }

    throw 'BannerlordGameRoot was not provided and could not be resolved from Skaldflow.Workspace.local.props. Pass -BannerlordGameRoot explicitly for Build/Publish.'
}

function Test-TaleWorldsAssemblyDirectory {
    param([Parameter(Mandatory)] [string] $Path)

    foreach ($name in @(
        'TaleWorlds.CampaignSystem.dll',
        'TaleWorlds.Core.dll',
        'TaleWorlds.Library.dll',
        'TaleWorlds.Localization.dll',
        'TaleWorlds.MountAndBlade.dll',
        'TaleWorlds.ObjectSystem.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath $name))) {
            return $false
        }
    }

    return $true
}

function Get-BannerlordBinDir {
    $root = Resolve-BannerlordGameRoot

    if (-not [string]::IsNullOrWhiteSpace($TaleWorldsAssemblyDir)) {
        $explicit = [System.IO.Path]::GetFullPath($TaleWorldsAssemblyDir)
        if (-not (Test-TaleWorldsAssemblyDirectory -Path $explicit)) {
            throw "TaleWorldsAssemblyDir does not contain the required TaleWorlds assemblies: $explicit"
        }

        Write-Step "Using explicit TaleWorlds assembly directory: $explicit"
        return $explicit
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Join-Path -Path $root -ChildPath 'bin/Win64_Shipping_Client'))
    $candidates.Add((Join-Path -Path $root -ChildPath 'Modules/DismembermentPlus/bin/Win64_Shipping_Client'))

    $modulesRoot = Join-Path -Path $root -ChildPath 'Modules'
    if (Test-Path -LiteralPath $modulesRoot) {
        foreach ($module in Get-ChildItem -LiteralPath $modulesRoot -Directory -ErrorAction SilentlyContinue) {
            $candidate = Join-Path -Path $module.FullName -ChildPath 'bin/Win64_Shipping_Client'
            if (-not $candidates.Contains($candidate)) {
                $candidates.Add($candidate)
            }
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-TaleWorldsAssemblyDirectory -Path $candidate) {
            Write-Step "Using TaleWorlds assembly directory: $candidate"
            return $candidate
        }
    }

    throw "Could not find a directory containing the required TaleWorlds assemblies. Pass -TaleWorldsAssemblyDir explicitly."
}

function Write-Plan {
    Write-Host 'Strategic Navies generated-officer safety spike'
    Write-Host ''
    Write-Host "Repo root    : $repoRootFull"
    Write-Host "Runtime root : $runtimeRootFull"
    Write-Host "Spike root   : $spikeRoot"
    Write-Host "Module root  : $moduleRoot"
    Write-Host "Artifacts    : $artifactRoot"
    Write-Host ''
    Write-Host 'The generated module deliberately uses only native Bannerlord state:'
    Write-Host '  - HeroCreator.CreateSpecialHero with an existing culture LordTemplates entry'
    Write-Host '  - Hero.ChangeState(Hero.CharacterStates.Active)'
    Write-Host '  - Helpers.MobilePartyHelper.SpawnLordParty'
    Write-Host '  - DestroyPartyAction.ApplyForDisbanding for graceful command retirement and War Sails ship distribution'
    Write-Host '  - DisableHeroAction.Apply for the native Disabled reserve state'
    Write-Host '  - Clan.WarPartyComponents / WarPartyLimit and the active ClanTierModel for diagnostics'
    Write-Host ''
    Write-Host 'The generated module contains no CampaignBehavior SyncData and no SaveableTypeDefiner.'
    Write-Host 'All state under test therefore belongs to native Bannerlord objects.'
    Write-Host ''
    Write-Host 'Evidence workflow:'
    Write-Host '  1. Publish the spike and enable it only on a disposable campaign.'
    Write-Host '  2. Use snspike.officer clans, then create one officer in a selected AI clan.'
    Write-Host '  3. Save, disable/remove the spike module, load and re-save.'
    Write-Host '  4. Re-enable and inspect whether the same native hero/party survived.'
    Write-Host '  5. Test graceful reserve -> Disabled -> Active lifecycle.'
    Write-Host '  6. Compare clan party counts/limits before and after officer creation.'
    Write-Host ''
    Write-Host 'Do not run this spike on a campaign you care about.' -ForegroundColor Yellow
}

function Write-SpikeFiles {
    New-SpikeDirectory -Path $projectRoot
    New-SpikeDirectory -Path $moduleBinRoot
    New-SpikeDirectory -Path $evidenceRoot

    @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <OutputType>Library</OutputType>
    <AssemblyName>StrategicNavies.OfficerSafetySpike</AssemblyName>
    <RootNamespace>StrategicNavies.OfficerSafetySpike</RootNamespace>
    <Platforms>x64</Platforms>
    <PlatformTarget>x64</PlatformTarget>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <OutputPath>..\module\StrategicNaviesOfficerSafetySpike\bin\Win64_Shipping_Client\</OutputPath>
  </PropertyGroup>

  <PropertyGroup Condition="'$(BannerlordGameRoot)' != '' and '$(TaleWorldsAssemblyDir)' == ''">
    <TaleWorldsAssemblyDir>$(BannerlordGameRoot)\bin\Win64_Shipping_Client</TaleWorldsAssemblyDir>
  </PropertyGroup>

  <ItemGroup>
    <Reference Include="System" />
    <Reference Include="System.Core" />
    <Reference Include="TaleWorlds.CampaignSystem">
      <HintPath>$(TaleWorldsAssemblyDir)\TaleWorlds.CampaignSystem.dll</HintPath>
      <Private>False</Private>
    </Reference>
    <Reference Include="TaleWorlds.Core">
      <HintPath>$(TaleWorldsAssemblyDir)\TaleWorlds.Core.dll</HintPath>
      <Private>False</Private>
    </Reference>
    <Reference Include="TaleWorlds.Library">
      <HintPath>$(TaleWorldsAssemblyDir)\TaleWorlds.Library.dll</HintPath>
      <Private>False</Private>
    </Reference>
    <Reference Include="TaleWorlds.Localization">
      <HintPath>$(TaleWorldsAssemblyDir)\TaleWorlds.Localization.dll</HintPath>
      <Private>False</Private>
    </Reference>
    <Reference Include="TaleWorlds.MountAndBlade">
      <HintPath>$(TaleWorldsAssemblyDir)\TaleWorlds.MountAndBlade.dll</HintPath>
      <Private>False</Private>
    </Reference>
    <Reference Include="TaleWorlds.ObjectSystem">
      <HintPath>$(TaleWorldsAssemblyDir)\TaleWorlds.ObjectSystem.dll</HintPath>
      <Private>False</Private>
    </Reference>
  </ItemGroup>
</Project>
'@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

    @'
<?xml version="1.0" encoding="utf-8"?>
<Module>
  <Name value="Strategic Navies Officer Safety Spike" />
  <Id value="StrategicNaviesOfficerSafetySpike" />
  <Version value="v0.0.1" />
  <DefaultModule value="false" />
  <ModuleCategory value="Singleplayer" />
  <ModuleType value="Community" />
  <DependedModules>
    <DependedModule Id="Native" />
    <DependedModule Id="SandBoxCore" />
    <DependedModule Id="Sandbox" />
    <DependedModule Id="NavalDLC" />
  </DependedModules>
  <SubModules>
    <SubModule>
      <Name value="Strategic Navies Officer Safety Spike" />
      <DLLName value="StrategicNavies.OfficerSafetySpike.dll" />
      <SubModuleClassType value="StrategicNavies.OfficerSafetySpike.OfficerSafetySubModule" />
      <Tags>
        <Tag key="DedicatedServerType" value="none" />
        <Tag key="IsNoRenderModeElement" value="false" />
      </Tags>
    </SubModule>
  </SubModules>
</Module>
'@ | Set-Content -LiteralPath $subModulePath -Encoding UTF8

    @'
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;

namespace StrategicNavies.OfficerSafetySpike
{
    /// <summary>
    /// Loads the disposable Strategic Navies officer-lifecycle research module.
    /// </summary>
    /// <remarks>
    /// The submodule intentionally registers no campaign behavior and therefore
    /// writes no custom campaign save data. Every mutation is initiated explicitly
    /// through the console commands in <see cref="OfficerSafetyCommands"/>.
    /// </remarks>
    public sealed class OfficerSafetySubModule : MBSubModuleBase
    {
        /// <inheritdoc />
        protected override void OnSubModuleLoad()
        {
            base.OnSubModuleLoad();
            OfficerSafetyLog.Write("module loaded; no officer mutation occurs until a snspike.officer command is run");
        }

        /// <inheritdoc />
        public override void OnGameEnd(Game game)
        {
            OfficerSafetyLog.Write("game ended");
            base.OnGameEnd(game);
        }
    }
}
'@ | Set-Content -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'OfficerSafetySubModule.cs') -Encoding UTF8

    @'
using System;
using System.IO;
using TaleWorlds.Library;

namespace StrategicNavies.OfficerSafetySpike
{
    /// <summary>
    /// Provides best-effort diagnostics for the disposable officer safety spike.
    /// </summary>
    /// <remarks>
    /// Logging must never be able to break the campaign. The log is deliberately
    /// external to the Bannerlord save so it does not contaminate persistence evidence.
    /// </remarks>
    internal static class OfficerSafetyLog
    {
        private static readonly string LogRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Skaldflow",
            "StrategicNaviesOfficerSafetySpike");

        /// <summary>
        /// Writes one timestamped diagnostic line to the external spike log and,
        /// when possible, mirrors it to Bannerlord's information feed.
        /// </summary>
        /// <param name="message">Human-readable evidence message.</param>
        public static void Write(string message)
        {
            string line = DateTimeOffset.Now.ToString("O") + " " + message;

            try
            {
                Directory.CreateDirectory(LogRoot);
                File.AppendAllText(Path.Combine(LogRoot, "officer-safety-spike.log"), line + Environment.NewLine);
            }
            catch
            {
                // Diagnostic output must never affect the campaign under test.
            }

            try
            {
                InformationManager.DisplayMessage(new InformationMessage("[Strategic Navies officer spike] " + message));
            }
            catch
            {
                // The console/log file remains sufficient if the UI is unavailable.
            }
        }
    }
}
'@ | Set-Content -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'OfficerSafetyLog.cs') -Encoding UTF8

    @'
using System;
using System.Collections.Generic;
using System.Linq;
using Helpers;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.Actions;
using TaleWorlds.CampaignSystem.Party;
using TaleWorlds.CampaignSystem.Settlements;
using TaleWorlds.Library;
using TaleWorlds.Localization;

namespace StrategicNavies.OfficerSafetySpike
{
    /// <summary>
    /// Implements the native-object operations exercised by the officer safety spike.
    /// </summary>
    /// <remarks>
    /// This type deliberately owns no persistent collection of generated officers.
    /// Officers are rediscovered after save/load from ordinary native Hero state by
    /// the visible test-name prefix. That keeps the experiment focused on whether
    /// Bannerlord itself can persist the generated hero and lord party without this
    /// assembly being present.
    /// </remarks>
    internal static class OfficerSafetyOperations
    {
        private const string GeneratedNamePrefix = "SN Test Admiral ";

        /// <summary>
        /// Returns concise identifiers for kingdom clans that are reasonable hosts
        /// for an officer-lifecycle test.
        /// </summary>
        public static string DescribeClans()
        {
            IEnumerable<string> lines = Clan.All
                .Where(clan => clan != null && clan.Kingdom != null && !clan.IsEliminated)
                .OrderBy(clan => clan.Kingdom.Name.ToString())
                .ThenBy(clan => clan.Name.ToString())
                .Take(80)
                .Select(clan => clan.StringId + " | " + clan.Name + " | " + clan.Kingdom.Name
                    + " | warParties=" + clan.WarPartyComponents.Count
                    + "/" + clan.WarPartyLimit);

            return string.Join(Environment.NewLine, lines);
        }

        /// <summary>
        /// Creates one entirely native Bannerlord hero from the selected clan culture's
        /// existing lord templates, activates that hero, gives it a diagnostic name,
        /// and asks Bannerlord's own MobilePartyHelper to spawn a normal lord party.
        /// </summary>
        /// <param name="clanId">Native clan StringId supplied from the clans command.</param>
        public static string Create(string clanId)
        {
            Clan? clan = FindClan(clanId);
            if (clan == null)
            {
                return "Unknown clan '" + clanId + "'. Run snspike.officer clans first.";
            }

            if (clan.Culture == null || clan.Culture.LordTemplates.Count == 0)
            {
                return "Clan '" + clanId + "' has no culture lord template available for native hero creation.";
            }

            Settlement? home = FindHomeSettlement(clan);
            if (home == null)
            {
                return "Clan '" + clanId + "' has no usable home/kingdom settlement for spawning the test party.";
            }

            int beforeCount = clan.WarPartyComponents.Count;
            int beforeLimit = clan.WarPartyLimit;
            int beforeModelLimit = Campaign.Current.Models.ClanTierModel.GetPartyLimitForTier(clan, clan.Tier);
            if (beforeCount >= beforeLimit)
            {
                return "Clan '" + clanId + "' is already at its ordinary war-party limit ("
                    + beforeCount + "/" + beforeLimit + "). Choose a clan with a free slot so the spike does not displace a native land party.";
            }

            CharacterObject template = clan.Culture.LordTemplates[0];
            Hero hero = HeroCreator.CreateSpecialHero(template, home, clan, null, 24);
            hero.ChangeState(Hero.CharacterStates.Active);

            string diagnosticName = GeneratedNamePrefix + hero.StringId;
            hero.SetName(new TextObject(diagnosticName), new TextObject("SN Admiral"));

            MobileParty party;
            try
            {
                party = MobilePartyHelper.SpawnLordParty(hero, home);
            }
            catch (Exception exception)
            {
                DisableHeroAction.Apply(hero);
                string failed = "Native hero creation succeeded for " + hero.StringId
                    + " but native lord-party spawning failed. The test hero was placed in Disabled state. "
                    + exception.GetType().Name + ": " + exception.Message;
                OfficerSafetyLog.Write(failed);
                return failed;
            }

            int afterCount = clan.WarPartyComponents.Count;
            int afterLimit = clan.WarPartyLimit;
            int afterModelLimit = Campaign.Current.Models.ClanTierModel.GetPartyLimitForTier(clan, clan.Tier);

            string result = "Created " + hero.StringId
                + " ('" + hero.Name + "') in clan " + clan.StringId
                + "; party=" + party.StringId
                + "; state=" + hero.HeroState
                + "; warPartyComponents " + beforeCount + " -> " + afterCount
                + "; WarPartyLimit " + beforeLimit + " -> " + afterLimit
                + "; ClanTierModel limit " + beforeModelLimit + " -> " + afterModelLimit + ".";

            OfficerSafetyLog.Write(result);
            return result;
        }

        /// <summary>
        /// Moves a generated officer toward a safe native reserve state without killing it.
        /// </summary>
        /// <remarks>
        /// If the officer still leads a party, the operation uses Bannerlord's ordinary
        /// ApplyForDisbanding path first. In 1.4.8 that path immediately dispatches the
        /// native OnPartyDisbanded event before removing the party; War Sails listens to
        /// that event to distribute remaining clan ships. Only after the party is gone
        /// does the operation call DisableHeroAction.Apply. Officers engaged in
        /// an army, map event, siege, or captivity are intentionally left alone so a player
        /// never sees a commander disappear out from under an active operation.
        /// </remarks>
        /// <param name="heroId">Native generated Hero StringId.</param>
        public static string Reserve(string heroId)
        {
            Hero? hero = FindGeneratedHero(heroId);
            if (hero == null)
            {
                return "Generated test officer '" + heroId + "' was not found.";
            }

            if (hero.HeroState == Hero.CharacterStates.Disabled)
            {
                return hero.StringId + " is already in Bannerlord's native Disabled state.";
            }

            if (!hero.IsAlive)
            {
                return "Refusing to reserve " + hero.StringId + " because the generated hero is not alive.";
            }

            if (hero.IsPrisoner || hero.PartyBelongedToAsPrisoner != null)
            {
                return "Refusing to reserve " + hero.StringId + " while the hero is a prisoner.";
            }

            if (hero.HeroState != Hero.CharacterStates.Active)
            {
                return "Refusing to reserve " + hero.StringId + " while native hero state is " + hero.HeroState + ".";
            }

            MobileParty? party = hero.PartyBelongedTo;
            if (party != null)
            {
                if (party.LeaderHero != hero)
                {
                    return "Refusing to reserve " + hero.StringId + " while the hero belongs to another leader's party.";
                }

                if (party.Army != null)
                {
                    return "Refusing to reserve " + hero.StringId + " while the officer's party belongs to an army.";
                }

                if (party.MapEvent != null)
                {
                    return "Refusing to reserve " + hero.StringId + " while the officer's party is in a map event/battle.";
                }

                if (party.SiegeEvent != null)
                {
                    return "Refusing to reserve " + hero.StringId + " while the officer's party belongs to a siege.";
                }

                Settlement? retirementSettlement = party.CurrentSettlement;
                if (retirementSettlement == null)
                {
                    return "Refusing to reserve " + hero.StringId
                        + " while the officer is still on the campaign map. Production retirement should first route the command into a friendly settlement so a fleet never vanishes at sea or while chasing the player.";
                }

                Clan? ownerClan = retirementSettlement.OwnerClan;
                Kingdom? officerKingdom = hero.Clan?.Kingdom;
                bool friendlySettlement = ownerClan == hero.Clan
                    || (ownerClan?.Kingdom != null && officerKingdom != null && ownerClan.Kingdom == officerKingdom);
                if (!friendlySettlement)
                {
                    return "Refusing to reserve " + hero.StringId
                        + " from settlement " + retirementSettlement.StringId
                        + " because it is not owned by the officer's clan/kingdom.";
                }

                if (MobileParty.MainParty?.CurrentSettlement == retirementSettlement)
                {
                    return "Refusing to reserve " + hero.StringId
                        + " while the player is in the same settlement. Wait until the command can demobilize off-screen.";
                }

                DestroyPartyAction.ApplyForDisbanding(party, retirementSettlement);
                if (hero.PartyBelongedTo != null)
                {
                    string incomplete = "Native ApplyForDisbanding returned but " + hero.StringId
                        + " still reports a party. The spike will not disable the hero; inspect the campaign before continuing.";
                    OfficerSafetyLog.Write(incomplete);
                    return incomplete;
                }
            }

            DisableHeroAction.Apply(hero);
            string disabled = "Retired " + hero.StringId
                + " through native party disbanding (when a party existed) and DisableHeroAction; state="
                + hero.HeroState + ".";
            OfficerSafetyLog.Write(disabled);
            return disabled;
        }

        /// <summary>
        /// Reactivates a generated officer that is currently in Bannerlord's Disabled
        /// reserve state and spawns a normal native lord party for that hero again.
        /// </summary>
        /// <param name="heroId">Native generated Hero StringId.</param>
        public static string Activate(string heroId)
        {
            Hero? hero = FindGeneratedHero(heroId);
            if (hero == null)
            {
                return "Generated test officer '" + heroId + "' was not found.";
            }

            if (hero.HeroState != Hero.CharacterStates.Disabled)
            {
                return hero.StringId + " is " + hero.HeroState + ", not Disabled. No activation was performed.";
            }

            Clan? clan = hero.Clan;
            if (clan == null)
            {
                return "Cannot reactivate " + hero.StringId + " because the native hero no longer belongs to a clan.";
            }

            Settlement? home = FindHomeSettlement(clan);
            if (home == null)
            {
                return "Cannot reactivate " + hero.StringId + " because the clan has no usable settlement.";
            }

            hero.ChangeState(Hero.CharacterStates.Active);
            MobileParty party = MobilePartyHelper.SpawnLordParty(hero, home);

            string result = "Reactivated " + hero.StringId + " and spawned native lord party " + party.StringId
                + "; state=" + hero.HeroState
                + "; clan war parties=" + clan.WarPartyComponents.Count + "/" + clan.WarPartyLimit + ".";
            OfficerSafetyLog.Write(result);
            return result;
        }

        /// <summary>
        /// Describes every generated spike officer that can be rediscovered from native
        /// hero state, including Disabled heroes that are no longer active on the map.
        /// </summary>
        public static string DescribeGeneratedOfficers()
        {
            List<Hero> heroes = GetGeneratedHeroes().OrderBy(hero => hero.StringId).ToList();
            if (heroes.Count == 0)
            {
                return "No generated Strategic Navies test officers were found in this campaign.";
            }

            return string.Join(Environment.NewLine, heroes.Select(DescribeHero));
        }

        /// <summary>
        /// Describes one generated officer plus the current host-clan party limit data
        /// needed to determine whether a generated naval command displaces a land party.
        /// </summary>
        /// <param name="heroId">Native generated Hero StringId.</param>
        public static string Inspect(string heroId)
        {
            Hero? hero = FindGeneratedHero(heroId);
            return hero == null ? "Generated test officer '" + heroId + "' was not found." : DescribeHero(hero);
        }

        /// <summary>
        /// Reports the generated officer's live campaign-map location without moving or revealing it.
        /// </summary>
        /// <param name="heroId">Native generated Hero StringId.</param>
        public static string Locate(string heroId)
        {
            Hero? hero = FindGeneratedHero(heroId);
            if (hero == null)
            {
                return "Generated test officer '" + heroId + "' was not found.";
            }

            MobileParty? party = hero.PartyBelongedTo;
            if (party == null)
            {
                return hero.StringId + " has no active MobileParty; state=" + hero.HeroState + ".";
            }

            Vec2 position = party.Position2D;
            Settlement? nearest = Settlement.All
                .Where(settlement => settlement != null)
                .OrderBy(settlement => (settlement.Position2D - position).LengthSquared)
                .FirstOrDefault();

            string nearestText = nearest == null
                ? "<none>"
                : nearest.StringId + " ('" + nearest.Name + "'), distance="
                    + (nearest.Position2D - position).Length.ToString("0.0");

            MobileParty? playerParty = MobileParty.MainParty;
            string playerDistance = playerParty == null
                ? "<unavailable>"
                : (playerParty.Position2D - position).Length.ToString("0.0");

            return hero.StringId
                + " | party=" + party.StringId
                + " | position=(" + position.X.ToString("0.0") + ", " + position.Y.ToString("0.0") + ")"
                + " | currentSettlement=" + (party.CurrentSettlement?.StringId ?? "<none>")
                + " | nearestSettlement=" + nearestText
                + " | distanceFromPlayer=" + playerDistance
                + " | targetParty=" + (party.TargetParty?.StringId ?? "<none>")
                + " | targetSettlement=" + (party.TargetSettlement?.StringId ?? "<none>");
        }

        /// <summary>
        /// Returns the live Bannerlord party-limit values for one native clan.
        /// </summary>
        /// <param name="clanId">Native clan StringId.</param>
        public static string DescribePartyLimits(string clanId)
        {
            Clan? clan = FindClan(clanId);
            if (clan == null)
            {
                return "Unknown clan '" + clanId + "'.";
            }

            int modelLimit = Campaign.Current.Models.ClanTierModel.GetPartyLimitForTier(clan, clan.Tier);
            return clan.StringId + " | " + clan.Name
                + " | tier=" + clan.Tier
                + " | WarPartyComponents=" + clan.WarPartyComponents.Count
                + " | WarPartyLimit=" + clan.WarPartyLimit
                + " | current ClanTierModel limit=" + modelLimit;
        }

        private static string DescribeHero(Hero hero)
        {
            Clan? clan = hero.Clan;
            MobileParty? party = hero.PartyBelongedTo;
            return hero.StringId
                + " | name=" + hero.Name
                + " | state=" + hero.HeroState
                + " | prisoner=" + hero.IsPrisoner
                + " | clan=" + (clan?.StringId ?? "<none>")
                + " | party=" + (party?.StringId ?? "<none>")
                + " | army=" + (party?.Army == null ? "<none>" : party.Army.Name.ToString())
                + " | mapEvent=" + (party?.MapEvent == null ? "no" : "yes")
                + " | siege=" + (party?.SiegeEvent == null ? "no" : "yes")
                + (clan == null
                    ? string.Empty
                    : " | clanWarParties=" + clan.WarPartyComponents.Count + "/" + clan.WarPartyLimit);
        }

        private static Clan? FindClan(string clanId)
        {
            return Clan.All.FirstOrDefault(clan => string.Equals(clan.StringId, clanId, StringComparison.OrdinalIgnoreCase));
        }

        private static Hero? FindGeneratedHero(string heroId)
        {
            return GetGeneratedHeroes().FirstOrDefault(hero => string.Equals(hero.StringId, heroId, StringComparison.OrdinalIgnoreCase));
        }

        private static IEnumerable<Hero> GetGeneratedHeroes()
        {
            return Hero.AllAliveHeroes
                .Concat(Hero.DeadOrDisabledHeroes)
                .Where(hero => hero != null && hero.Name != null && hero.Name.ToString().StartsWith(GeneratedNamePrefix, StringComparison.Ordinal));
        }

        private static Settlement? FindHomeSettlement(Clan? clan)
        {
            if (clan == null)
            {
                return null;
            }

            if (clan.HomeSettlement != null)
            {
                return clan.HomeSettlement;
            }

            if (clan.Settlements.Count > 0)
            {
                return clan.Settlements[0];
            }

            if (clan.Kingdom != null && clan.Kingdom.Settlements.Count > 0)
            {
                return clan.Kingdom.Settlements[0];
            }

            return clan.InitialHomeSettlement;
        }
    }
}
'@ | Set-Content -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'OfficerSafetyOperations.cs') -Encoding UTF8

    @'
using System.Collections.Generic;
using TaleWorlds.CampaignSystem;
using TaleWorlds.Library;

namespace StrategicNavies.OfficerSafetySpike
{
    /// <summary>
    /// Exposes explicit console operations for the disposable generated-officer spike.
    /// </summary>
    public static class OfficerSafetyCommands
    {
        /// <summary>
        /// Executes one Strategic Navies officer-safety research command.
        /// </summary>
        /// <param name="args">Console tokens following <c>snspike.officer</c>.</param>
        /// <returns>Human-readable evidence suitable for copying into the spike report.</returns>
        [CommandLineFunctionality.CommandLineArgumentFunction("officer", "snspike")]
        public static string Officer(List<string> args)
        {
            if (Campaign.Current == null)
            {
                return "Load a campaign before using snspike.officer commands.";
            }

            if (args.Count == 0)
            {
                return Usage();
            }

            string command = args[0].ToLowerInvariant();
            switch (command)
            {
                case "clans":
                    return OfficerSafetyOperations.DescribeClans();
                case "list":
                case "status":
                    return OfficerSafetyOperations.DescribeGeneratedOfficers();
                case "create":
                    return args.Count >= 2 ? OfficerSafetyOperations.Create(args[1]) : "Usage: snspike.officer create <clanId>";
                case "inspect":
                    return args.Count >= 2 ? OfficerSafetyOperations.Inspect(args[1]) : "Usage: snspike.officer inspect <heroId>";
                case "locate":
                    return args.Count >= 2 ? OfficerSafetyOperations.Locate(args[1]) : "Usage: snspike.officer locate <heroId>";
                case "limits":
                    return args.Count >= 2 ? OfficerSafetyOperations.DescribePartyLimits(args[1]) : "Usage: snspike.officer limits <clanId>";
                case "reserve":
                    return args.Count >= 2 ? OfficerSafetyOperations.Reserve(args[1]) : "Usage: snspike.officer reserve <heroId>";
                case "activate":
                    return args.Count >= 2 ? OfficerSafetyOperations.Activate(args[1]) : "Usage: snspike.officer activate <heroId>";
                default:
                    return Usage();
            }
        }

        private static string Usage()
        {
            return "Usage: snspike.officer clans | list | create <clanId> | inspect <heroId> | locate <heroId> | limits <clanId> | reserve <heroId> | activate <heroId>";
        }
    }
}
'@ | Set-Content -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'OfficerSafetyCommands.cs') -Encoding UTF8

    Write-Step "Generated spike project and module under $spikeRoot"
}

function Invoke-SpikeBuild {
    Write-SpikeFiles
    $binDir = Get-BannerlordBinDir
    $root = Resolve-BannerlordGameRoot
    $outputDll = Join-Path -Path $moduleBinRoot -ChildPath 'StrategicNavies.OfficerSafetySpike.dll'

    # Remove stale output so a failed build can never be mistaken for a fresh one.
    if (Test-Path -LiteralPath $outputDll) {
        Remove-Item -LiteralPath $outputDll -Force
    }

    Write-Step "Building spike project against $binDir"
    & dotnet build $projectPath --configuration Release --no-incremental -p:BannerlordGameRoot="$root" -p:TaleWorldsAssemblyDir="$binDir"
    if ($LASTEXITCODE -ne 0) {
        throw "Strategic Navies officer spike build failed with exit code $LASTEXITCODE. Nothing will be published."
    }

    if (-not (Test-Path -LiteralPath $outputDll)) {
        throw "Strategic Navies officer spike build reported success but the expected DLL was not produced: $outputDll"
    }

    Write-Step "Build succeeded: $outputDll"
}

function Publish-SpikeModule {
    $root = Resolve-BannerlordGameRoot
    $targetModuleRoot = Join-Path -Path $root -ChildPath "Modules/$moduleId"

    try {
        Invoke-SpikeBuild
    }
    catch {
        # A previous revision of this spike could copy SubModule.xml even after a
        # failed build. Remove any stale disposable publication so the launcher
        # cannot present it as though a fresh spike DLL exists.
        if (Test-Path -LiteralPath $targetModuleRoot) {
            Remove-Item -LiteralPath $targetModuleRoot -Recurse -Force
            Write-Step "Removed stale disposable publication after build failure: $targetModuleRoot"
        }

        throw
    }

    if (Test-Path -LiteralPath $targetModuleRoot) {
        Remove-Item -LiteralPath $targetModuleRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $targetModuleRoot | Out-Null
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath '*') -Destination $targetModuleRoot -Recurse -Force
    Write-Step "Published disposable spike module to $targetModuleRoot"
    Write-Host ''
    Write-Host 'Enable StrategicNaviesOfficerSafetySpike only for disposable test saves.' -ForegroundColor Yellow
}

function Write-EvidenceTemplate {
    New-SpikeDirectory -Path $evidenceRoot
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path -Path $evidenceRoot -ChildPath "strategic-navies-officer-safety-evidence-$timestamp.md"

    @"
# Strategic Navies Native Officer Safety Evidence — $timestamp

Status: TODO / fill after live Bannerlord 1.4.8 + War Sails testing
Module under test: $moduleId
Workstream: STRATEGIC-NAVIES-1

## Environment

- Bannerlord version:
- War Sails/NavalDLC version:
- Launcher/mod list:
- Disposable test save names:
- Notes:

## Spike invariants

The generated test module contains no CampaignBehavior SyncData, no
SaveableTypeDefiner, no custom Hero type, no custom PartyComponent, and no Harmony.
It deliberately creates only ordinary native Hero and LordPartyComponent state.

Commands:

```text
snspike.officer clans
snspike.officer list
snspike.officer create <clanId>
snspike.officer inspect <heroId>
snspike.officer locate <heroId>
snspike.officer limits <clanId>
snspike.officer reserve <heroId>
snspike.officer activate <heroId>
```

External log:

```text
%LOCALAPPDATA%\Skaldflow\StrategicNaviesOfficerSafetySpike\officer-safety-spike.log
```

## A. Native generated hero + lord party

1. Choose a normal AI kingdom clan with `snspike.officer clans`.
2. Record `snspike.officer limits <clanId>`.
3. Run `snspike.officer create <clanId>` once.
4. Record the returned hero id, party id, WarPartyComponents count, WarPartyLimit,
   and current ClanTierModel limit.
5. Run `snspike.officer inspect <heroId>`.
6. Save as `sn_officer_10_enabled_active` and quit.

Observed:

- Hero id:
- Party id:
- Party count before/after:
- Party limit before/after:
- Notes:

## B. Remove-module load safety

1. Disable/remove `StrategicNaviesOfficerSafetySpike`.
2. Load `sn_officer_10_enabled_active`.
3. Confirm the generated lord/party behaves as an ordinary native Bannerlord lord.
4. Save as `sn_officer_11_disabled_resave_active`.
5. Quit, re-enable the spike, load that save, and run `snspike.officer list`.

Observed:

- Original save loaded with spike absent: TODO
- Re-save with spike absent succeeded: TODO
- Re-save loaded after re-enable: TODO
- Same hero rediscovered: TODO
- Same party/native state remained coherent: TODO

## C. Safe reserve lifecycle

1. Ensure the generated officer is not in an army, battle/map event, siege, or captivity, and is physically inside a friendly clan/kingdom settlement with the player elsewhere.
2. Run `snspike.officer reserve <heroId>`.
3. Confirm the command reports `Disabled` and that the officer no longer has a party.
4. Confirm `snspike.officer inspect <heroId>` reports `Disabled` and no party.
5. Save as `sn_officer_20_enabled_disabled` and quit.
6. Disable/remove the spike and load/re-save that save.
7. Re-enable the spike and confirm the Disabled hero is rediscovered by `list`.
8. Run `snspike.officer activate <heroId>` and verify a normal lord party spawns.

Observed:

- Native ApplyForDisbanding removed the party and allowed Disabled transition: TODO
- Disabled state persisted: TODO
- Save loaded with spike removed: TODO
- Native reactivation succeeded: TODO
- New lord party coherent: TODO

## D. Capture/replacement precursor

This spike does not auto-spawn replacements. The purpose of this test is to prove
that a captured generated officer remains ordinary native prisoner state and that
we can leave that officer untouched while another generated officer is created.

1. Arrange for the first generated officer to be captured normally.
2. Confirm `inspect` reports prisoner state.
3. Confirm `reserve` refuses to disable the prisoner.
4. Create a second generated officer in the same clan or another kingdom clan.
5. Save, disable the spike, load, and verify both heroes remain valid native state.

Observed:

- Captured officer remained coherent: TODO
- Reserve correctly refused capture cleanup: TODO
- Replacement hero created without mutating prisoner: TODO
- Disabled-module load succeeded: TODO

## PASS criteria for adopting generated naval officers

- Active generated officers survive save/reload with the spike removed.
- Disabled generated officers survive save/reload with the spike removed.
- Native Disabled -> Active reactivation is coherent.
- Retirement can wait for safe disbanding and does not require killing a hero.
- A captured officer is left alone rather than being retired underneath captivity.
- The exact clan party-limit cost of each generated command is understood.
- No custom save type is required to rediscover or operate the generated hero.

## Decision

- [ ] PASS — generated native officers are a viable basis for Strategic Navies.
- [ ] CONDITIONAL — viable only with the constraints recorded below.
- [ ] FAIL — use existing native lords instead.

Constraints / follow-up:

- TODO
"@ | Set-Content -LiteralPath $path -Encoding UTF8

    Write-Step "Wrote evidence template: $path"
    Write-Host $path
}

function Clean-Spike {
    if (Test-Path -LiteralPath $spikeRoot) {
        Remove-Item -LiteralPath $spikeRoot -Recurse -Force
        Write-Step "Removed generated spike root $spikeRoot"
    }
}

switch ($Command) {
    'Plan' { Write-Plan }
    'Prepare' { Write-SpikeFiles }
    'Build' { Invoke-SpikeBuild }
    'Publish' { Publish-SpikeModule }
    'EvidenceTemplate' { Write-EvidenceTemplate }
    'Clean' { Clean-Spike }
    default { throw "Unsupported command '$Command'." }
}
