{ config, pkgs, lib, ... }:

# SOLEM EMAIL — client locale + offline-first (Geary/Thunderbird).
#
# Single responsibility: SOLO installazione client + helper script
# `solem-mail-triage` (chiama AI per smistare email non lette).
#
# Apps FOSS:
#   - Thunderbird   → client multipiattaforma classico
#   - Geary         → client GNOME moderno
#   - aerc          → TUI moderno (notmuch backend)
#   - notmuch       → indicizzatore + tagger offline
#   - mbsync        → IMAP sync (isync)
#
# 100% locale, costo 0 €.

let
  cfg = config.solem.email;

  triageScript = pkgs.writeShellApplication {
    name = "solem-mail-triage";
    runtimeInputs = with pkgs; [ notmuch curl jq coreutils ];
    text = ''
      # Triage AI per email non lette (richiede notmuch indexed)
      # Manda subject+from al /ai/route → categoria suggerita → tagga notmuch

      API="''${SOLEM_API_URL:-http://127.0.0.1:8001}"
      QUERY="''${1:-tag:unread and not tag:triaged}"

      ${pkgs.notmuch}/bin/notmuch search --format=json "$QUERY" | ${pkgs.jq}/bin/jq -c '.[]' | while read -r msg; do
        thread_id=$(echo "$msg" | ${pkgs.jq}/bin/jq -r .thread)
        subject=$(echo "$msg" | ${pkgs.jq}/bin/jq -r .subject)
        from=$(echo "$msg" | ${pkgs.jq}/bin/jq -r .authors)

        prompt="Email da: $from. Subject: $subject. Suggerisci UNA categoria tra: urgent, work, personal, newsletter, spam, social. Reply ONLY one word."
        body=$(${pkgs.jq}/bin/jq -n --arg p "$prompt" '{messages:[{role:"user",content:$p}],hint:"auto",max_tokens:20,temperature:0.1}')
        cat=$(${pkgs.curl}/bin/curl -fsS -X POST "$API/solem/ai/route" -H 'Content-Type: application/json' -d "$body" | ${pkgs.jq}/bin/jq -r .content | tr -d ' ' | tr 'A-Z' 'a-z' | head -c 20)

        case "$cat" in
          urgent|work|personal|newsletter|spam|social)
            ${pkgs.notmuch}/bin/notmuch tag +ai-"$cat" +triaged -- thread:"$thread_id"
            echo "  [$cat] $subject"
            ;;
          *)
            ${pkgs.notmuch}/bin/notmuch tag +ai-unknown +triaged -- thread:"$thread_id"
            ;;
        esac
      done
    '';
  };
in {
  options.solem.email = {
    enable = lib.mkEnableOption "Email client locale (Thunderbird + Geary + notmuch)";

    aiTriage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Helper script solem-mail-triage per AI smistamento";
    };

    notmuchSync = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Timer mbsync ogni 5min + notmuch index";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      thunderbird
      geary
      aerc
      notmuch
      isync          # mbsync
      msmtp          # SMTP send
      lieer          # alternativa: gmail-rest
    ] ++ lib.optional cfg.aiTriage triageScript;

    # mbsync timer ogni 5 min se attivato
    systemd.user.services.solem-mail-sync = lib.mkIf cfg.notmuchSync {
      description = "SOLEM — mbsync + notmuch index";
      script = ''
        ${pkgs.isync}/bin/mbsync -a 2>/dev/null || true
        ${pkgs.notmuch}/bin/notmuch new 2>/dev/null || true
      '';
      serviceConfig.Type = "oneshot";
    };

    systemd.user.timers.solem-mail-sync = lib.mkIf cfg.notmuchSync {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
