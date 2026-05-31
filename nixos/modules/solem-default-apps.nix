{ config, pkgs, lib, ... }:

# SOLEM DEFAULT APPS — Step 40: preset apps user-facing curato.
#
# Single responsibility: SOLO selezione + install di app default coerenti
# con filosofia SOLEM (FOSS, leggere, privacy-respecting). Non configura
# desktop env (vedi solem-desktop), non installa server (vedi solem-monitoring).
#
# Filosofia scelte:
#   - Browser: Firefox + LibreWolf opzionale (no Chrome telemetria)
#   - File manager: nnn (TUI veloce) + Nautilus (GUI default Hyprland)
#   - Editor: Kate (GUI feature-rich) + Helix (TUI modern)
#   - Office: LibreOffice (default) + OnlyOffice opzionale
#   - Media: mpv (player), Audacity (audio editor), GIMP (image), Krita (paint)
#   - PDF: zathura (vim-style) + Okular (feature-rich)
#   - Email: Thunderbird
#   - Calendar: GNOME Calendar (semplice) + khal CLI (sync CalDAV)
#   - Notes: Obsidian opzionale (proprietario MA molto usato) o Logseq (FOSS)
#   - Messaging: Signal Desktop + Element (Matrix)
#
# Default: insieme MINIMO (browser + files + editor + media base).
# Opt-in: full bundle (~3GB) con tutto.

let
  cfg = config.solem.defaultApps;
in {
  options.solem.defaultApps = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa preset apps user-facing SOLEM";
    };

    profile = lib.mkOption {
      type = lib.types.enum [ "minimal" "office" "media" "developer" "full" ];
      default = "minimal";
      description = ''
        Profilo apps:
          - minimal: browser + files + editor + media base (~500MB)
          - office:  minimal + LibreOffice + Thunderbird (~1.5GB)
          - media:   minimal + GIMP + Krita + Audacity + Inkscape (~2GB)
          - developer: minimal + VSCode + Docker + langservers (~2.5GB)
          - full:    tutto (~5GB)
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs;
      let
        minimalSet = [
          firefox            # browser default
          nautilus           # file manager GUI
          nnn                # file manager TUI
          kate               # editor GUI feature-rich
          helix              # editor TUI modal modern
          mpv                # video player
          zathura            # PDF viewer (vim-style)
          alacritty          # terminal default
          chromium           # secondario per testing
          imv                # image viewer veloce
        ];
        officeSet = [
          libreoffice-fresh  # suite office completa
          thunderbird        # email
          gnome-calendar     # calendar GUI
          khal               # calendar CLI CalDAV
          vdirsyncer         # sync CalDAV/CardDAV
        ];
        mediaSet = [
          gimp               # image editor pro
          krita              # painting
          inkscape           # vector graphics
          audacity           # audio editor
          obs-studio         # screen recording / streaming
          handbrake          # video transcoder
          shotcut            # video editor
        ];
        developerSet = [
          vscodium           # VSCode senza telemetria MS
          gh                 # GitHub CLI
          lazygit            # git TUI
          tmux               # terminal multiplexer
          ripgrep
          fd
          fzf
          bat
          eza
          delta              # git diff bello
          jq yq
          httpie
          dive               # docker image explorer
          k9s                # kubernetes TUI
          # Languages essenziali
          nodejs_20
          python3
          go
          rustc cargo
        ];
        messagingSet = [
          signal-desktop
          element-desktop
        ];
      in
        minimalSet
        ++ lib.optionals (cfg.profile == "office" || cfg.profile == "full") officeSet
        ++ lib.optionals (cfg.profile == "media" || cfg.profile == "full") mediaSet
        ++ lib.optionals (cfg.profile == "developer" || cfg.profile == "full") developerSet
        ++ lib.optionals (cfg.profile == "full") messagingSet;

    # XDG default applications (MIME associations)
    xdg.mime.defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "application/pdf" = "org.pwmt.zathura.desktop";
      "image/png" = "imv.desktop";
      "image/jpeg" = "imv.desktop";
      "image/svg+xml" = "imv.desktop";
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "audio/mpeg" = "mpv.desktop";
      "inode/directory" = "org.gnome.Nautilus.desktop";
      "text/plain" = "org.kde.kate.desktop";
    };

    # Firefox config: privacy default
    programs.firefox = {
      enable = true;
      policies = {
        DisableTelemetry = true;
        DisablePocket = true;
        DisableFirefoxStudies = true;
        DisableFirefoxAccounts = false;  # user choice
        DontCheckDefaultBrowser = true;
        EnableTrackingProtection = {
          Value = true;
          Locked = false;
          Cryptomining = true;
          Fingerprinting = true;
        };
        PasswordManagerEnabled = true;
        DisableFormHistory = false;
        FirefoxSuggest = {
          WebSuggestions = false;
          SponsoredSuggestions = false;
        };
        SearchEngines.PreventInstalls = false;
        Homepage = {
          URL = "https://duckduckgo.com";
          StartPage = "homepage";
        };
      };
    };

    environment.etc."solem/default-apps.md".text = ''
      # SOLEM Default Apps (Step 40)

      Preset user-facing app curato FOSS/privacy-respecting.

      ## Profilo corrente: ${cfg.profile}

      ### Sempre installati (minimal)
      - **firefox**: browser default privacy-hardened (telemetry off)
      - **chromium**: secondario per testing
      - **nautilus**: file manager GUI (default Hyprland)
      - **nnn**: file manager TUI super veloce
      - **kate**: editor GUI feature-rich
      - **helix**: editor TUI modal moderno
      - **alacritty**: terminale default
      - **mpv**: video player
      - **zathura**: PDF viewer (vim-style)
      - **imv**: image viewer veloce

      ### Profile "office" aggiunge
      - LibreOffice (suite completa)
      - Thunderbird (email)
      - GNOME Calendar + khal CLI + vdirsyncer

      ### Profile "media" aggiunge
      - GIMP, Krita, Inkscape, Audacity, OBS, Handbrake, Shotcut

      ### Profile "developer" aggiunge
      - VSCodium (no MS telemetry), gh, lazygit, tmux
      - ripgrep, fd, fzf, bat, eza, delta, jq, yq, httpie
      - Languages: nodejs, python, go, rust

      ### Profile "full"
      Tutti i set sopra + messaging (Signal Desktop, Element/Matrix)

      ## XDG defaults
      Mime associations sane (Firefox per HTTP, zathura per PDF, mpv per
      video, ...) impostati globalmente.

      ## Firefox policies (privacy-first)
      - Telemetry: OFF
      - Pocket: OFF
      - Firefox Studies: OFF
      - Tracking Protection: ON (crypto + fingerprint)
      - Homepage: DuckDuckGo

      ## Selezione del profilo
      ```nix
      solem.defaultApps.profile = "developer";  # o "office" / "media" / "full"
      ```

      ## Disabilitare alcuni package specifici
      Override esplicito:
      ```nix
      environment.systemPackages = lib.mkOverride 50 (lib.subtractLists
        [ pkgs.chromium pkgs.thunderbird ]
        config.environment.systemPackages);
      ```
    '';
  };
}
