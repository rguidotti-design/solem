{ config, pkgs, lib, ... }:

# CONFIGURAZIONE MINIMALE VM — ULTRA-MINIMAL per debug CI.
# Solo solem-core (step 0).

{
  imports = [
    ./modules/solem-core.nix
    ./modules/solem-cli.nix
    ./modules/solem-motd.nix
    ./modules/solem-public-apis.nix
    ./modules/solem-demo.nix    # riaggiunto: gum rimosso, solo echo
    ./modules/solem-quick-search.nix  # fd + rg + fzf
    ./modules/solem-clipboard-share.nix  # solem-clip HTTP share
    ./modules/solem-productivity.nix     # solem-pomo + solem-todo + solem-note
    ./modules/solem-smart-install.nix    # solem-app store unificato
    ./modules/solem-migrate-windows.nix  # migrazione NTFS Windows
    ./modules/solem-snap-layouts.nix     # Hyprland binds Win-style
    ./modules/solem-hw-just-works.nix    # sane defaults HW (opt-in default false)
    ./modules/solem-davinci.nix          # DaVinci Resolve helper
    ./modules/solem-wine-office-photoshop.nix  # Office/Photoshop wine preset
    ./modules/solem-steam-deck.nix       # gaming Steam Deck-like
    ./modules/solem-dictation-live.nix   # speech-to-text whisper.cpp
    ./modules/solem-cloud-auto-pair.nix  # solem-cloud QR pair Nextcloud
    ./modules/solem-ai-shortcuts.nix     # Super+T/M/W/D/R/G quick AI actions
    ./modules/solem-quick-look.nix       # preview file spacebar-like
    ./modules/solem-mission-control.nix  # Super+Tab overview
    ./modules/solem-continuity-camera.nix  # Android phone webcam
    ./modules/solem-airplay-auto.nix     # AirPlay receiver auto
    ./modules/solem-photos-memories.nix  # digiKam face recognition
    ./modules/solem-clipboard-mesh.nix   # universal clipboard auto-push P2P
    ./modules/solem-family-gui.nix       # zenity GUI family sharing
    ./modules/solem-cloud-sync.nix       # rclone 70+ provider
    ./modules/solem-dark-mode.nix        # toggle dark/light system-wide
    ./modules/solem-print-pdf.nix        # stampante virtuale PDF (CUPS-PDF)
    ./modules/solem-net-monitor.nix      # solem-net CLI bandwidth/speed/dns
    ./modules/solem-disk-health.nix      # solem-disk SMART monitoring
    ./modules/solem-calendar-sync.nix    # solem-cal CalDAV khal+vdirsyncer
    ./modules/solem-live-caption.nix     # solem-caption STT live mic
    ./modules/solem-battery-predict.nix  # solem-battery-predict + alert
    ./modules/solem-wifi-captive.nix     # solem-wifi-captive portal detect
    ./modules/solem-update-notifier.nix  # solem-update-check + notify-send
    ./modules/solem-ai-guardrails.nix    # 🔒 sandbox AI + kill switch
    ./modules/solem-workload-detect.nix  # profilo OS auto-adattivo
    ./modules/solem-anti-malware.nix     # 🛡️ ClamAV + AIDE + rkhunter + chkrootkit
    ./modules/solem-process-sentinel.nix # 👁️ rule-based anomaly detector
    ./modules/solem-vault.nix            # 🔐 secret manager age-encrypted
    ./modules/solem-encrypted-memory.nix # 🧠 zram cifrato + tmpfs /tmp
    ./modules/solem-net-audit.nix        # 📡 log ogni connect outbound
    ./modules/solem-download-scanner.nix # 🦠 ClamAV auto-scan download
    ./modules/solem-ai-user.nix          # 👥 gavio-ai utente isolato (UID 970)
  ];

  # Identità
  networking.hostName = "solem-vm";
  system.stateVersion = "24.11";
  networking.networkmanager.enable = true;

  # Tool base
  environment.systemPackages = with pkgs; [
    git curl vim
    htop
    python312
  ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };

  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "it_IT.UTF-8";
  i18n.supportedLocales = [
    "it_IT.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];
  console.keyMap = "it";
}
