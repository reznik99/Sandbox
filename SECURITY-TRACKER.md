# Personal Dev Security Posture — Tracker

**Current score: 95 / 100**
Last updated: 2026-05-14

## In place

| Layer | Defense | Threat addressed |
| --- | --- | --- |
| **Container isolation** | Rootless podman with `--userns=keep-id` | Container escape → host pivot |
| | `--cap-drop=ALL` | Linux capability abuse |
| | `--security-opt=no-new-privileges` | setuid privilege escalation |
| | `--pids-limit=512`, `--memory`, `--cpus` | Resource exhaustion / fork bombs |
| | 3-profile split (`sandbox` / `sandbox-code` / `sandbox-dev`) | Blast-radius minimisation by use-case |
| | `sandbox-claude` volume only in `sandbox-code` | Claude token exfil from dev-server runs |
| | `~/.claude.json` symlinked into the same volume | Full auth persistence across nuke/rebuild |
| **Supply chain (npm)** | `NPM_CONFIG_MIN_RELEASE_AGE=2` inside sandbox | Fast-burn worms (Shai-Hulud class) |
| | `min-release-age=2` on host `~/.npmrc` | Same, for host npm invocations |
| | npm self-upgraded ≥ 11.10.0 in image | Enables the cooldown setting |
| | `NPM_CONFIG_PREFIX=~/.local` in sandbox | `npm install -g` works rootless |
| | npm passkey (YubiKey, FIDO2) | Phishing-resistant account auth |
| | npm `auth-and-writes` 2FA via passkey | Required on every publish |
| **Supply chain (Go)** | `GOSUMDB=sum.golang.org` default | Module checksum tampering |
| **Identity / commits** | PGP commit signing (YubiKey, physical touch) | Imposter commits from compromised local git |
| | SSH key with passphrase | Key-at-rest theft mitigation |
| | GitHub passkey (YubiKey, FIDO2) | Phishing-resistant account auth |
| **Host hardening** | SELinux enforcing (Fedora) | Mandatory access control |
| | OpenSnitch outbound filter (Fedora) | Network exfiltration alerts |
| | `git config --global core.hooksPath /dev/null` | Sandbox-to-host bypass via `.git/hooks/` |
| | `ForwardAgent no` default in `~/.ssh/config` | SSH agent abuse from remote hosts |
| | Secrets in macOS Keychain / GNOME keyring (not dotfiles) | Filesystem credential sweeps |
| **Operational** | Code review before `git push` | Source-tampering catch-net |
| | Sandboxed `npm install`, `go get`, builds, tests | Dep code never runs with host creds |

## Remaining work

| # | Defense | Threat | Effort | Impact | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Lockfile diff review discipline | Indirect-dep poisoning via `package-lock.json` / `go.sum` | Low (habit) | +1.5 | ☐ |
| 2 | Pre-install scanning (Socket.dev / `npm audit signatures` in CI) | Content-based detection (typosquats, sketchy install scripts) | Medium | +1 | ☐ |
| 3 | Caruso branch protection: require signed commits | Coworker compromise propagation | Low (ruleset change) | +1 | ☐ |
| 4 | YubiKey FIDO2 PIN | Physical theft of YubiKey | Low (one-time) | +0.5 | ☐ |
| 5 | Migrate SSH to `sk-ed25519` (YubiKey-backed) | SSH key abuse from compromised host session | Medium | +0.5 | ☐ |
| 6 | Periodic `podman image/volume prune` | Disk hygiene, stale artefacts | Low (cron / quarterly) | +0.5 | ☐ |
| **Behavioural** | Don't skip the sandbox "just this once"; never mount `~/.ssh` for convenience; read every YubiKey prompt before touching | All of the above bypassed by laziness | — | residual | ongoing |

## Consciously out of scope

| Idea | Why skipped |
| --- | --- |
| Custom AppArmor / seccomp profile | Marginal gain over `cap-drop=ALL`, high maintenance |
| Distroless / Alpine base | Friction (musl issues, package compatibility) vs minimal security gain |
| Reproducible builds | Enterprise-scale concern |
| Air-gapped Verdaccio/JFrog mirror | Cooldown already provides ~80% of the value |
| Network VLAN / segregation | Home network, diminishing returns over OpenSnitch |
| Browser hardening (uBlock + NoScript + ...) | Different threat model from this exercise |
| Disk-level encryption (FDE) | Assumed already enabled on host |
| Hardware security beyond YubiKey | Out of solo-dev scope |

## Score breakdown

| Category | Score | Max |
| --- | --- | --- |
| Container isolation | 25 | 25 |
| Supply-chain defenses (npm + Go) | 23 | 25 |
| Authentication & identity | 19 | 20 |
| Host hardening | 14 | 15 |
| Operational discipline | 14 | 15 |
| **Total** | **95** | **100** |

**Where the missing 5 points are:**
- ~2 pts: behavioural risk (skip/laziness)
- ~1.5 pts: lockfile review gap
- ~1 pt: pre-install content scanning
- ~0.5 pts: minor hygiene (prune, PIN, sk-ed25519, Caruso ruleset)

The remaining gap is mostly process and habit, not configuration. Diminishing returns from here on.

## Change log

| Date | Change | Score |
| --- | --- | --- |
| 2026-05-14 | Initial tracker created. Baseline includes sandbox, npm cooldown, YubiKey passkeys, PGP signing. | 95 |
