# SOLEM — draft post per Reddit / Hacker News / r/NixOS

## Per r/NixOS

**Titolo**: `SOLEM — NixOS AI-native OS with 53+ zero-trust security layers (FOSS)`

```
Hi r/NixOS,

I've been working on SOLEM, a NixOS distribution focused on hosting
personal AI (GAVIO) with strict zero-trust isolation.

TL;DR: 53+ declarative security layers, auto red-team nightly,
self-heal, Friday/JARVIS-style unified CLI. All FOSS, 0 €.

Highlights (all in nixos/modules/solem-*.nix):
- solem-ai-user: dedicated UID 970 for AI (gavio-ai)
- solem-ai-network: nftables egress whitelist filtered by UID
- solem-gavio-zero-trust: systemd override (NNP, caps drop, syscall filter)
- solem-canary: honey tokens + auto-kill switch
- solem-kernel-harden + solem-hardened-kernel: sysctl + KSPP
- solem-ai-dns: unbound allowlist anti-DNS-tunneling
- solem-apparmor: MAC profile kernel-enforced
- solem-ai-audit-strict: auditd for UID 970
- solem-self-redteam + solem-self-heal: auto-attack + fix nightly
- solem-tor-onion, solem-wireguard-mesh, solem-local-pki

VM tests 15/15 green. Build: nix build .#vm / .#vm-gnome / .#iso

Repo: https://github.com/rguidotti-design/solem
Honest roadmap: docs/GAPS-VERO-OS.md

Inspired by Iron Man's Friday/JARVIS — SOLEM is the active shell that
contains and protects GAVIO (the AI inside).

Looking for: NixOS testers, module design feedback, ideas to close
the remaining gaps (hardware test, GAVIO packaging, mass-market polish).
```

---

## Per Hacker News (Show HN)

**Titolo**: `Show HN: SOLEM – NixOS-based OS with 53 zero-trust layers for hosting AI`

```
SOLEM is a NixOS distribution I've been building to address: how do
you host a personal AI on your own machine without giving it the keys
to your kingdom?

Answer: 53+ declarative security layers. Highlights:
- AI runs as dedicated UID isolated from human user
- nftables egress whitelist filtered by UID (AI can't phone home)
- AppArmor MAC profile kernel-enforced
- DNS allowlist via unbound (anti-tunneling)
- Honey-token canary files + auto-kill switch on read
- Hardened kernel + sysctl strict + lockdown LSM
- Self red-team attacks the system nightly + auto-applies safe fixes
- Friday/JARVIS-style CLI: solem ai ask "..."

Standard NixOS goodies: reproducibility, rollback-safe generations,
declarative config in flake.nix.

Status (honest): 15/15 VM tests green, ISO builds, GTK theme navy/gold.
Missing: real GAVIO packaging (scaffolding ready), hardware testing
on physical laptops, public CDN for ISO.

Repo + honest roadmap: https://github.com/rguidotti-design/solem

Feedback especially welcome from people who've thought about
"how do I host my own AI assistant without trusting it".
```

---

## Per awesome-nix PR

Aggiungi sotto "Distributions":

```markdown
- [SOLEM](https://github.com/rguidotti-design/solem) - AI-native NixOS
  distribution with 53+ zero-trust security layers for hosting personal
  AI. Auto red-team + self-heal, Friday-style CLI, hardened kernel,
  AppArmor MAC, encrypted backup, Tor onion service.
```

---

## Twitter / X thread

```
1/ SOLEM: OS NixOS pensato per ospitare la tua AI con vero zero-trust.
   53+ layer di sicurezza dichiarativi. Auto red-team notturno.
   Friday/JARVIS-style CLI.
   github.com/rguidotti-design/solem

2/ Problema: vuoi AI sul TUO PC (privacy, no cloud) MA come ti fidi
   che non ti rubi i dati / non telefoni a casa?

   SOLEM: UID isolato + nftables egress + AppArmor MAC + DNS allowlist
   + audit + canary kill switch + ... (12 layer specifici per AI).

3/ Plus host:
   - Kernel hardened + sysctl strict
   - Backup encrypted borg+age+rclone
   - WireGuard mesh / Tor onion remote
   - TPM measured boot + Secure Boot scaffolding
   - PWA mobile companion

4/ Tutto FOSS, 0 €. Build: VM + ISO live + Calamares installer.
   15/15 VM test verdi in CI.

5/ Honest roadmap docs/GAPS-VERO-OS.md
   12-18 mesi UX/polish per mass-market.
   Oggi: pronto per developer/researcher AI-paranoid.

6/ Cerco tester + feedback. RT se interessa.
```

---

## NON pubblicare ancora se

- GitHub Pages non attivo (link landing 404)
- ISO non hostata (utenti download fail)
- README scarno (richiede badges + screenshot + quick-start)

Prima di pubblicare:
1. Attiva GitHub Pages (Settings - Pages - main /docs)
2. Aspetta deploy (2 min)
3. Verifica https://rguidotti-design.github.io/solem/ apre
4. Screenshot reali in docs/screenshots/
5. README con badges CI + quick-start
6. Pubblica
