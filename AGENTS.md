# AGENTS.md - YL.Prisoners.CapturedLordsGrantInfluence

This repository owns one optional Bannerlord gameplay mod. Installing and enabling this module enables the rule; BannerCord itself must remain policy-free.

Naming rules:

- Public mod title: `YL Prisoners: Captured Lords Grant Influence`.
- Repository, project, Bannerlord module ID, assembly, and root namespace: `YL.Prisoners.CapturedLordsGrantInfluence`.
- Preserve the anonymous `YL <Vertical>: <Feature>` product convention for related mods.

Product rules:

- Depend on the dedicated `BannerCord` module and compile against `BannerCord.Core`.
- Keep the captured-lord influence policy and its player-editable XML configuration in this repository.
- Do not add the behavior to `Bannercord.Core` or `BannerCord.Module`.
- Count each unique imprisoned Hero lord held by the clan being evaluated once per daily influence calculation.
- Include the evaluated clan's native mobile-party and dungeon custody; include `MobileParty.MainParty` explicitly for the player clan.
- Ship defaults of 0.5 influence for a lord, 1.0 for a clan leader, and 1.5 for a kingdom ruler; load player overrides from `module/config/CapturedLordsGrantInfluence.xml`; only the highest tier applies.
- Apply the same rule to NPC clans by default. `ApplyToAiClans="false"` may disable AI participation without changing player behavior.
- Do not add war, faction, peace, alive/dead, or hostility checks.
- Keep the behavior stateless; do not add custom save data.

<!-- ai-repo-workflow:start -->
# AGENTS.md - YL.Prisoners.CapturedLordsGrantInfluence

Project: `YL.Prisoners.CapturedLordsGrantInfluence`
Tier: `PUBLIC_PORTFOLIO`
Visibility: `PUBLIC_GITHUB`

## Source of truth

Treat a supplied snapshot as canonical; otherwise use the current checkout. Never substitute remembered or shadow copies.

## Work mode

Default to normal approval mode. Before edits/packages, state target/files, non-goals, ambiguities, and verification; wait unless fast patch mode was requested. Stop on material conflicts.

## Example hygiene

In public repos, examples/tests/docs use neutral fictional identifiers and placeholder paths; never copy consumer names, organizations, usernames, or machine paths.

## Workstream identity

Every patch has a workstream ID/purpose, but ordinary work does not require an active-work record or lease. Continue an established ID when appropriate; otherwise create a descriptive task ID.

Read active reservations before editing. Pre-lease only expensive/high-collision work: always for coordinated multi-repo/shared-contract/broad migration work; otherwise when at least two apply—>6 files, >2 subsystems, nearby active work, expensive verification, costly rebase. State `Pre-lease: yes/no` and why. If yes, stop after the approved plan, produce one control-only reservation patch, and wait for successful apply before editing; otherwise implement normally. Control apply skips product verification/snapshots.

Before using diagnostics/snapshots, compare embedded `workstreamId` with the task; route mismatches to the owning workstream.

## Repository work

Inspect only task-relevant artifacts. Reference-mode repositories use the deployed ai-repo-workflow package; do not vendor or modify `tools/ai-repo-workflow` implementation files in the target repository.

Run `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1` when requested or as the pre-push gate; never claim success without evidence. Patch/snapshot operations do not run Verify. After failures inspect `artifacts/diagnostics/latest/`. External commands must capture stdout/stderr; `Start-Transcript` alone is insufficient.

## Agent instruction profiles

Language/client/team profiles render in this `AGENTS.md`. Manage with `./repo-tools.ps1 -Command AgentInstructions`; text outside managed blocks is repository-owned.

## Patch and snapshot workflow

Configured workspaces run patch/snapshot operations from the workspace root. Multi-repo work uses one `WorkspacePatchBundle` with `manifest.json` schema 1 and one routed child ZIP per target/workstream. Do not hand-author bundles; use `ValidateWorkspacePatchBundle` and `ValidatePatch`. Child snapshots use `projects/<project-name>/`.

When `workstreamRouting.enabled`, per-path base state/hash is the optimistic concurrency authority. `docs/work/active/<workstream>.json` is optional and reserves paths only for deliberate pre-leases. Ordinary implementation needs no lease. Touched-path drift or another workstream's reservation rejects before writes; unrelated reservations do not block disjoint patches. Control patches stay separate from implementation.

Manual patch metadata uses root `.ai-repo-workflow-patch.json` schema 2. Root keys: `schemaVersion`, `workstreamId`, `workstreamPurpose`, `patchId`, `targetRepository`, optional `baseReference`, `files`; no extras. Follow `config/ai-repo-workflow/agent-workflow-summary.jsonc` → `patchMetadataContract`. `files[].baseState`: existing file=`file` + `baseSha256`; directory=`directory` + `baseSha256`; absent=`absent` without `baseSha256`. Never use `present`/`exists` or omit `baseState`. Intentional deletes use root `delete.txt`; follow `patchZipRules.deleteManifest` for its format and metadata interaction. Name patches `<project>-patch-<workstream>-<patch-id>.zip`.

Apply Patch never runs Verify. After writes it runs present `patch.after.ps1`, then `scripts/test.ps1`; bundles defer both until child writes finish. Incomplete apply skips the hook but still runs tests. ZIPs contain only target-relative changes plus metadata.

Failure diagnostics identify the workstream and recovery. On stale state, use compact current target files first and say `Rebase this patch against the current files in the diagnostic.` Post-apply diagnostics include resolvable current files named by failure logs. Ask for a full snapshot only if insufficient. Report workstream, target/prefix, changed files, apply command, verification, commit message, next step.
<!-- ai-repo-workflow:end -->

<!-- ai-repo-workflow:conventions:start -->
<!-- Generated from configured instruction profiles. Manage with ./repo-tools.ps1 -Command AgentInstructions. Do not edit this block directly. -->
## C# conventions

Keep one top-level type per file: class, record, struct, interface, enum, or delegate. Prefer `TypeName.cs`; a distinct single-type companion may use `TypeName.Purpose.cs`. Do not add declarations to grandfathered migration exceptions.
<!-- ai-repo-workflow:conventions:end -->
