# Repo Hygiene

Repo hygiene is part of ai-repo-workflow.

The repo hygiene scan is a public-safety check for source repositories. It looks for accidental local runtime output, patch archives, workspace files, large files, local path indicators, project-specific deny terms supplied by the developer, and common secret-looking patterns before work is published.

Run it through normal verification:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

Or run the scanner directly:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-RepoHygiene.ps1
```

## Scan Scope

By default, the scanner is Git-aware. It checks source candidates from:

```powershell
git ls-files --cached --others --exclude-standard
```

That means normal verification checks tracked files and untracked files that are not ignored by Git. Git-ignored generated output such as `bin/`, `obj/`, `node_modules/`, runtime caches, and build artifacts is not part of the default verify gate. Building a .NET, WinUI, Node, or other generated-output-heavy project should not make `verify.ps1` fail merely because ignored output exists on disk.

This does not allow binaries or artifacts into source. A DLL, zip, large file, workspace file, denied term, or secret-looking value still fails hygiene when it is tracked or untracked-but-not-ignored.

`Start-Repo.ps1` and `Update-GitIgnore.ps1` can merge AI Repo Workflow safe defaults, diagnostics output ignores, and common .NET, NuGet, Visual Studio, `bin/`, and `obj/` ignore rules into an existing `.gitignore` without replacing custom rules. The safe defaults include current-run diagnostics markers such as `artifacts/diagnostics/latest/README.md`, because the `latest` diagnostics folder is volatile output. The merge writes clearly marked `# BEGIN AI Repo Workflow: ...` / `# END AI Repo Workflow: ...` managed blocks and removes duplicate exact managed lines that were already present elsewhere in `.gitignore`. Existing custom rules stay outside the managed blocks.

Ignore rules only affect new/untracked files. After `.gitignore` is updated, the tools check for tracked files that now match `.gitignore`; the wizards ask whether to run `git rm --cached` so those files remain on disk but leave the Git index. Automation can use `-UntrackGitIgnoredFiles` or `-UntrackGitIgnoredFiles $true` depending on the entry point to perform that cleanup without the prompt.

For already-registered repositories, use the deployed package task `AI Repo Workflow: Update GitIgnore` instead of rerunning Start-Repo. It lists registered repos, lets the user choose the target, updates managed `.gitignore` blocks, optionally untracks newly ignored files, and optionally runs the target repo's verify script.

For a manual deep scan of every physical file and directory on disk, including ignored paths, run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-RepoHygiene.ps1 -IncludeIgnored
```

## Default Checks

Committed checks stay generic. The scanner fails on source-candidate runtime folders, patch archives, local editor workspace files, large files, common local machine path indicators, and secret-looking strings such as API keys, tokens, passwords, private key headers, GitHub tokens, and AWS access key ids.

When a source-text check fails, the scanner reports every match it finds instead of stopping at the first match in the file. Each text finding includes the repo-relative path, line, column, and a short single-line snippet so humans can inspect the complete set of findings before deciding whether to fix, allow-list, or intentionally bypass the push hook. Secret-looking findings report the location and context but redact the matched secret-looking value from the snippet.

`.vscode/tasks.json` is allowed because Start-Repo can intentionally scaffold committed team tasks for AI Repo Workflow. Other `.vscode` files remain local-workspace candidates and should not be committed by default, including `settings.json`, `launch.json`, `.code-workspace` files, and editor/cache files.

Runtime state should live outside the public source repository. For this package, the default runtime root is:

```text
<RuntimeRoot>
```

That private runtime root holds incoming patches, applied or failed patch archives, snapshots, and patch-run logs. Those files can contain private diagnostics or generated artifacts, so they should not live in the public repo even when ignored by Git.

## Local Config

Personal and project-specific deny terms belong in `repo-hygiene.local.jsonc`. That file is optional and ignored by Git. Keep real usernames, client names, private project names, and private repo names there instead of committing them to public source.

Start from the committed example:

```powershell
Copy-Item .\repo-hygiene.example.jsonc .\repo-hygiene.local.jsonc
```

Then replace the placeholders in `repo-hygiene.local.jsonc` with values that are private to the machine or repository:

```jsonc
{
  "denyTerms": [
    "YOUR_WINDOWS_USERNAME",
    "YOUR_PRIVATE_PROJECT_NAME",
    "YOUR_CLIENT_NAME"
  ],
  "allowTerms": [
    "YOUR_PUBLIC_SAMPLE_NAME"
  ],
  "allowPatterns": [
    "example-only-[A-Za-z0-9_-]+"
  ],
  "maxFileSizeMB": 5
}
```

The example uses fake placeholder values only. Do not commit a local config with real private terms.

The committed example also allows deny-term matches in `repo-hygiene.example.jsonc` and `docs/guides/repo-hygiene.md`, because those files intentionally document placeholder deny terms. Keep that allow-list narrow. Secret-pattern checks still run unless explicitly allowed.

## Starter Config

`Start-Repo.ps1` can seed new repositories with an ignored local hygiene config. It checks for this private global starter file:

```text
<RuntimeRoot>/config/repo-hygiene.defaults.local.jsonc
```

If that file exists, `Start-Repo.ps1` copies it to the target repository as `repo-hygiene.local.jsonc`. This runtime-local starter may contain real user-specific deny terms because it lives outside the public package repository.

If the private starter does not exist, `Start-Repo.ps1` creates `repo-hygiene.local.jsonc` from the committed safe `repo-hygiene.example.jsonc` placeholder template. In both cases, the target repository's `.gitignore` includes `repo-hygiene.local.jsonc`, and the bootstrap output reports whether the local config came from the private global starter or the safe placeholder template.

Do not add the private starter file to `ai-repo-workflow`. Only files under the private runtime root should contain real usernames, private project names, client names, or other local deny terms.

## False Positives

Use allow-lists sparingly and keep them specific:

- `allowTerms` allows an exact deny term when that term is legitimate public content.
- `allowPatterns` allows deny-term findings when the file text matches a regex pattern.
- `allowPaths` allows a repo-relative wildcard path for all hygiene categories.
- `allowZipPaths`, `allowLargeFilePaths`, `allowDenyTermPaths`, and `allowSecretPatternPaths` allow one category for matching repo-relative wildcard paths.

You can also pass a config path explicitly:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-RepoHygiene.ps1 -HygieneConfigPath .\repo-hygiene.local.jsonc
```

Local config is ignored because it is expected to contain the exact private strings that public hygiene scanning is meant to keep out of commits.

## Package update propagation

`Test-RepoHygiene.ps1` is a managed repo-level workflow file. Publishing `ai-repo-workflow` includes it in the deployed package root, and `Update-WorkflowPackage.ps1` refreshes existing target repo copies during package updates. This prevents target repos from keeping stale hygiene behavior after the source package changes.
