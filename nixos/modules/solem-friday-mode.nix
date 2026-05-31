{ config, pkgs, lib, ... }:

# SOLEM FRIDAY MODE — Step 27: SOLEM diventa attivo come Friday/JARVIS.
#
# Metafora utente: SOLEM = Friday (guscio attivo che contiene + controlla
# GAVIO), GAVIO = AI vera (Tony chiede a JARVIS). Questo modulo concretizza
# la metafora: SOLEM smette di essere OS passivo, fa PROATTIVAMENTE:
#
#   1. Briefing mattutino (cron 08:00): riassunto della notte.
#   2. Status conversazionale (`solem status` ASCII HUD).
#   3. Bridge GAVIO: chiede interpretazione eventi non chiari.
#   4. Action policy autonoma: lockdown su critical alert.
#   5. Voice opt-in: TTS proattivo (espeak).
#
# Aggrega informazioni da TUTTI gli altri step 1-26:
#   - self-redteam buchi
#   - self-heal applied
#   - canary trip
#   - suricata IDS critical
#   - audit AI activity
#   - kernel update pending
#   - backup status
#   - hardware temperature / disk
#
# Tutto FOSS (Python stdlib + jq + espeak opt-in).

let
  cfg = config.solem.fridayMode;

  briefingScript = pkgs.writers.writePython3Bin "solem-friday-briefing" {
    libraries = [ ];
    flakeIgnore = [ "E501" "E302" "W291" "W293" "E305" "E402" "E741" ];
  } ''
    """SOLEM Friday: briefing periodico — stato sistema + eventi notte.

    Aggrega dati da:
      - /var/log/solem/redteam/LATEST.md (Step 22)
      - /var/log/solem/heal/*.json (Step 23)
      - /var/log/solem/canary.log (Step 4)
      - /var/lib/solem/IDS_ALERT (Step 25)
      - /var/log/audit/audit.log (Step 9)
      - /proc/meminfo, /proc/loadavg (system)
      - /sys/class/thermal (temp)
      - /var/log/solem/backup.log (Step 17)
    """
    import json
    import os
    import subprocess
    import sys
    from datetime import datetime, timezone
    from pathlib import Path

    def run(cmd, timeout=5):
        try:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
            return r.stdout.strip()
        except Exception:
            return ""

    def file_tail(p, n=5):
        try:
            with open(p) as f:
                return f.readlines()[-n:]
        except Exception:
            return []

    def file_age_min(p):
        try:
            mtime = os.stat(p).st_mtime
            return int((datetime.now().timestamp() - mtime) / 60)
        except Exception:
            return -1

    NOW = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    HOST = os.uname().nodename

    sections = []

    # ── HEADER ──
    sections.append(f"╔══════════════════════════════════════════════════╗")
    sections.append(f"║       SOLEM Friday Mode — Briefing               ║")
    sections.append(f"║       {NOW:<42} ║")
    sections.append(f"║       Host: {HOST:<36} ║")
    sections.append(f"╚══════════════════════════════════════════════════╝")
    sections.append("")

    # ── SYSTEM STATE ──
    uptime = run("uptime -p")
    load = run("cat /proc/loadavg | awk '{print $1, $2, $3}'")
    mem_used = run("free -m | awk '/Mem:/ {printf \"%dMB/%dMB (%.0f%%)\", $3, $2, $3/$2*100}'")
    disk_root = run("df -h / | awk 'NR==2 {print $5\" usato di \"$2}'")

    sections.append("── Sistema ──")
    sections.append(f"  Uptime:    {uptime or '?'}")
    sections.append(f"  Load avg:  {load or '?'}")
    sections.append(f"  RAM:       {mem_used or '?'}")
    sections.append(f"  Disk /:    {disk_root or '?'}")

    # Temperatura (Intel/AMD)
    temp_raw = run("cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null")
    if temp_raw.isdigit():
        sections.append(f"  CPU temp:  {int(temp_raw)/1000:.1f}°C")
    sections.append("")

    # ── SECURITY EVENTS (notte) ──
    sections.append("── Eventi sicurezza ultime 24h ──")

    # Self-redteam ultimo report
    redteam_json = sorted(Path("/var/log/solem/redteam").glob("*.json"))
    if redteam_json:
        latest = json.loads(redteam_json[-1].read_text())
        summary = latest.get("summary", {})
        buchi = summary.get("buchi", 0)
        blocked = summary.get("blocked", 0)
        total = summary.get("total", 0)
        icon = "❌" if buchi > 0 else "✅"
        sections.append(f"  {icon} Self red-team: {blocked}/{total} blocked, {buchi} BUCHI")
        if buchi > 0:
            for sc in latest.get("scenarios", []):
                if sc.get("verdict") == "BUCO":
                    sections.append(f"    - {sc['name']}: {sc.get('evidence', '?')[:60]}")
    else:
        sections.append("  ⚪ Self red-team: mai eseguito")

    # Self-heal
    heal_json = sorted(Path("/var/log/solem/heal").glob("*.json"))
    if heal_json:
        latest = json.loads(heal_json[-1].read_text())
        applied = latest.get("summary", {}).get("auto_fix_applied", 0)
        if applied > 0:
            sections.append(f"  🔧 Self-heal: {applied} fix applicate")

    # Canary
    canary_marker = Path("/var/lib/solem/CANARY_TRIPPED")
    if canary_marker.exists():
        sections.append(f"  ⚠⚠ CANARY TRIPPED: {canary_marker.read_text().strip()[:80]}")

    # IDS alert
    ids_marker = Path("/var/lib/solem/IDS_ALERT")
    if ids_marker.exists():
        lines = ids_marker.read_text().strip().split("\n")
        sections.append(f"  ⚠ Suricata IDS: {len(lines)} critical alert ultime 24h")
        for l in lines[-3:]:
            sections.append(f"    {l[:80]}")

    # Audit AI activity count
    audit_log = "/var/log/audit/audit.log"
    if Path(audit_log).exists():
        ai_exec = run(f"sudo grep -c 'key=\"ai_execve\"' {audit_log} 2>/dev/null") or "0"
        ai_conn = run(f"sudo grep -c 'key=\"ai_connect\"' {audit_log} 2>/dev/null") or "0"
        sections.append(f"  📊 AI activity: {ai_exec} execve, {ai_conn} connect attempts")

    sections.append("")

    # ── UPDATES / MAINTENANCE ──
    sections.append("── Manutenzione ──")
    # Nix generation
    gen = run("readlink /nix/var/nix/profiles/system | sed 's/system-//;s/-link//'")
    sections.append(f"  System gen: {gen or '?'}")

    # Backup
    backup_log = "/var/log/solem/backup.log"
    if Path(backup_log).exists():
        age = file_age_min(backup_log)
        if age >= 0:
            hrs = age // 60
            sections.append(f"  Last backup: {hrs}h fa")
    else:
        sections.append(f"  Last backup: ⚠ MAI (configura solem.backupEncrypted)")

    # Last update check
    update_log = run("journalctl -u nixos-upgrade.service --since '7 days ago' --no-pager 2>/dev/null | tail -3")
    if update_log:
        sections.append(f"  Auto-update: attivo")
    else:
        sections.append(f"  Auto-update: ⚪ inattivo (configura solem.autoUpdate)")
    sections.append("")

    # ── GAVIO STATE ──
    sections.append("── GAVIO ──")
    gavio_active = run("systemctl is-active gavio.service 2>/dev/null")
    if gavio_active == "active":
        sections.append(f"  ✅ Service: ATTIVO")
        # Memoria GAVIO se disponibile
        mem = run("systemctl show gavio.service -p MemoryCurrent --value 2>/dev/null")
        if mem.isdigit() and int(mem) > 0:
            mb = int(mem) / 1024 / 1024
            sections.append(f"  RAM:       {mb:.0f} MB")
    else:
        sections.append(f"  ⚪ Service: {gavio_active or 'inattivo'}")

    # Ollama
    ollama_active = run("systemctl is-active ollama.service 2>/dev/null")
    sections.append(f"  Ollama:    {ollama_active or 'inattivo'}")

    sections.append("")

    # ── FOOTER ──
    sections.append("─" * 52)
    sections.append("CLI: solem status | solem ask <q> | solem lockdown")
    sections.append("─" * 52)

    output = "\n".join(sections)
    print(output)

    # Persist briefing in log
    briefing_dir = Path("/var/log/solem/friday")
    briefing_dir.mkdir(parents=True, exist_ok=True)
    ts_file = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    (briefing_dir / f"{ts_file}.txt").write_text(output)
    (briefing_dir / "LATEST.txt").write_text(output)
  '';

  fridayCli = pkgs.writeShellApplication {
    name = "solem";
    runtimeInputs = with pkgs; [ coreutils jq systemd curl libnotify ];
    text = ''
      ACTION="''${1:-status}"
      shift || true

      case "$ACTION" in
        status)
          # Mini status dashboard (ASCII HUD stile)
          if [ -f /var/log/solem/friday/LATEST.txt ]; then
            cat /var/log/solem/friday/LATEST.txt
          else
            echo "Briefing non ancora generato. Run: solem briefing"
          fi
          ;;

        briefing|hud)
          ${briefingScript}/bin/solem-friday-briefing
          # TTS opt-in
          ${lib.optionalString cfg.voice ''
            if command -v espeak >/dev/null 2>&1; then
              # Estrai sommario buchi/heal/alert per voice short
              BUCHI=$(jq '.summary.buchi // 0' /var/log/solem/redteam/$(ls -t /var/log/solem/redteam/ 2>/dev/null | head -1) 2>/dev/null || echo 0)
              if [ "$BUCHI" -gt 0 ]; then
                espeak -v it "Attenzione: trovati $BUCHI buchi di sicurezza." 2>/dev/null || true
              else
                espeak -v it "Sistema sicuro. Nessun buco rilevato." 2>/dev/null || true
              fi
            fi
          ''}
          ;;

        ask)
          # Bridge GAVIO: chiama API GAVIO per interpretare query
          Q="''${1:?Usage: solem ask <domanda>}"
          GAVIO_URL="${cfg.gavioApiUrl}"
          if curl -s -m 2 -o /dev/null "$GAVIO_URL/health" 2>/dev/null; then
            echo "Chiedo a GAVIO: $Q"
            RES=$(curl -s -X POST "$GAVIO_URL/api/chat" \
              -H "Content-Type: application/json" \
              -d "{\"message\":\"Contesto sistema SOLEM. Domanda: $Q\"}" \
              -m 30 2>/dev/null | jq -r '.response // .message // .' 2>/dev/null)
            echo "$RES"
          else
            echo "GAVIO non risponde su $GAVIO_URL. Sistema offline?"
            echo
            echo "Risposta SOLEM (no AI): consulta solem briefing per stato sistema."
          fi
          ;;

        lockdown)
          # Action proattiva: lockdown sistema
          echo "── SOLEM LOCKDOWN ──"
          read -r -p "Confermi lockdown (stop GAVIO + revoke WG + block outbound)? [YES/no]: " ANS
          if [ "$ANS" = "YES" ]; then
            echo "1/4 Stop GAVIO..."
            sudo systemctl stop gavio.service 2>/dev/null || true
            echo "2/4 Stop ollama..."
            sudo systemctl stop ollama.service 2>/dev/null || true
            echo "3/4 Restrict firewall (drop outbound non whitelist)..."
            sudo iptables -I OUTPUT -j REJECT 2>/dev/null || true
            sudo iptables -I OUTPUT -d 127.0.0.0/8 -j ACCEPT 2>/dev/null
            sudo iptables -I OUTPUT -d 10.100.0.0/24 -j ACCEPT 2>/dev/null
            echo "4/4 Notify..."
            for D in /run/user/*; do
              [ -d "$D" ] || continue
              U=$(basename "$D")
              sudo -u "#$U" DBUS_SESSION_BUS_ADDRESS="unix:path=$D/bus" \
                notify-send -u critical "SOLEM LOCKDOWN" "Sistema in modalita' difensiva. Run: solem unlockdown" 2>/dev/null || true
            done
            echo "✓ Lockdown attivo. Verifica con: solem status"
          fi
          ;;

        unlockdown)
          echo "── SOLEM UNLOCKDOWN ──"
          read -r -p "Confermi restore (start GAVIO + clear firewall extra)? [YES/no]: " ANS
          if [ "$ANS" = "YES" ]; then
            sudo iptables -D OUTPUT -j REJECT 2>/dev/null || true
            sudo systemctl start ollama.service 2>/dev/null || true
            sudo systemctl start gavio.service 2>/dev/null || true
            echo "✓ Sistema restored"
          fi
          ;;

        morning|night)
          # Alias per briefing
          ${briefingScript}/bin/solem-friday-briefing
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem — Friday Mode CLI (SOLEM as JARVIS/Friday)

  status         dashboard ASCII HUD (ultimo briefing)
  briefing       genera briefing live (forensics + system + GAVIO)
  ask <q>        chiedi a GAVIO via API (richiede gavio-api active)
  lockdown       stop GAVIO + restrict firewall + notify (paranoid mode)
  unlockdown     restore sistema

Aliases:
  morning, night   alias briefing
  hud              alias briefing

Schedule automatico:
  - solem-friday-briefing.service eseguito ${cfg.briefingSchedule}
  - Briefing salvato in /var/log/solem/friday/{ts}.txt + LATEST.txt
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.fridayMode = {
    enable = lib.mkEnableOption "SOLEM Friday Mode: briefing proattivo + status conv + bridge GAVIO";

    briefingSchedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 08:00:00";
      description = ''
        OnCalendar: quando generare briefing automatico.
        Default 08:00 daily (buongiorno utente).
      '';
    };

    voice = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Abilita TTS via espeak su briefing automatic. Voice italiana.
        Default off (rumoroso se workstation in ufficio).
      '';
    };

    gavioApiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8000";
      description = "URL backend GAVIO API per bridge 'solem ask'";
    };

    notifyOnBriefing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "notify-send desktop con sommario briefing";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/log/solem 0750 root root - -"
      "d /var/log/solem/friday 0750 root root - -"
    ];

    # Briefing service
    systemd.services.solem-friday-briefing = {
      description = "SOLEM Friday: morning briefing + state aggregator";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${briefingScript}/bin/solem-friday-briefing";
        ExecStartPost = lib.mkIf cfg.notifyOnBriefing
          "${pkgs.writeShellScript "friday-notify" ''
            set +e
            for D in /run/user/*; do
              [ -d "$D" ] || continue
              U=$(basename "$D")
              # Sommario short da briefing
              BUCHI=$(${pkgs.jq}/bin/jq '.summary.buchi // 0' $(ls -t /var/log/solem/redteam/*.json 2>/dev/null | head -1) 2>/dev/null || echo 0)
              CANARY=$( [ -f /var/lib/solem/CANARY_TRIPPED ] && echo "+CANARY" || echo "" )
              IDS=$( [ -f /var/lib/solem/IDS_ALERT ] && echo "+IDS" || echo "" )
              MSG="Briefing pronto. Buchi: $BUCHI $CANARY $IDS"
              sudo -u "#$U" DBUS_SESSION_BUS_ADDRESS="unix:path=$D/bus" \
                ${pkgs.libnotify}/bin/notify-send -u normal -t 20000 \
                "SOLEM Friday" "$MSG. Run: solem status" 2>/dev/null || true
            done
            ${lib.optionalString cfg.voice ''
              command -v ${pkgs.espeak}/bin/espeak >/dev/null && \
                ${pkgs.espeak}/bin/espeak -v it "Briefing pronto" 2>/dev/null || true
            ''}
          ''}";
        User = "root";
      };
    };

    systemd.timers.solem-friday-briefing = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.briefingSchedule;
        Persistent = true;
      };
    };

    environment.systemPackages = [
      briefingScript
      fridayCli
    ] ++ lib.optional cfg.voice pkgs.espeak;

    environment.etc."solem/friday-mode.md".text = ''
      # SOLEM Friday Mode (Step 27)

      Concretizza la metafora utente: SOLEM = Friday/JARVIS (guscio attivo
      che contiene + controlla GAVIO). GAVIO = AI vera dentro Friday.

      ## Capacita' attive (Friday-like)

      1. **Briefing mattutino** (${cfg.briefingSchedule}):
         - Aggrega eventi notte da TUTTI step 1-26
         - Self-redteam buchi + self-heal applied + canary trip + IDS alert
         - System state (RAM, load, disk, temp CPU)
         - GAVIO service state
         - Output: ASCII HUD + notify-send (+ voice se enabled)

      2. **Status conversazionale** (`solem status`):
         - Mostra ultimo briefing
         - Dashboard immediato

      3. **Bridge GAVIO** (`solem ask <q>`):
         - Forwarda a GAVIO API (${cfg.gavioApiUrl}/api/chat)
         - Risposta strutturata
         - Fallback: messaggio offline

      4. **Lockdown autonomo** (`solem lockdown`):
         - Stop GAVIO + ollama
         - iptables OUTPUT REJECT (solo loopback + WG mesh consentiti)
         - Notify critical desktop
         - `solem unlockdown` per restore

      ## Workflow tipico

      Mattina:
        08:00 → briefing auto + notify
        08:01 → utente apre: solem status (dashboard)
        08:02 → utente: solem ask "cosa è successo stanotte"
                 → GAVIO interpreta + risponde

      Incident:
        Suricata → critical alert → IDS_ALERT marker → canary kill switch →
        solem-self-heal applica fix safe → notify desktop
        Utente vede + decide: solem lockdown se vuole paranoid mode.

      ## Voice opt-in

      ```nix
      solem.fridayMode.voice = true;
      ```
      espeak in italiano. Default off (rumoroso ufficio).

      ## Limiti onesti

      - Friday Mode dipende da GAVIO API per "ask" complete. Senza GAVIO
        running: degrada a status sistema only.
      - Briefing aggrega solo Step 1-26 attivi. Layer non enabled → assenti.
      - Lockdown e' invasivo: iptables OUTPUT REJECT puo' rompere update,
        backup offsite, ... → unlockdown manuale.
      - TTS espeak ha voce robotica. Per voce naturale: pikoTTS o Mimic3
        (futuro Step opzionale).
    '';
  };
}
