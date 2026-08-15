# Lords Grant Influence behavior specification

Status: implemented checkpoint for Bannerlord 1.4.8

## Purpose

`YL.Prisoners.LordsGrantInfluence` makes continued custody of captured lords contribute to the player clan's native daily influence calculation while presenting the same contribution in Bannerlord's native influence tooltip.

## Influence policy

Each unique imprisoned lord held by the player clan contributes one daily category value. The shipped defaults are:

- ordinary lord: 0.5 influence;
- clan leader who is not a kingdom ruler: 1.0 influence;
- kingdom ruler: 1.5 influence.

Only the highest matching category applies to a Hero. Zero-count or zero-value categories are omitted from the explanation.

The current policy intentionally does not add war-state, hostility, alive/dead, acquisition-method, or other eligibility filters beyond the native `Hero.IsLord` classification and current player-clan custody.

## Player configuration

`module/config/LordsGrantInfluence.xml` is the authoritative player-editable source for the three per-prisoner values. It is loaded once when the campaign session composes the calculator.

Configuration requirements:

- use the `OrdinaryLord`, `ClanLeader`, and `KingdomRuler` entries under `InfluencePerDay`;
- each `value` is influence per unique prisoner per day;
- values use invariant decimal notation with a period;
- values must be finite and greater than or equal to zero;
- zero disables influence from that tier;
- a missing or invalid file causes the complete policy to fall back to the shipped 0.5 / 1.0 / 1.5 defaults and displays a warning.

The configuration is not save data. Changing or removing the module does not leave custom settings records in a Bannerlord campaign save.

## Custody scope and deduplication

The provider gathers lords from native player-clan custody locations: the main party, other player-clan mobile parties, and player-clan dungeon prisoners. A Hero is counted once even if Bannerlord exposes the same prisoner through more than one collection.

## Native politics-model integration

The module registers a `ClanPoliticsModel` replacement through `CampaignGameStarter.AddModel`. Its `CalculateInfluenceChange` implementation calls `BaseModel.CalculateInfluenceChange` first and then adds this module's contribution only for `Clan.PlayerClan`. All unrelated `ClanPoliticsModel` methods delegate to `BaseModel`.

This chaining contract is required because Bannerlord uses the active politics model for both the native daily influence tick and the native influence-tooltip explanation. The gameplay award and the displayed breakdown therefore come from one calculation; the module does not award a second copy from a parallel daily campaign event.

`ExplainedNumber` is a value type. Any helper that adds a prisoner contribution must receive the current result by `ref`. Passing the value into a mutating helper by value modifies only the helper's numeric copy and can produce a misleading tooltip in which explanation rows appear while `Expected Change` omits those values. The by-reference mutation is therefore a required behavior, not a style preference.

## Tooltip presentation

When descriptions are requested, nonzero prisoner categories appear as native `ExplainedNumber` lines using the localized labels:

- `Captured lords ({COUNT})`;
- `Captured clan leaders ({COUNT})`;
- `Captured kingdom rulers ({COUNT})`.

The first category means ordinary lords who are neither clan leaders nor kingdom rulers. The more specific wording avoids implying that leader/ruler prisoners should also be included in the ordinary count.

## Compatibility warning

A diagnostic campaign behavior runs a one-time model-chain check after campaign initialization. It invokes the final active `ClanPoliticsModel` and verifies that the invocation counter on `LordsGrantInfluenceClanPoliticsModel` advances during that call.

If another mod replaces the active politics calculation without delegating through `BaseModel`, the module displays one `InformationManager` warning that names the active model type. It does not fight the other mod, reinstall itself, or create a second influence-award path.

## Persistence and removal

`LordsGrantInfluenceCampaignBehavior.SyncData` is empty. The module stores no custom campaign state and defines no custom saveable campaign object types. Disabling/removing it therefore stops future prisoner influence contributions without leaving module-owned campaign records behind.

## Compatibility boundary

The module uses Bannerlord's public model/event/UI explanation mechanisms and BannerCord's shared assembly boundary. It uses no Harmony patching and does not replace Gauntlet view models.
