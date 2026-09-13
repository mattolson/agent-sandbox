# DNS egress audit

Probes for milestone m18. They measure which DNS channels leave the agent container, and they re-run after each
later task to prove the channel flipped from open to blocked. The matrix that interprets the results lives in
`docs/plan/milestones/m18-dns-egress-controls/bypass-matrix.md`.

Two scripts:

- `probe.bash` runs inside the agent container. It needs only bash, coreutils, iproute2, and curl, and builds DNS
  packets by hand because the images carry no `dig`, `nc`, or `python3`. Run it directly from a sandbox shell to get
  the in-container rows, or pass `--list` to see the probe table.
- `run-audit.bash` runs on the Mac. It starts a throwaway DNS responder on the sandbox's compose network, streams
  `probe.bash` into the agent container, captures DNS traffic inside the Colima VM, collects host-side facts, and
  diffs everything against `expected/<stage>.tsv`.

## Running the host-side audit

Prerequisites on the Mac: `docker`, `agentbox`, and a running sandbox for this repo (`agentbox up`). `colima` is
needed for the VM capture and listener check; without it those rows are skipped. The VM needs `tcpdump`:

```bash
colima ssh -- sudo apt-get update
colima ssh -- sudo apt-get install -y tcpdump
```

Then, from the repo root:

```bash
scripts/dns-egress-audit/run-audit.bash --dry-run          # prints the steps, touches nothing
scripts/dns-egress-audit/run-audit.bash --stage baseline   # the real run, about 40 seconds
```

The runner prints the random label for the run. To also see the query leave the Mac, start this in another
terminal before the probes run, and use `--pause` so the runner waits for you:

```bash
sudo tcpdump -ni "$(route -n get 8.8.8.8 | awk '/interface:/{print $2}')" -l udp port 53 | grep --line-buffered <label>
```

Results land in `results/<stage>-<timestamp>/`: `results.tsv` (every probe), `compare.tsv` (status against the
expected file), the VM capture, the peer responder log, the `dns:` override check, and the firewall dumps taken as
root. Commit the baseline run's directory; later runs are working files.

## Policy probes (D2, D3, D4)

Three probes need hosts the default policy does not allow. Add them to `.agent-sandbox/policy/user.policy.yaml`
under `domains:`, reload, run with `--policy-probes`, then revert and reload again:

```yaml
domains:
  - dns.google
  - proxy
  - localhost
```

```bash
agentbox proxy reload
scripts/dns-egress-audit/run-audit.bash --stage baseline --policy-probes
git checkout .agent-sandbox/policy/user.policy.yaml
agentbox proxy reload
```

D2 shows that DNS-over-HTTPS to an allowed host is open by design. D3 and D4 show that an allowed name resolving
into the sandbox's own bridge network or the proxy's loopback is connected today; m18.4 must refuse both.

If D2 still reads `proxy-403` after the reload, the proxy did not apply the new policy. Check the reload event with
`agentbox compose logs proxy | grep '"type": "reload"'`; an `applied` entry means the entries are live, a
`rejected` entry carries the render error. `agentbox compose restart proxy` re-renders from scratch if the
signal path is not working. The three probes run inside the container, so once the entries are live they can
also be taken from a sandbox shell with `probe.bash --policy-probes --only D2,D3,D4`.

## Devcontainer mode

Open the repo as a devcontainer in VS Code, find the container id with `docker ps`, and pass it:

```bash
scripts/dns-egress-audit/run-audit.bash --stage baseline --container <id>
```

The same expected file applies. Both modes must produce the same rows.

## Later stages

`--stage after-m18.2`, `after-m18.3`, and `after-m18.4` pick the matching expected file. Each file's header says
which rows must differ from baseline. The implementing task may change a value, but not undo a flip.
