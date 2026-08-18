# Architecture

`YL.Prisoners.CapturedLordsGrantInfluence` owns its captured-lord influence policy and Bannerlord integration. `BannerCord` supplies the shared runtime assembly boundary, but installing BannerCord alone does not enable this mechanic.

Normative behavior is defined in [`specifications/Captured_Lords_Grant_Influence.md`](specifications/Captured_Lords_Grant_Influence.md).

## Composition

`CapturedLordsGrantInfluenceSubModule` constructs `ImprisonedLordInfluenceCalculator` and `ClanImprisonedLordProvider`, registers `CapturedLordsGrantInfluenceClanPoliticsModel` through `CampaignGameStarter.AddModel`, and registers `CapturedLordsGrantInfluenceCampaignBehavior` only for the one-time compatibility diagnostic.

The calculator reads `module/config/CapturedLordsGrantInfluence.xml` once when the campaign session is composed. Configuration is runtime input only and is not stored in the Bannerlord save.

## Gameplay model

`CapturedLordsGrantInfluenceClanPoliticsModel` is the only influence-award integration. It delegates first to `BaseModel`, then augments the returned `ExplainedNumber` for the clan Bannerlord is currently evaluating.

By default the rule applies to both the player and NPC clans. `ApplyToAiClans="false"` short-circuits the contribution for non-player clans while preserving the player's contribution.

Because Bannerlord uses the same politics calculation for simulation and tooltip descriptions, the native daily award and UI explanation use one calculation.

`ExplainedNumber` is a value type. Helpers that mutate the active result receive it by `ref`; passing it by value can leave the numeric result unchanged even while explanation backing data becomes visible in the tooltip. Regression tests explicitly protect this boundary.

Every unrelated `ClanPoliticsModel` method delegates to the previous model. This preserves vanilla, War Sails, and other well-behaved model contributions regardless of load order.

## Custody and policy services

`ClanImprisonedLordProvider` is clan-generic. For the evaluated clan it scans:

- every native mobile party whose `ActualClan` is that clan;
- the player's `MobileParty.MainParty` explicitly when evaluating `Clan.PlayerClan`;
- `clan.DungeonPrisonersOfClan`.

A `HashSet<Hero>` deduplicates a lord exposed through more than one native collection.

`ImprisonedLordInfluenceCalculator` owns the highest-tier-only classification policy and configurable per-tier values. It returns one `ImprisonedLordInfluenceBreakdown` and never mutates campaign state.

The shipped defaults are 0.5 for an ordinary lord, 1.0 for a clan leader, and 1.5 for a kingdom ruler. Missing `ApplyToAiClans` is treated as `true` so pre-parity XML files remain valid. Invalid or missing XML falls back to all shipped defaults and produces a user-visible warning.

## Compatibility diagnostic

`CapturedLordsGrantInfluenceCampaignBehavior` awards no influence. On the first suitable hourly tick it performs one behavioral model-chain probe using the player clan. If calling the final active politics model does not reach `CapturedLordsGrantInfluenceClanPoliticsModel`, the player receives one warning naming the active model type. The module does not override or repair a non-delegating third-party model.

The probe only verifies chain reachability; it does not need to test every NPC clan because all clans traverse the same active `ClanPoliticsModel` chain.

## Persistence and removal

`SyncData` is empty and there is no module-owned campaign save state. Runtime behavior is reconstructed from Bannerlord's native prisoner/model state plus the current XML settings each session.

The runtime module ID changed from `YL.Prisoners.LordsGrantInfluence` to `YL.Prisoners.CapturedLordsGrantInfluence`. Existing saves may therefore display Bannerlord's ordinary changed-module-set warning, but there are no module-owned serialized object types that require the old ID to deserialize.

## Generated output migration

The project, assembly, namespace, module, repository, and configuration names all use the Captured Lords identity. After a successful build, the project deletes only the stale `YL.Prisoners.LordsGrantInfluence.dll/.pdb` pre-rename output from `module/bin/Win64_Shipping_Client`; it must never delete the current `YL.Prisoners.CapturedLordsGrantInfluence.dll/.pdb` output.
