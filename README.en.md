# SOLEM

**SOLEM** is an AI-native operating system based on NixOS, built to host AI as first-class citizens of the system.

> Italian README: [README.md](README.md). Note: SOLEM is **Italian-first**, EN is secondary.

---

## State

- **Version:** 0.1.0-step0
- **Roadmap:** see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Target hardware:** Beelink mini-PC (Step 1)
- **Today:** testable VM, no host impact

---

## Quick start

### Option A — With WSL2 + Nix (recommended)

From PowerShell:

```powershell
.\scripts\solem-launch.ps1
```

VM boots headless in WSL, Edge opens fullscreen at `http://localhost:8001` showing the SOLEM dashboard (your "OS surface").

### Option B — Without Nix on host

1. Download [NixOS minimal ISO](https://nixos.org/download)
2. Create VM (VirtualBox/Hyper-V/QEMU): 4GB RAM, 20GB disk
3. Install NixOS minimal ([manual](https://nixos.org/manual/nixos/stable/#sec-installation))
4. Transfer `solem/` into VM (USB, scp, shared folder)
5. Inside VM: `sudo SOLEM_DIR=/etc/nixos/solem ./scripts/setup-in-vm.sh`
6. Reboot → SOLEM active

Full details: [docs/TESTING.md](docs/TESTING.md).

---

## Architecture

7-layer model:

- **L1** Identity Engine — who each user is
- **L2** Context Engine — where, when, what, active role
- **L3** Event Bus — coordination + audit
- **L4** Capabilities Pool — what SOLEM can do
- **L5** Memory & Knowledge — 3 levels (SOLEM, user, contextual)
- **L6** Interop — email, calendar, IoT, devices
- **L7** Extensions Marketplace — third-party plugins (Step 4+)

Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## Cost: 0 €

SOLEM is 100% free, FOSS, self-hostable. Forever. See [docs/COSTS.md](docs/COSTS.md).

- Software: open source (MIT/BSD/Apache/GPL)
- Services: free tier sufficient (Supabase, Groq, GitHub, Let's Encrypt)
- AI models: open weight only (Llama, Mistral, Qwen, Phi, Gemma)
- Hardware: you buy from your supplier when ready (one-time)
- **No subscriptions ever. No feature gating. No managed paid services.**

---

## Non-negotiable principles

1. **One entity, many windows** — devices are thin clients
2. **Oriented leverage** — Identity guides every AI decision
3. **Adaptive, never prescriptive**
4. **Vibe and precision coexist**
5. **Open collaboration, sealed foundations**
6. **Independence, not isolation** — your data stays yours
7. **Builder-friendly by nature**

---

## Documentation

- [README.md](README.md) — Italian (primary)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 7-layer architecture
- [docs/INSTALL.md](docs/INSTALL.md) — bare-metal install
- [docs/COSTS.md](docs/COSTS.md) — cost transparency
- [docs/HARDENING.md](docs/HARDENING.md) — systemd hardening rationale
- [docs/SECURITY.md](SECURITY.md) — threat model + disclosure
- [docs/adr/](docs/adr/) — 9 architecture decision records
- [STATUS.html](STATUS.html) — open in browser to see live project status
- [ROADMAP.md](ROADMAP.md) — Step 0 → 5+ milestones

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Italian welcome, English welcome, no proprietary deps welcome.

License: see flake.nix and individual module headers. All FOSS-compatible.
