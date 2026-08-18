# Captured Lords Grant Influence behavior specification

Status: implemented checkpoint for Bannerlord 1.4.8

## Purpose

`YL.Prisoners.CapturedLordsGrantInfluence` makes continued custody of captured lords contribute to the native daily influence calculation of the clan holding them. The same calculation presents the contribution in Bannerlord's native influence tooltip when descriptions are requested.

The shipped policy applies symmetrically to the player and NPC clans so the mechanic does not give the player a private campaign advantage.

## Runtime identity

The Bannerlord-facing identity is:

- module ID: `YL.Prisoners.CapturedLordsGrantInfluence`;
- assembly: `YL.Prisoners.CapturedLordsGrantInfluence.dll`;
- root namespace: `YL.Prisoners.CapturedLordsGrantInfluence`;
- version: `v0.1.0`.


## Influence policy

Each unique imprisoned lord held by an evaluated clan contributes one daily category value. The shipped defaults are:

- ordinary lord: 0.5 influence;
- clan leader who is not a kingdom ruler: 1.0 influence;
- kingdom ruler: 1.5 influence.

Only the highest matching category applies to a `Hero`. Zero-count or zero-value categories are omitted from the explanation.

The policy intentionally does not add war-state, hostility, alive/dead, acquisition-method, or other eligibility filters beyond native `Hero.IsLord` classification and current native clan custody.

## Player configuration

`module/config/CapturedLordsGrantInfluence.xml` is the authoritative player-editable settings source.

The root attribute:

```xml
<CapturedLordsGrantInfluenceSettings ApplyToAiClans="true">
```

controls AI parity:

- `true` (shipped default): player and NPC clans use the same captured-lord influence rule;
- `false`: the player clan receives the contribution and non-player clans do not.

If `ApplyToAiClans` is omitted, it defaults to `true`.

The `InfluencePerDay` section uses `OrdinaryLord`, `ClanLeader`, and `KingdomRuler` elements. Each `value` is influence per unique prisoner per day, uses invariant decimal notation with a period, must be finite and greater than or equal to zero, and may be `0` to disable that tier.

A missing or invalid file causes the complete policy to fall back to `0.5 / 1.0 / 1.5` and `ApplyToAiClans=true`, with one user-visible warning. Configuration is not save data.

## Custody scope and deduplication

For each clan Bannerlord evaluates, the provider gathers lords from native custody locations:

- mobile parties whose `ActualClan` is the evaluated clan;
- `MobileParty.MainParty` explicitly when the evaluated clan is `Clan.PlayerClan`;
- `clan.DungeonPrisonersOfClan`.

A `HashSet<Hero>` ensures a Hero contributes at most once even if Bannerlord exposes the prisoner through more than one native collection.

## Native politics-model integration

The module registers a `ClanPoliticsModel` replacement through `CampaignGameStarter.AddModel`. `CalculateInfluenceChange` calls `BaseModel.CalculateInfluenceChange` first.

It then determines whether the evaluated clan is the player clan. If it is the player clan, the captured-lord contribution is always applied. If it is an NPC clan, the contribution is applied when `ApplyToAiClans` is true.

All unrelated `ClanPoliticsModel` methods delegate to `BaseModel`.

Bannerlord uses the active politics model for both its native daily influence tick and native influence-tooltip explanation. The gameplay award and displayed breakdown therefore come from one calculation; the module does not award a second copy through a parallel daily event.

`ExplainedNumber` is a value type. Any helper adding a captured-lord contribution must receive the current result by `ref`. Passing the value by value modifies only a numeric copy and can produce a misleading tooltip whose explanation rows appear while `Expected Change` omits the values.

## Tooltip presentation

When descriptions are requested, nonzero categories use native `ExplainedNumber` rows:

- `Captured lords ({COUNT})`;
- `Captured clan leaders ({COUNT})`;
- `Captured kingdom rulers ({COUNT})`.

The first category means ordinary lords who are neither clan leaders nor kingdom rulers.

## Compatibility warning

A diagnostic campaign behavior performs a one-time model-chain check after campaign initialization. It invokes the final active `ClanPoliticsModel` for the player clan and verifies that the invocation counter on `CapturedLordsGrantInfluenceClanPoliticsModel` advances.

If another mod replaces the active politics calculation without delegating through `BaseModel`, the module displays one `InformationManager` warning naming the active model type. It does not fight the other mod, reinstall itself, or create a second influence path.

## Persistence, removal, and rename safety

`CapturedLordsGrantInfluenceCampaignBehavior.SyncData` is empty. The module stores no custom campaign state and defines no custom saveable campaign object types. Disabling/removing it therefore stops future captured-lord influence contributions without leaving module-owned campaign records.

The module ID rename from `YL.Prisoners.LordsGrantInfluence` to `YL.Prisoners.CapturedLordsGrantInfluence` can trigger Bannerlord's ordinary "module set changed" warning when loading a save made with the prior ID. The code does not depend on the old module ID for custom deserialization because there are no module-owned serialized types.

## Compatibility boundary

The module uses Bannerlord's public model/event/UI explanation mechanisms and BannerCord's shared assembly boundary. It uses no Harmony patching and does not replace Gauntlet view models.
