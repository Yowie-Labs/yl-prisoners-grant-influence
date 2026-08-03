# YL Prisoners: Lords Grant Influence

A small optional Bannerlord module that makes continued custody of captured lords politically useful.

Each daily player-clan tick awards:

- ordinary lord: **1 influence**;
- clan leader: **2 influence**;
- kingdom ruler: **3 influence**.

Only the highest tier applies. Each Hero is counted once across the main party, player-clan parties, and player-clan dungeons.

The module is stateless. Removing or disabling it stops future awards and leaves no custom save data.

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
