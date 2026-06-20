# Security Policy

Thanks for helping keep SurvivorCore — and the games built on it — safe.

## Reporting a vulnerability

**Please don't report security vulnerabilities through public GitHub issues, discussions, or
pull requests** — a public report discloses the problem before a fix exists, and every game built
on SurvivorCore inherits it.

Instead, report it privately via GitHub's
**[Report a vulnerability](https://github.com/TemujinCalidius/SurvivorCore/security/advisories/new)**
form (the repo's **Security → Advisories → Report a vulnerability**). Only the maintainers can see it.

Please include what you can:

- the affected file(s) / module / version,
- the impact and how it could be exploited (e.g. an exploit a malicious client could run against a
  game that uses the engine),
- steps to reproduce or a proof of concept,
- any suggested fix.

## What happens next

SurvivorCore is small and mostly solo-maintained, so this is best-effort:

1. We aim to **acknowledge** your report within a few days.
2. We confirm the issue and develop a fix **privately**.
3. We **release the fix first**, then publish a **GitHub Security Advisory** (requesting a CVE where
   warranted) and **credit you** — unless you'd prefer to stay anonymous.

We practice **coordinated disclosure**: please give us a reasonable window to ship a fix before
disclosing publicly, so games already running the engine can update first.

## Supported versions

Security fixes ship against the **latest release** only. Keep your game current with the newest
SurvivorCore release — bump the Wally dependency (`temujincalidius/survivorcore`) or re-import the
latest `SurvivorCore.rbxm`.

| Version | Supported |
|---------|-----------|
| Latest release | ✅ |
| Anything older | ❌ — please update |

## Scope

SurvivorCore is an **engine consumed by independent games**, so each game is built and deployed
separately.

- **In scope:** vulnerabilities in the **SurvivorCore engine code in this repository** — anything
  that puts a game built on the engine at risk (e.g. a server-side trust boundary the engine gets
  wrong, or an exploitable default).
- **Out of scope here:** a specific *game's* own code, content, or misconfiguration (including any
  private game built on the engine), and bugs in third-party dependencies or Roblox itself (report
  those upstream — though we're glad to hear about ones that materially affect SurvivorCore).

A game built on SurvivorCore is also only as safe as its own server: **never trust the client** —
validate every `RemoteEvent` / `RemoteFunction` argument server-side, keep secrets and keys out of
client scripts, and run the latest engine release.

## How we handle security internally

Most hardening lands openly as normal issues and PRs, and we run **`selene` + `luau-lsp` static
analysis** in CI plus a daily triage. (Luau isn't supported by GitHub CodeQL, so that static
analysis is our code-scanning equivalent.) Genuinely sensitive, high-severity findings go through
the private advisory process above instead, so a fix is available before any public disclosure.
