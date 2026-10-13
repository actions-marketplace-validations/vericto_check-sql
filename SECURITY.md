# Security Policy

Vericto is a security product. We take vulnerabilities seriously and
appreciate responsible disclosure.

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report it privately, by either channel:

- Email **security@vericto.com**.
- Open a private report on GitHub:
  [Report a vulnerability](https://github.com/vericto/check-sql/security/advisories/new)
  (Security tab, "Report a vulnerability"). Only the maintainers can see it.

Include:

- A description of the vulnerability and its impact.
- Steps to reproduce, ideally a minimal workflow.
- The action version (`vericto/check-sql@...`) and the runner OS.
- Any suggested remediation.

You will receive an acknowledgement within **48 hours** and a status update
within **5 business days**.

## Scope

High-priority issues for this action include:

- **Credential exposure**: the API key or an OIDC token printed in a log,
  placed on a command line, or sent anywhere other than the configured Vericto
  API.
- **Injection**: an input, a file name or a branch name that makes the action
  run code or forge step outputs or workflow commands.
- **Supply chain**: a way to make the action install or run a binary other than
  the one the pinned vericto-cli release published, or to skip its SHA-256
  check.
- **Gate bypass**: a path where the action reports success for SQL the CLI did
  not evaluate.

Issues in the CLI itself belong to
[vericto-cli](https://github.com/vericto/vericto-cli/security), and issues in
the SQL evaluation to
[vericto-engine](https://github.com/vericto/vericto-engine/security).

## How the action protects you

See [Security](README.md#security) in the README: checksum verification before
extraction, advisory build attestation, secrets only in the environment, and
every dependency pinned by commit SHA.

## Disclosure process

1. Report received and acknowledged (within 48h).
2. We confirm and assess severity.
3. We develop and test a fix.
4. We release the fix, move the major tag, and credit you (unless you prefer to
   remain anonymous).
5. Public disclosure after users have had reasonable time to update.

## Supported versions

Security fixes are released for the latest `v1.x.y` and the `v1` tag moves to
it. Older releases are patched at the maintainers' discretion.
