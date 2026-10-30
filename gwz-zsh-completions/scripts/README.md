# Scripts

Maintainer-facing map. The agent contract is `SKILL.md` and `references/`.

Only the top-level scripts are entry points. Everything in `collect/` and
`lib/` is internal; `verify/` scripts are called by `preflight` or by the agent
for a specific level.

| Path | Role | Called by |
| --- | --- | --- |
| `preflight.zsh` | Collect facts and print `decision` / `verification` | agent |
| `self-check.zsh` | Check the skill and the demo fixture | maintainer |
| `collect/fpath.zsh` | `fpath` views, `_cmd` copies, shadowing | `preflight`, `self-check` |
| `collect/help.zsh` | Safe help probing with fallbacks | `preflight`, `self-check` |
| `verify/lint.zsh` | L1 linter: metadata, syntax, bash markers | agent, `self-check` |
| `verify/gate.zsh` | Harness self-test on `tests/fixtures/_demo` | `preflight` |
| `verify/harness.zsh` | L3: real TAB through `zpty` | `verify/gate.zsh`, agent |
| `lib/ansi.zsh` | Shared helpers (`stripAnsi`) | `collect/help.zsh`, `verify/harness.zsh` |

```text
preflight
  ├── collect/fpath.zsh
  ├── collect/help.zsh
  └── verify/gate.zsh
        └── verify/harness.zsh
              └── lib/ansi.zsh

collect/help.zsh ──→ lib/ansi.zsh
self-check ──→ collect/fpath, collect/help, verify/lint, verify/harness
```

Add a script only when it has a single role. Entry points stay at the top
level; helpers go under `lib/`, fact collection under `collect/`, and checks
under `verify/`.
