# Tests

This directory contains Pester 5 tests for ai-repo-workflow, including an
integration test that bootstraps a temporary target repository with
`Start-Repo.ps1`, checks CI provider scaffolding and VS Code task merging, and
verifies the generated repo end to end.

Run them from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

The test runner runs Pester `tests/**/*.Tests.ps1` files when present and then
runs external commands configured in `config/test-config.jsonc` for the source
repo, or `config/ai-repo-workflow/test-config.jsonc` in reference-mode target
repos. Configured external commands use `Invoke-AiRepoDiagnosticCommand`, so
stdout, stderr, timing, exit status, and the full command line are saved under
`artifacts/diagnostics/latest` even when the command fails. The Pester portion
requires Pester 5. It prints an install command when the module is not available
and does not install modules automatically.

Patch workflow coverage also proves that file application is reported separately
from post-apply verification, test, build, diagnostics, and snapshot outcomes.
Applied-but-unsuccessful archives must never be labeled as failures to apply.

# Tests

# Tests

# Tests

<!-- ai-repo-workflow:tests-readme:start -->
## ai-repo-workflow smoke test

This repository uses the reference-mode ai-repo-workflow smoke test in
`tests/GeneratedRepoSmoke.Tests.ps1`. It verifies that the supported repository
entry points and reference-mode configuration exist without vendoring the
workflow implementation.

Use the repository entry points rather than ai-repo-workflow source scripts:

```powershell
.\repo-tools.ps1 -Command Verify
.\repo-tools.ps1 -Command Test
```

Detailed command diagnostics are written under `artifacts/diagnostics/latest`.
Do not copy test-suite documentation from the ai-repo-workflow source repository
into this consumer repository.
<!-- ai-repo-workflow:tests-readme:end -->
