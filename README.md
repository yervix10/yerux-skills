# yerux-skills

A collection of **Agent Skills** for Claude Code and Codex, plus **agent-bridge**, a tool that lets AI coding sessions from
different accounts and different CLIs talk to each other on one machine. Everything installs with one command, and every
skill follows the same naming scheme and folder layout.

## Install

Linux, macOS, WSL:

    curl -fsSL https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.sh | bash

Windows:

    powershell -c "irm https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.ps1 | iex"

The installer finds your Claude Code and Codex accounts (and Kiro, Antigravity, Cursor, Copilot and OpenCode when present)
and opens a menu: `↑ ↓` move · `space` select · `enter` continue (`r` renames and `+` adds an account on the first page).
Without a terminal it installs agent-bridge into every account it finds.

Options after `bash -s --`:

    --yes                      no menu
    --skills a,b | all | none  extra skills to install (default: none)
    --list | --dry-run | --check [--fix] | --uninstall

On Windows pass the same options with `$env:AGENT_BRIDGE_ARGS='-Yes -Skills all'`. Pin a version with `AGENT_BRIDGE_REF=<tag>`.
From a clone: `./install.sh` (Linux/macOS/WSL) or `.\install.ps1` (Windows).
`--uninstall` removes agent-bridge and the extra skills the installer added; the mailbox `~/.claude-bridge` is kept.

## Mentioning agents

In a Claude Code session, address a worker by name: `@agent-claude-2 run the tests of project X`. The installer creates a small
subagent for every worker (`~/.claude*/agents/<worker>.md`) that only forwards your task with `agent <worker> "..."`.
Type `@agent-<name>` by hand if the typeahead does not list it. Re-run the installer (or update) after adding or renaming an agent.

## Updating

Releases are git tags named `vX.Y.Z`. The installed version is stored in `~/.claude-bridge/version`.

    agent update --check     is there a newer tag? (changes nothing)
    agent update --yes       download that tag and run the installer on it (asks without --yes)

The desktop widget checks when it starts and every 15 minutes (or on demand: tray menu, **Buscar actualizaciones**) and shows an **Actualización disponible** banner; one click (after a confirmation)
runs `agent update --yes` and restarts the widget. Nothing is installed automatically.

## Repository layout

    skills/               every skill, one folder each, named <topic>-<type>
      …                   the other skills (below)
    lib/ui.sh             terminal UI helpers shared by the installers

The featured package **agent-bridge** (scripts, runners, desktop app, Windows port, tests) is a separate project, `yerux-agent-bridge`. The installers find it in `$AGENT_BRIDGE_DIR` or in `../yerux-agent-bridge`; `get.sh` / `get.ps1` download it for you. Without it, the other skills still install.
    install.sh / .ps1     installers (Linux/macOS/WSL, Windows)
    get.sh / .ps1         one-line bootstrap: downloads the repo and runs the installer
    .github/workflows/    CI: shell and PowerShell syntax, security and feed tests on Linux and macOS

## Skills

| Skill | What it gives you |
|---|---|
| **agent-bridge** | `/admin`, `/agent`, `/dashboard`: one session orchestrates headless workers (Claude, Codex, Kiro, Antigravity, Cursor, Copilot, OpenCode) through a file mailbox. Per-worker git worktrees, usage-aware work assignment, live dashboard and desktop widget. See [skills/agent-bridge/README.md](skills/agent-bridge/README.md). |
| **astro-best-practices** | Production Astro 7 sites: static by default, `.astro` before framework components, typed content collections, SEO generated from the content schema, TailwindCSS v4. |
| **html-best-practices** | Framework-agnostic semantic HTML, landmarks, headings, content elements and the TailwindCSS v4 theme. |
| **react-core-best-practices** | React on any platform: effects and state, derived values, list identity, typed React Query layer, composition, typing. |
| **react-best-practices** | React on the web: forms with react-hook-form and shadcn/ui, and the shadcn/ui generator contract. |
| **react-native-with-expo-best-practices** | React Native with Expo: NativeWind, Expo Router layout, native config through `app.json` plugins. |
| **django-rest-framework-best-practices** | Django and DRF: ORM efficiency, serialization strategy, API security. |
| **git-best-practices** | Conventional Commits, Conventional Branch naming (with an agent-authored prefix) and a `/commit` command. |
| **project-review** | Code review of a commit or path against the standards the project already declares, loading the matching best-practices skills. |
| **deployment-workflow** | Security-first deployment over SSH: per-repo deploy keys, Docker Compose behind a shared Caddy proxy. |
| **design-system-factory** | Create, extend and audit a brand design system: tokens, assets, components, print stationery, governance. |
| **color-palette** | 11-shade Tailwind-style palettes from hex codes, as a Figma-ready variables JSON with RGB, CMYK and HSL values. |
| **neovim-audit** | Reads and updates the Neovim `audit` plugin's per-project file review state and refuses to touch files marked done. |
| **skill-factory** | Guide and templates for writing new skills in this collection. |

## Conventions

- **Names** are kebab-case and always `<topic>-<type>` (`git-best-practices`, `color-palette`, `neovim-audit`); the folder name equals the `name:` in `SKILL.md`.
- **Tiers** (see `skills/skill-factory`): a one-file procedure, a skill with `metadata.json`, `README.md` and `scripts/`, or a rule catalog with `rules/` and a compiled `AGENTS.md`. Pick the smallest tier that fits.
- **Every skill** has a `SKILL.md` with `name` and `description` front matter; the installer lists whatever it finds under `skills/`.

## Adding a skill

Create `skills/<topic>-<type>/` following `skills/skill-factory`, then run `./install.sh --list` to confirm it shows up.

## Tests and CI

    ./install.sh --dry-run --yes --skills none   # installer smoke test (agent-bridge's own tests live in yerux-agent-bridge)

GitHub Actions checks the syntax of the installer scripts and runs the installer dry-run.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
