# Execution Log: m8.3 - Layered Policy Model

## 2026-03-13 04:31 UTC - Full verification passed

The remaining real-environment verification gap is now closed. After the follow-up compatibility fixes to `cli/lib/composefile.bash` and `cli/lib/cli-compose.bash`, the full `m8.3` test set passed, including the previously blocked real-`yq` regression coverage:

- `cli/test/policy/render.bats`
- `cli/test/edit/policy.bats`
- `cli/test/compose/run-compose.bats`
- `cli/test/init/init.bats`
- `cli/test/init/policy.bats`
- `cli/test/init/regression.bats`
- `cli/test/switch/switch.bats`

This confirms that the layered policy model works in both the shell-only paths and the repository's actual compose-generation environment.

## 2026-03-12 03:18 UTC - Follow-up fix for real `yq` parser compatibility

The first implementation of `ensure_service_volume()` in `cli/lib/composefile.bash` used a jq-style `if ... then ... else ... end` expression directly inside `yq -i`. That passed in the shell-only test environment, but the real repository `yq` parser rejected it with:

`lexer: invalid input text "if ($volumes | i..."`

The fix was to move the duplicate check into shell:

1. query the current volume list length with a simple `map(select(...)) | length` expression
2. return early if the mount already exists
3. otherwise append with the existing simple `add_service_volume()` mutation path

This keeps the behavior the same while avoiding parser-specific control-flow syntax in write expressions.

The same compatibility issue surfaced in `set_service_environment_var()`, where the initial implementation used `startswith(...)` inside a `map(select(...))` write expression. The real parser rejected that as well.

That helper now follows the same approach:

1. read the existing environment array line-by-line with a simple `yq -r`
2. filter conflicting `NAME=` entries in shell
3. reset the YAML array to `[]`
4. append the preserved entries and the new assignment with simple `+= [...]` writes

The working rule for this codebase is now explicit: keep `yq` mutations narrow and push any conditional or string-matching logic into shell.

One more host-side compatibility bug appeared immediately after that change: with `set -u` enabled, Bash 3.2 treats `${empty_array[@]}` as an unbound variable. The first shell rewrite still iterated over `preserved_entries[@]` unconditionally, which broke layered CLI init and any path that ensured active-agent runtime files for a proxy service with no existing environment array.

The fix was to track `preserved_entry_count` explicitly and only iterate when the count is non-zero. I also defaulted the earlier `existing_count` read in `ensure_service_volume()` to `0` so an empty `yq` read cannot silently take the "already present" branch.

The next regression surfaced in the CLI init regression suite rather than the policy helpers: `scaffold_cli_shared_override_if_missing()` was still expanding `${HOME}` for the shell customization mount when it wrote `.agent-sandbox/compose/user.override.yml`. The layered override files are supposed to keep `${HOME}` literal, both for portability and to match the existing compose-generation contract.

That helper now writes the shell customization mount as the literal string:

`'${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro'`

## 2026-03-12 03:05 UTC - Layered policy model implemented

Completed the end-to-end layered CLI policy conversion across CLI scaffolding, runtime Compose behavior, proxy startup, and docs.

Key implementation changes:

1. `cli/lib/cli-compose.bash` now treats `.agent-sandbox/user.policy.yaml` and `.agent-sandbox/user.agent.<agent>.policy.yaml` as the layered CLI policy inputs, upgrades managed base and agent compose layers in place, and migrates interim `policy-cli-<agent>.yaml` files into the new agent-specific user-owned file before renaming the old file to `policy-cli-<agent>.deprecated*.yaml`.
2. `images/proxy/render-policy`, `images/proxy/entrypoint.sh`, and `images/proxy/addons/enforcer.py` now render the effective policy before enforcement and read the rendered path from `POLICY_PATH`, so runtime no longer depends on a single mounted file for layered CLI mode.
3. Added `agentbox policy render` as a new module-backed command that runs the proxy-side render helper through the same Compose stack the runtime uses.
4. `edit policy` now defaults layered CLI repos to the shared user-owned policy file, supports `--agent <name>` for agent-specific edits, and deliberately skips restarting the current proxy when the edited file belongs to an inactive agent.
5. `switch` now treats same-agent layered invocations as a managed-runtime refresh path so current projects have an explicit repair command even when the selected agent does not change.

Verification:

- Passed: `cli/test/policy/render.bats`
- Passed: `cli/test/edit/policy.bats`
- Passed: `cli/test/compose/run-compose.bats`
- Passed: `cli/test/init/init.bats`
- Passed: `cli/test/switch/switch.bats`
- Not run here: the updated `yq`-dependent suites (`cli/test/init/policy.bats`, `cli/test/init/regression.bats`, and composefile-level coverage) because this container still lacks a real `yq` binary

## 2026-03-12 02:06 UTC - Execution started

Execution is proceeding with the approved layered policy naming and the tightened `m8.2` carry-forward behavior:

- use `.agent-sandbox/user.policy.yaml` for shared user-owned additions
- use `.agent-sandbox/user.agent.<agent>.policy.yaml` for agent-specific user-owned additions
- migrate interim `policy-cli-<agent>.yaml` content only into the new agent-specific file
- rename migrated flat files to `policy-cli-<agent>.deprecated.yaml` so they are preserved but no longer look live

The implementation focus is to change the runtime contract first so every caller targets the same merge path:

1. layered CLI compose should mount stable shared and agent-specific user policy inputs into the proxy
2. proxy startup should render the effective policy from the active agent baseline plus those user inputs
3. `agentbox policy render` should invoke that same proxy-side render path instead of re-implementing merge logic in shell

## 2026-03-12 01:40 UTC - Planning complete

Reviewed the `m8` milestone, `docs/plan/learnings.md`, decision `004`, the completed `m8.2` task, the current CLI policy helpers, `edit policy`, the layered CLI compose helpers, and the proxy runtime code in `images/proxy/entrypoint.sh` and `images/proxy/addons/enforcer.py`.

The main planning conclusion is that `m8.3` cannot be treated as a pure YAML merge utility. The current system has three coupled assumptions that all need to change together:

1. layered CLI compose mounts one flat policy file directly into the proxy
2. proxy startup expects exactly one policy file at `/etc/mitmproxy/policy.yaml`
3. `edit policy` still targets `policy-<mode>-<agent>.yaml`

**Issue:** `m8.2` introduced interim `policy-cli-<agent>.yaml` files so switching would work before policy layering landed. If `m8.3` simply ignores those files, current layered CLI customizations can be stranded.
**Solution:** Plan a targeted carry-forward path when scaffolding new layered user-owned policy files: if the new file is missing but the interim flat file exists, compute the delta relative to the managed baseline, seed only the new agent-specific user file, then rename the old flat file to a conspicuous deprecated filename so it can no longer look authoritative.

**Decision:** Keep the real policy merge implementation in the proxy runtime path and have `agentbox policy render` invoke that same implementation rather than duplicating merge logic in shell.

**Decision:** Rename the planned layered user-owned policy files to `.agent-sandbox/user.policy.yaml` and `.agent-sandbox/user.agent.<agent>.policy.yaml` so policy ownership follows the same `user.*` convention as layered compose overrides.

**Decision:** Do not delete `m8.2` flat policy files automatically after carry-forward. Renaming them to something like `policy-cli-<agent>.deprecated.yaml` is safer because it preserves recovery context while making future edits obviously ineffective.

**Learning:** The merge-path reuse requirement is really a dependency-management problem. A host-side shell implementation would be easy to write with `yq`, but it would immediately diverge from proxy runtime unless the proxy image also adopted the same toolchain.
