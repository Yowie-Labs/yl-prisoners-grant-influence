# YL Prisoners: Captured Lords Grant Influence

A small optional Bannerlord module that makes continued custody of captured lords politically useful for both the player and NPC clans.

The shipped daily defaults are:

- ordinary lord: **0.5 influence**;
- clan leader: **1.0 influence**;
- kingdom ruler: **1.5 influence**.

Only the highest tier applies. Each Hero is counted once across the evaluated clan's native mobile-party and dungeon custody locations.

The same chained native `ClanPoliticsModel` calculation drives Bannerlord's real daily influence change and the influence tooltip. Tooltip rows such as `Captured lords (4) +2` therefore contribute to the same numeric `Expected Change`; the implementation deliberately passes `ExplainedNumber` by reference so the explanation and gameplay total cannot diverge.

## Player configuration

Edit:

```text
module/config/CapturedLordsGrantInfluence.xml
```

The root setting:

```xml
<CapturedLordsGrantInfluenceSettings ApplyToAiClans="true">
```

controls campaign parity:

- `true` (default): NPC clans receive the same captured-lord influence rule as the player;
- `false`: only the player clan receives the captured-lord contribution.

The `InfluencePerDay` entries configure daily influence per unique prisoner. Values use a period as the decimal separator and must be finite numbers greater than or equal to zero. Setting a tier to `0` disables influence from that tier.

Configuration is loaded when a campaign session starts, so reload/restart after editing it. If the XML is missing or malformed, the module displays a warning and falls back to `0.5 / 1.0 / 1.5` with AI parity enabled rather than failing the campaign.

The module remains stateless. XML settings are not serialized into Bannerlord saves.

## Runtime identity

Bannerlord-facing identity is now:

```text
Module ID:  YL.Prisoners.CapturedLordsGrantInfluence
Assembly:   YL.Prisoners.CapturedLordsGrantInfluence.dll
Namespace:  YL.Prisoners.CapturedLordsGrantInfluence
Version:    v0.1.0
```

Changing the Bannerlord module ID can produce Bannerlord's normal "module set changed" warning on an existing save. This module defines no custom saveable campaign objects or custom `SyncData`, so the rename does not introduce a module-owned deserialization dependency.

## Dependencies

- Bannerlord modules declared in `module/SubModule.xml`;
- installed `BannerCord` module version 0.0.5 or later;
- `BannerCord.Core` 0.0.5 package for compilation only. BannerCord supplies the runtime assembly.

## Build

Configure `BannerlordGameRoot` through the sibling `Skaldflow.Workspace/Skaldflow.Workspace.local.props` or an ignored `Directory.Build.props.user`, then run:

```powershell
dotnet build .\src\YL.Prisoners.CapturedLordsGrantInfluence.csproj -c Release -p:Platform=x64
```

The project produces:

```text
module/bin/Win64_Shipping_Client/YL.Prisoners.CapturedLordsGrantInfluence.dll
```

A successful build removes stale pre-rename `YL.Prisoners.LordsGrantInfluence.dll/.pdb` output from that module bin directory so deployments cannot contain both assemblies.

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

Runtime smoke testing should cover the player and at least one NPC clan holding a lord, plus an existing save created with the previous module ID.

## Naming convention

This mod belongs to the anonymous `YL` series. Public titles use `YL <Vertical>: <Feature>`; technical runtime identifiers use `YL.<Vertical>.<Feature>`.
