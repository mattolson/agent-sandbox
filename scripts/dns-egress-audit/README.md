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

H1 carries a positive control. During the capture a throwaway container resolves a separate `ctl-` label through
Docker's embedded resolver, which forwards it out through the VM. H1 reads `not-seen` only when the capture shows
the control and not the run's label, and `error` when it shows neither, since an empty capture proves nothing.

## The upstream rows (C1, C2)

C1 and C2 send raw queries to the embedded resolver's upstream. Docker names it in the `ExtServers` comment of
the `resolv.conf` it writes, but since m18.2 the firewall rewrites the agent's copy, so the runner reads the
comment from a throwaway container on the sandbox network and passes `--upstream` to `probe.bash`. Pass
`--upstream ADDR` to either script to override it; without it, `probe.bash` alone reports `error` for both rows.

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
agentbox compose restart proxy
scripts/dns-egress-audit/run-audit.bash --stage baseline --policy-probes --skip-vm
git checkout .agent-sandbox/policy/user.policy.yaml
agentbox compose restart proxy
```

Restart rather than reload. The proxy mounts the policy file as a single-file bind mount, and an editor or
`git checkout` that replaces the file leaves the container attached to the old inode; a reload re-renders the stale
content and still reports `applied`. A restart re-establishes the mount from the path.

D2 shows that DNS-over-HTTPS to an allowed host is open by design. D3 and D4 show that an allowed name resolving
into the sandbox's own bridge network or the proxy's loopback is connected today; m18.4 must refuse both.

If D2 still reads `proxy-403`, the proxy is not seeing the entries. `agentbox compose logs proxy | grep
'"type": "reload"'` shows the host count each render produced; if it does not grow, the mount is stale. The
three probes run inside the container, so once the entries are live they can also be taken from a sandbox shell
with `probe.bash --policy-probes --only D2,D3,D4`.

## Devcontainer mode

Open the repo as a devcontainer in VS Code, find the container id with `docker ps`, and pass it:

```bash
scripts/dns-egress-audit/run-audit.bash --stage baseline --container <id>
```

The same expected file applies. Both modes must produce the same rows.

## Later stages

`--stage after-m18.2`, `after-m18.3`, and `after-m18.4` pick the matching expected file. Each file's header says
which rows must differ from baseline. The implementing task may change a value, but not undo a flip.

## IPv6 for the after-m18.3 run

The E rows can only flip when the compose network has IPv6, which Docker leaves off by default. Enable it in
`.agent-sandbox/compose/user.override.yml`, which both modes share:

```yaml
networks:
  default:
    enable_ipv6: true
```

Docker Engine 27 and later assigns a unique-local `/64` when no subnet is given; this repo's Colima runs 29.2.1.
An older daemon needs an `ipam` block with a subnet under `fd00::/8`. Compose does not change an existing network
in place, so run `agentbox down` before `agentbox up`. With IPv6 on, `--stage after-m18.3` expects E1 `present`
and E2 through E4 `rejected`; with it off, `--stage after-m18.2` is the file to use. This repo keeps the override
in place so development exercises the IPv6 rules every day.
