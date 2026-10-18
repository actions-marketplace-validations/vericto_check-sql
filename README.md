# Vericto SQL Check

A GitHub Action that checks the SQL in your pull requests (migrations, ad-hoc
scripts, generated queries) against your [Vericto](https://vericto.com)
workspace's rules before it runs anywhere. Findings appear as Code Scanning
annotations on the PR, and a blocked statement fails the job.

The action wraps [`vericto check`](https://github.com/vericto/vericto-cli) from
the Vericto CLI. It downloads a pinned CLI release, verifies its SHA-256 before
extracting it, runs the check and uploads the SARIF report.

- Works on Linux (x64, arm64), macOS (x64, arm64) and Windows (x64) runners.
- Checks only the `*.sql` files a PR changes by default, or the files you list.
- Authenticates with an API key or with GitHub OIDC (no stored secret).
- Exits with the CLI's code, so a block fails the build and an outage is not
  mistaken for a pass.

## Quick start (API key)

1. Create an API key with the `ci_dryrun:execute` scope in the Vericto
   dashboard ([API keys](https://vericto.com/docs/api-keys)).
2. Add it to the repository as a secret named `VERICTO_API_KEY`
   (Settings, Secrets and variables, Actions).
3. Add `.github/workflows/vericto.yml`:

```yaml
name: Vericto SQL check

on:
  pull_request:
    paths: ["**/*.sql"]

permissions:
  contents: read
  security-events: write # upload SARIF to Code Scanning
  actions: read          # needed by the SARIF upload in private repositories

jobs:
  vericto:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # full history, so the PR's changed files can be diffed

      - uses: vericto/check-sql@v1
        with:
          api-key: ${{ secrets.VERICTO_API_KEY }}
```

That is the whole setup: the action checks the `*.sql` files the PR changes
(`dialect` defaults to postgres) and the findings show up on the PR.

## OIDC (no long-lived secret)

With OIDC, the job proves its identity to Vericto with a short-lived GitHub
token instead of a stored key. The CLI exchanges the token for a key scoped to
`ci_dryrun:execute`, keeps it in memory for the run and never writes it to disk.

1. In the Vericto dashboard, add a trust policy to the workspace: issuer
   `https://token.actions.githubusercontent.com`, audience `vericto` and a
   subject pattern such as `repo:my-org/*`.
2. Give the job `id-token: write` and pass the workspace ID:

```yaml
permissions:
  contents: read
  security-events: write
  actions: read
  id-token: write # mint the OIDC token

jobs:
  vericto:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - uses: vericto/check-sql@v1
        with:
          oidc: true
          workspace: ws_123
```

`workspace` can also come from `workspace_id` in `.vericto.toml`.

## Inputs

| Input | Default | Description |
|---|---|---|
| `api-key` | | Vericto API key (`vtro_...`), from a secret. Not used with `oidc: true`. Falls back to a `VERICTO_API_KEY` env var set on the job. |
| `oidc` | `false` | Authenticate with GitHub OIDC. Needs `id-token: write`. |
| `workspace` | | Workspace ID for OIDC. Falls back to `VERICTO_WORKSPACE_ID`, then `.vericto.toml`. |
| `files` | | Paths or globs (`*`, `?`, `[...]`, `**`), separated by spaces or newlines, relative to `working-directory`. A directory means every `*.sql` under it. Empty: check changed files. |
| `changed` | `true` when `files` is empty | Check only the `*.sql` files changed against the base (see [Changed files](#changed-files)). |
| `since` | | Base ref for the changed-files diff, e.g. `origin/main`. Implies `changed`. |
| `dialect` | postgres | `postgres`, `mysql`, `oracle` or `mssql`. Empty uses `default_dialect` from `.vericto.toml`, else postgres. |
| `baseline` | | Baseline file to apply (as written by `vericto baseline`, by default `.vericto-baseline.json`). Falls back to `.vericto.toml`. |
| `format` | `sarif` | `sarif`, `json`, `text`, `gitlab-codequality` or `gitlab-sast`. |
| `upload-sarif` | `true` | Upload the SARIF report to Code Scanning (only with `format: sarif`). |
| `api-url` | CLI default | Vericto API base URL (`https://api.vericto.com`). |
| `timeout` | CLI default (30) | Per-request timeout, in seconds. |
| `cli-version` | `1.7.1` | Vericto CLI release to install. Pinned per action release; `latest` is rejected. |
| `working-directory` | `.` | Where the check runs (where `.vericto.toml` lives). With `changed`, it must be the root of the checkout. |

`fail_on` (which severity fails the run) is read from `.vericto.toml`; the
default is to fail only on BLOCKED findings. See the
[CLI's project config](https://github.com/vericto/vericto-cli#project-config-verictotoml).

## Outputs

| Output | Description |
|---|---|
| `exit-code` | The CLI's exit code (table below). |
| `result` | `pass`, `warn` (passed, with findings that don't fail the run) or `fail`. |
| `sarif-file` | Path to the SARIF report; empty if none was written. |
| `report-file` | Path to the report for any machine format; empty for `text`. |
| `blocked`, `flagged`, `monitored`, `parse-errors` | Finding counts, for the `sarif` and `json` formats. |

| Exit code | Meaning |
|---|---|
| `0` | Nothing at or above `fail_on`. |
| `1` | A finding at or above `fail_on`. |
| `2` | Usage error: bad input, unreadable file, no base ref for `changed`. |
| `3` | Authentication or plan error: missing or invalid key, OIDC not configured, plan not entitled, monthly allowance used up. |
| `4` | Backend or network error, including a workspace config that can't be read. No verdict, and no SQL is sent in that case. |

A non-zero code fails the step, and the job with it, unless you set
`continue-on-error: true` and decide from `exit-code`.

## Permissions

| Permission | Why |
|---|---|
| `contents: read` | Check out the code. |
| `security-events: write` | Upload SARIF to Code Scanning (`upload-sarif: true`). |
| `actions: read` | Required by the SARIF upload in private repositories. |
| `id-token: write` | OIDC only. |

Code Scanning is available on public repositories, and on private ones with
GitHub Advanced Security (GitHub Code Security). Without it, set
`upload-sarif: false`: the check, the log and the job summary still work.

## Examples

### Changed SQL on pull requests and on main

```yaml
on:
  pull_request:
    paths: ["**/*.sql"]
  push:
    branches: [main]
    paths: ["**/*.sql"]
# ...
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - uses: vericto/check-sql@v1
        with:
          api-key: ${{ secrets.VERICTO_API_KEY }}
          dialect: mysql
```

### Explicit files

```yaml
      - uses: vericto/check-sql@v1
        with:
          api-key: ${{ secrets.VERICTO_API_KEY }}
          files: |
            db/migrations/**/*.sql
            reports/monthly.sql
```

`fetch-depth: 0` is not needed when you list files. A pattern that matches no
SQL file fails with exit code 2, so a typo can't turn into a silent pass.

### Adopting Vericto in a repo with existing findings

Record today's findings once, commit the baseline, and only new findings fail:

```bash
vericto baseline db/migrations/*.sql   # writes .vericto-baseline.json
git add .vericto-baseline.json
```

```yaml
      - uses: vericto/check-sql@v1
        with:
          api-key: ${{ secrets.VERICTO_API_KEY }}
          baseline: .vericto-baseline.json
```

Baselined findings are still reported (`result: warn`); they just don't fail
the run. A single statement can also be suppressed inline with
`-- vericto:ignore[VERICTO-001] reason`.

### A subdirectory in a monorepo

```yaml
      - uses: vericto/check-sql@v1
        with:
          api-key: ${{ secrets.VERICTO_API_KEY }}
          working-directory: services/billing
          files: migrations
```

Report paths are rewritten relative to the repository root, so annotations
land on the right files.

### Report only, without failing the build

```yaml
      - id: vericto
        uses: vericto/check-sql@v1
        continue-on-error: true
        with:
          api-key: ${{ secrets.VERICTO_API_KEY }}
      - if: steps.vericto.outputs.result != 'pass'
        run: echo "Vericto: ${{ steps.vericto.outputs.blocked }} blocked, ${{ steps.vericto.outputs.flagged }} flagged"
```

### GitLab and other CI systems

This action is for GitHub Actions. On GitLab CI, run the CLI directly with
`--format gitlab-codequality`; the [CLI README](https://github.com/vericto/vericto-cli#cicd)
has a ready-made job.

## Changed files

With `changed` (the default when `files` is empty), the CLI checks the `*.sql`
files that differ from a base, excluding deleted files. The base is:

1. `since`, when set;
2. on `pull_request`, the PR's base branch (`origin/<base>`);
3. on `merge_group`, the queue's base commit;
4. on `push`, the commit before the push;
5. otherwise, the repository's default branch (`origin/<default>`).

The diff needs the base commit, so check out with `fetch-depth: 0`. When no SQL
changed, the check passes and no SQL is sent.

## Troubleshooting

- **`could not determine a base ref` or `git diff ... failed` (exit 2):** the
  checkout is shallow or lacks the base branch. Use `fetch-depth: 0`, or set
  `since`.
- **`changed must run from the root of the git checkout`:** git reports changed
  paths from the repository root. Run from the root, or list `files`.
- **Exit 3:** the key is missing, invalid or lacks `ci_dryrun:execute`; the
  OIDC trust policy doesn't match the repository; or the plan's monthly CLI
  allowance is used up. `vericto doctor` shows which.
- **`oidc: true needs 'permissions: id-token: write'`:** add the permission to
  the job. Pull requests from forks don't get OIDC tokens or secrets.
- **Exit 4:** the API could not be reached, or the workspace config could not
  be read. Corporate TLS proxies: set `VERICTO_CA_BUNDLE` (a PEM path) in the
  job's `env`.
- **SARIF upload fails with "Advanced Security must be enabled" or "Resource
  not accessible by integration":** Code Scanning is not available on this
  repository, or the job lacks `security-events: write` (fork PRs never have
  it). Set `upload-sarif: false` there.

## Security

- **Checksum verification.** The CLI is downloaded from the
  [vericto-cli](https://github.com/vericto/vericto-cli/releases) release that
  `cli-version` pins, never from `latest`. Its SHA-256 is verified against the
  release's `.sha256` file before the archive is extracted; a mismatch stops
  the action. A cached download is re-verified on every run, and the binary on
  `PATH` is always extracted from the verified archive.
- **Build attestation (advisory).** When the GitHub CLI is available, the
  action also runs `gh attestation verify` against the release's Sigstore
  build provenance. If that can't run (no `gh`, no network to the attestation
  API) or doesn't pass, the action logs a warning and continues: the checksum
  is the gate.
- **No secrets on the command line.** The API key reaches the CLI only through
  the `VERICTO_API_KEY` environment variable, is masked in the log, and the CLI
  never prints it. Pass it from `secrets.*` so the runner masks it from the
  start.
- **No shell injection.** No input is interpolated into a script: each one is
  passed through an environment variable, validated, and handed to the CLI as a
  single argument.
- **Pinned dependencies.** Every action this action uses is pinned by commit
  SHA. You can pin this action the same way:
  `uses: vericto/check-sql@<full commit SHA> # v1.0.0`.

Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## SQL never leaves your CI unless it is selected for the check

The CLI is a thin client: it evaluates nothing locally, so checking SQL means
sending it to your Vericto workspace. What is sent, per the
[CLI design](https://github.com/vericto/vericto-cli/blob/main/DESIGN.md):

- **Only the files selected for the check** (the changed `*.sql` files, or
  `files`) and their paths, to your workspace's API only, over TLS
  (`https://api.vericto.com` unless you set `api-url`). No other file in the
  repository is sent.
- **Sanitized when your workspace says so.** Before sending any SQL, the CLI
  reads the workspace's telemetry mode. In `sanitized` mode it replaces literal
  values with placeholders (`$1`, `$2`, ...) on the runner, so raw values never
  leave it. Sanitization is a workspace setting, not a per-run flag.
- **Fail closed.** If the workspace config can't be read, the CLI sends no SQL
  and exits with code 4.
- **Run metadata** for the audit trail: commit SHA, ref, CI provider, run URL
  and the actor's username. Never a credential.
- **Not kept by the CLI.** It does not persist the SQL beyond the request. The
  report it writes can quote short previews and suggested fixes, so treat it
  like the SQL itself.

See [Telemetry & privacy](https://vericto.com/docs/telemetry-privacy).

## Links

- [vericto.com](https://vericto.com)
- [Documentation](https://vericto.com/docs)
- [Vericto CLI](https://github.com/vericto/vericto-cli)
- [Changelog](CHANGELOG.md)

## Versioning

Releases follow [Semantic Versioning](https://semver.org). The major tag
(`v1`) moves to each compatible release, the usual convention for GitHub
Actions; `@v1.0.0` or a commit SHA stays fixed. Each action release pins a
CLI version, and a CLI bump ships as a new action release.

## Tests

The scripts in `scripts/` have offline unit tests (bash 3.2+, `git` and `jq`),
run in CI on Linux and macOS:

```bash
for t in lib resolve verify-checksum install check; do bash "test/$t-test.sh"; done
```

They use local fixtures only: `test/install-test.sh` serves the release
download from `file://` through a `curl` stand-in, and `test/check-test.sh`
runs `check.sh` against a stand-in CLI (`test/fixtures/fake-cli/vericto`). A
case marked `xfail` is a known bug, kept visible until it is fixed.
`test/checksum-test.sh VERSION` checks the same gate against the real release
asset and needs the network.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the checks CI runs, the rules for the
scripts, and how releases are cut.

## License

[Elastic License 2.0](LICENSE) (SPDX `Elastic-2.0`), the same license as the
Vericto CLI, engine and proxy.

---

## En español

**Vericto SQL Check** es una GitHub Action que valida el SQL de sus pull
requests (migraciones, scripts, consultas generadas) contra las reglas de su
espacio de trabajo de [Vericto](https://vericto.com) antes de que se ejecute.
Los hallazgos aparecen como anotaciones de Code Scanning en el PR y una
sentencia bloqueada hace fallar el job.

Uso básico, con una clave de API guardada en el secreto `VERICTO_API_KEY`:

```yaml
permissions:
  contents: read
  security-events: write
  actions: read
steps:
  - uses: actions/checkout@v7
    with:
      fetch-depth: 0
  - uses: vericto/check-sql@v1
    with:
      api-key: ${{ secrets.VERICTO_API_KEY }}
```

- Por defecto se revisan solo los archivos `*.sql` que cambian en el PR. Para
  revisar archivos concretos, indíquelos en `files`.
- Para no guardar una clave, use OIDC: `oidc: true`, `workspace: ws_...` y el
  permiso `id-token: write`.
- La acción descarga una versión fija del CLI y verifica su SHA-256 antes de
  extraerlo. La clave de API se pasa solo por variable de entorno y nunca
  aparece en la línea de comandos.
- El SQL seleccionado se envía a su espacio de trabajo para evaluarlo. Si el
  espacio está en modo `sanitized`, los valores literales se reemplazan en el
  runner antes del envío.

La documentación completa está en inglés, más arriba, y en
[vericto.com/docs](https://vericto.com/docs).
