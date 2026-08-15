# YL Prisoners: Lords Grant Influence

A small optional Bannerlord module that makes continued custody of captured lords politically useful.

The shipped daily defaults are:

- ordinary lord: **0.5 influence**;
- clan leader: **1.0 influence**;
- kingdom ruler: **1.5 influence**.

Only the highest tier applies. Each Hero is counted once across the main party, player-clan parties, and player-clan dungeons.

The same native `ClanPoliticsModel` calculation drives both Bannerlord's real daily influence change and the influence tooltip. The tooltip therefore shows separate non-zero rows such as `Captured lords (4) +2` or `Captured clan leaders (2) +2` while the numeric `Expected Change` includes those same values.

## Player configuration

The three per-prisoner values are intentionally player-editable. Change:

```text
module/config/LordsGrantInfluence.xml
```

The shipped file contains comments explaining every setting. Values are daily influence per unique prisoner, use a period as the decimal separator, and must be zero or greater. Setting a value to `0` disables influence from that prisoner tier.

The XML is loaded when the campaign session starts, so restart/reload after editing it. If the file is missing or malformed, the module displays a warning and falls back to the shipped `0.5 / 1.0 / 1.5` defaults rather than failing the campaign.

The module is stateless. Removing or disabling it stops future awards and leaves no custom save data; the XML settings are not serialized into Bannerlord saves.

## Dependencies

- Bannerlord 1.4.5 modules declared in `module/SubModule.xml`;
- installed `BannerCord` module version 0.0.5 or later;
- `BannerCord.Core` 0.0.5 package for compilation only. The DLL is supplied at runtime by BannerCord.

## Build

Configure `BannerlordGameRoot` through the sibling `Skaldflow.Workspace/Skaldflow.Workspace.local.props` or an ignored `Directory.Build.props.user`, then run:

```powershell
dotnet build .\src\YL.Prisoners.LordsGrantInfluence.csproj -c Release -p:Platform=x64
```

The project writes its DLL directly into the complete deployable module directory:

```text
module/bin/Win64_Shipping_Client/YL.Prisoners.LordsGrantInfluence.dll
```

After a successful build, the entire `module/` directory can be copied manually to `Bannerlord/Modules/YLPrisonersLordsGrantInfluence/`.

After configuring the shared BannerCord publisher local settings, it can be built, backed up, and installed from `Skaldflow.Workspace` with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-BannerlordModulesWorkflow.ps1 `
  -Command BuildPublishAll `
  -ModuleId YLPrisonersLordsGrantInfluence
```

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

## Naming convention

This mod belongs to the anonymous `YL` series. Public titles use `YL <Vertical>: <Feature>`; technical identifiers use `YL.<Vertical>.<Feature>`.
