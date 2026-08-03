# AGENTS.md - YL.Prisoners.LordsGrantInfluence

This repository owns one optional Bannerlord gameplay mod. Installing and enabling this module enables the rule; BannerCord itself must remain policy-free.

Naming rules:

- Public mod title: `YL Prisoners: Lords Grant Influence`.
- Repository, assembly, and root namespace: `YL.Prisoners.LordsGrantInfluence`.
- Bannerlord module ID: `YLPrisonersLordsGrantInfluence`.
- Preserve the anonymous `YL <Vertical>: <Feature>` product convention for related mods.

Product rules:

- Depend on the dedicated `BannerCord` module and compile against `BannerCord.Core`.
- Keep the 1/2/3 prisoner-influence policy in this repository.
- Do not add the behavior to `Bannercord.Core` or `BannerCord.Module`.
- Count each unique imprisoned Hero lord held by the player clan once per day.
- Include the main party, every player-clan mobile party, and every player-clan dungeon.
- Award 1 influence for a lord, 2 for a clan leader, and 3 for a kingdom ruler; only the highest tier applies.
- Do not add war, faction, peace, alive/dead, or hostility checks.
- Keep the behavior stateless; do not add custom save data.

<!-- ai-repo-workflow:start -->
# AGENTS.md - YL.Prisoners.LordsGrantInfluence

Project: `YL.Prisoners.LordsGrantInfluence`
Tier: `PUBLIC_PORTFOLIO`
Visibility: `PUBLIC_GITHUB`

## Source of truth

Treat a supplied snapshot as canonical; otherwise use the current checkout. Do not substitute remembered code, another repository, or workspace shadow copies.

## Work mode

Default to normal approval mode. Before editing or packaging, state the exact approved target, exact files, non-goals, ambiguities, and verification plan, then wait for approval unless fast patch mode was explicitly requested.

Implement only approved behavior. Do not add architecture, cleanup, compatibility work, or unrelated changes. Stop and report a material conflict between the request, specifications, plans, and code.

## Repository work

Inspect only task-relevant artifacts. Reference-mode repositories use the deployed ai-repo-workflow package; do not vendor or modify `tools/ai-repo-workflow` implementation files in the target repository.

Run `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1` and never claim verification passed without evidence. After a failure, inspect current-run diagnostics under `artifacts/diagnostics/latest/` before asking for copied terminal output. `Start-Transcript` is not sufficient evidence for native tools; external commands must use `scripts/Invoke-RepoDiagnosticCommand.ps1` or another explicit stdout/stderr capture path.

## C# source layout

Put each top-level class, record, struct, interface, enum, and delegate in its own file named after the type. Partial files may use `TypeName.Purpose.cs`. New types always receive their own files. A migration allowance may temporarily grandfather existing violations; do not add declarations to those files or perform unrelated broad extraction.

## Patch and snapshot workflow

When this repository belongs to a configured workspace, run patch and snapshot operations from the workspace root through `repo-tools.ps1`. A workspace snapshot may contain authoritative child snapshots under `projects/<project-name>/`; inspect them before requesting separate files.

For multi-repository work, produce one workspace bundle containing `manifest.json` and one routed patch ZIP per target under `patches/`. Each inner ZIP uses the target's configured prefix and contains only full target-repository-relative changed paths, with no wrapper, workspace-relative, snapshot, temporary, or absolute paths. A focused single-repository patch remains allowed and is still applied from the workspace root.

Report patch mode, targets, prefixes, changed files, apply command, verification, suggested commit message, and next step.
<!-- ai-repo-workflow:end -->
