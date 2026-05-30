# Execution Log: m16.7 - Hermes agent docs, README support matrix, and m16 done-marking

## 2026-05-29 - First-run testing surfaced m16.3 reversal

Built the hermes image and ran it through a first-use flow. Every command that touches config (`chat`, `model`,
`postinstall`, ...) blew up:

```
RuntimeError: /home/dev/.hermes/cron does not exist. Run 'sudo nixos-rebuild switch' first.
```

And `hermes setup` refused with:

```
Cannot run setup wizard: this Hermes installation is managed by AgentSandbox.
Use your package manager to upgrade or reinstall Hermes.
```

After hand-creating `cron`, `sessions`, `memories`, the errors marched forward one missing dir at a time, then
landed on the setup-wizard refusal — no path forward to configure a provider.

**Root cause:** `HERMES_MANAGED=AgentSandbox` is the wrong knob. It also blocks `hermes setup` and demands the
package manager pre-create state dirs with 2770 perms. See the m16.3 execution log addendum for the full
investigation.

**Fix:** replaced `HERMES_MANAGED` in the Dockerfile with a thin shell wrapper at `/usr/local/bin/hermes` that
intercepts `update` and `uninstall` with the same intent (clean message + pointer to `agentbox bump`) but without
the unwanted side effects. Updated `docs/agents/hermes.md`, the milestone scope note, and this task's docs scope
to match. Code+docs changes in flight; rebuild + re-test pending.

This means m16.7 is no longer pure docs — it now carries a small image/Dockerfile change too. The acceptance
criteria are updated accordingly (`hermes update --yes` and `hermes uninstall --yes` both refuse via the wrapper).

## 2026-05-27 - Plan drafted

Closing task for m16. Roughly three buckets of work:

1. **`docs/agents/hermes.md`** — new doc. Pi-as-reference structure plus the Hermes-specific upgrade-path section
   we've been building toward since the m16.3 discussion about `hermes update`. Will be ~120-150 lines (pi.md is
   ~70, but Hermes has more to explain: upgrade path, optional opt-in domains, broader provider list).
2. **README support matrix + mark-done in project plan/roadmap** — three small mechanical edits.
3. **Host-side manual verification** — the only acceptance criterion that can't be verified from inside this
   sandbox. Requires a real provider API key and an actual `agentbox up` cycle. Will hand off as a checklist.

**Provider env-var enumeration decision** (one of the open questions): document the common 4 (Nous Portal,
OpenRouter, OpenAI, Anthropic) in the main flow, plus a short table listing the others (Gemini, Novita, OLLAMA,
Google API). Documenting all 9-ish equally would dilute the common path.

**IDE-extension status decision** (the other open question): `:no_entry_sign:` for both VS Code and JetBrains.
Hermes ships its own TUI (via `ui-tui/`, npm-built) and many platform adapters (Telegram, Discord, etc.), but no
IDE extension. Match the Pi/OpenCode "No IDE extensions available" line in the known-blockers list. If a future
extension surfaces, the matrix can be updated then.

Awaiting approval to execute.
