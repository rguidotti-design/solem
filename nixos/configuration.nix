{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/solem-core.nix
    ./modules/networking.nix
    ./modules/security.nix
    ./modules/ai-freedom.nix
    ./modules/gavio.nix
    ./modules/solem-api.nix
    ./modules/solem-backup.nix
    ./modules/solem-mesh.nix         # opt-in: solem.mesh.enable = true
    ./modules/solem-zero-trust.nix   # opt-in: solem.zeroTrust.enable = true
    ./modules/solem-desktop.nix      # opt-in: solem.desktop.enable = true
    ./modules/solem-boot.nix         # Plymouth splash + quiet boot
    ./modules/solem-secure.nix       # 5 layer sicurezza (opt-in granulare)
    ./modules/solem-creator.nix      # dev/ai/data/creative toolkit (opt-in)
    ./modules/solem-profiles.nix     # preset: minimal/developer/creator/server/desktop
    ./modules/solem-update.nix       # auto-update OTA + rollback (opt-in)
    ./modules/solem-gavio-storage.nix      # /var/lib/gavio strutturato (M1.2)
    ./modules/solem-supabase-backup.nix    # pg_dump Supabase settimanale (ADR-004, opt-in)
    ./modules/solem-voice.nix              # STT (whisper.cpp) + TTS (piper) locali (opt-in)
    # ── Moduli atomici Single Responsibility (Prompt Master v4.0) ───────
    ./modules/solem-double-vpn.nix         # VPN doppia (mesh + tunnel esterno) opt-in
    ./modules/solem-dns-private.nix        # DoT/DoH stubby+unbound opt-in
    ./modules/solem-kernel-hardening.nix   # KSPP boot cmdline + lockdown (default ON)
    ./modules/solem-memory.nix             # zram + earlyoom + oomd (default ON)
    ./modules/solem-sandbox.nix            # bubblewrap+firejail+landlock (default ON)
    ./modules/solem-tpm.nix                # TPM2 measured boot opt-in
    ./modules/solem-usbguard.nix           # USBGuard allowlist opt-in
    ./modules/solem-tor.nix                # Tor client + onion service opt-in
    ./modules/solem-secrets.nix            # sops-nix dichiarativo opt-in
    ./modules/solem-secure-boot.nix        # Lanzaboote opt-in
    ./modules/solem-motd.nix         # banner ASCII + MOTD dinamica al login
    ./modules/solem-cli.nix          # comando `solem` (status/layers/caps/pair)
    ./modules/solem-shell.nix        # TUI `solem-shell` (paradigma AI-as-shell)
    ./modules/solem-doctor.nix       # `solem-doctor` diagnostica completa (30+ check)
    ./modules/solem-keep.nix         # watchdog servizi core + event bus integration
    ./modules/solem-layers.nix
  ];

  # ── PROFILO COMPLETO — "creator" ────────────────────────────────────
  # Sviluppo + AI + data + creative tools tutti abilitati.
  solem.profile = "creator";

  # ── TUTTI I MODULI ATTIVATI ─────────────────────────────────────────
  solem.mesh.enable = true;             # WireGuard mesh (interface up, peers vuoti)
  solem.zeroTrust.enable = true;        # Caddy mTLS proxy + CA bootstrap
  # Desktop attivato MA kiosk disabled (VM headless in WSL2 → dashboard via browser host)
  solem.desktop.enable = true;          # Hyprland + Pipewire + Bluetooth installati (per Beelink Step 1)
  solem.desktop.autoLogin = false;      # No auto-login GUI (headless)
  solem.desktop.kiosk = false;          # No kiosk (browser host = UI)
  solem.update.enable = true;           # Auto-update OTA settimanale + boot rollback
  solem.secure.kernelHardening.enable = true;  # sysctl strict, ASLR, ptrace restrict

  # Stato base — NON cambiare dopo prima install. Lega la release NixOS che
  # ha generato il sistema per garantire compatibilità su upgrade.
  system.stateVersion = "24.11";

  nixpkgs.config.allowUnfree = true;

  # Identità del nodo
  networking.hostName = "solem";
  networking.domain = "local";

  # Italia
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "it_IT.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "it_IT.UTF-8";
    LC_MEASUREMENT = "it_IT.UTF-8";
    LC_TIME = "it_IT.UTF-8";
    LC_NUMERIC = "it_IT.UTF-8";
  };
  console.keyMap = "it";

  # Tool base sempre presenti — disponibili a GAVIO senza venv
  environment.systemPackages = with pkgs; [
    git curl wget vim neovim
    htop btop tmux jq yq
    ripgrep fd bat eza tree
    python312 uv
    openssl gnupg
    unzip zip
  ];
}
