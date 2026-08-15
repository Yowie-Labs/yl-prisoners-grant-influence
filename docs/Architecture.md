# Architecture

`YL.Prisoners.LordsGrantInfluence` owns its prisoner-influence policy and Bannerlord integration. `BannerCord` supplies the shared runtime assembly boundary, but installing BannerCord alone does not enable this mechanic.

Normative behavior is defined in [`specifications/Lords_Grant_Influence.md`](specifications/Lords_Grant_Influence.md).

## Composition

`LordsGrantInfluenceSubModule` creates `ImprisonedLordInfluenceCalculator` and `PlayerClanImprisonedLordProvider`, registers `LordsGrantInfluenceClanPoliticsModel` with `CampaignGameStarter.AddModel`, and registers `LordsGrantInfluenceCampaignBehavior` for diagnostics.

The calculator reads `module/config/LordsGrantInfluence.xml` once when it is constructed for the campaign session. Configuration is runtime input only; it is not stored in the Bannerlord save.

## Gameplay model

`LordsGrantInfluenceClanPoliticsModel` is the only influence-award integration. It delegates first to `BaseModel`, then augments the returned `ExplainedNumber` for the player clan. Because Bannerlord uses the same politics calculation for simulation and tooltip descriptions, the native daily award and UI explanation use one calculation.

`ExplainedNumber` is a value type. Helpers that mutate the active result must receive it by `ref`; passing it by value can leave the numeric result unchanged even while explanation backing data becomes visible in the tooltip. The regression tests explicitly protect this boundary.

Every unrelated `ClanPoliticsModel` method delegates to the previous model. This preserves vanilla, War Sails, and other well-behaved model contributions regardless of load order.

## Custody and policy services

`PlayerClanImprisonedLordProvider` owns discovery/deduplication of native custody locations. `ImprisonedLordInfluenceCalculator` owns the highest-tier-only classification policy and configurable per-tier values, and returns an `ImprisonedLordInfluenceBreakdown`; neither service mutates campaign state.

The shipped defaults are 0.5 for an ordinary lord, 1.0 for a clan leader, and 1.5 for a kingdom ruler. Invalid or missing XML falls back to those defaults and produces a user-visible warning instead of aborting campaign startup.

## Compatibility diagnostic

`LordsGrantInfluenceCampaignBehavior` awards no influence. On the first suitable hourly tick it performs one behavioral model-chain probe. If calling the final active politics model does not reach `LordsGrantInfluenceClanPoliticsModel`, the player receives one warning naming the active model type. The module does not override or repair a non-delegating third-party model.

## Persistence

`SyncData` is empty and there is no module-owned campaign save state. Runtime behavior is reconstructed from Bannerlord's native prisoner/model state plus the current XML settings each session.
