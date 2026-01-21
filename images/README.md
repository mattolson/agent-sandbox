GPT-5.1:

By doing:

```dockerfile
ARG YQ_VERSION=v4.44.1
RUN mise use --global yq@$YQ_VERSION
```

you’ve effectively:

- Installed `mise` system-wide via APT (so `/usr/bin/mise` is available to any user and non-interactive scripts).
- Set a **global** `yq` version, so `mise x -- yq ...` works:
  - in your `init-firewall.sh` (run via `sudo` / as root),
  - and in interactive shells for your `dev` user.

You now have a single canonical `yq` managed by `mise`, used everywhere.

If you want to cement this pattern for other tools, you can repeat it:

```dockerfile
RUN mise use --global yq@$YQ_VERSION \
    && mise use --global node@lts \
    && mise use --global python@3.12
```

and always call them in scripts via `mise x -- <tool> ...` to ensure consistent versions.
