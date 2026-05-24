{ config, pkgs, lib, ... }:

# SOLEM DEMO — mostra capability del sistema in 30 secondi.
#
# Single responsibility: SOLO CLI `solem-demo` che esegue diagnostica
# rapida e mostra cosa funziona. Solo dipendenze base (coreutils + curl).

let
  cfg = config.solem.demo;

  demoCli = pkgs.writeShellApplication {
    name = "solem-demo";
    runtimeInputs = with pkgs; [ coreutils systemd curl ];
    text = ''
      echo "════════════════════════════════════════════════════════════"
      echo "  SOLEM Demo · AI-native OS · 30s · 0 €"
      echo "════════════════════════════════════════════════════════════"
      echo

      # ── 1. Sistema ──────────────────────────────────────────────
      echo "[1/6] Sistema"
      echo "  Hostname:  $(hostname)"
      echo "  Kernel:    $(uname -r)"
      echo "  Uptime:    $(uptime -p 2>/dev/null || uptime)"
      MEM=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}' || echo "?")
      echo "  Memoria:   $MEM"
      echo

      # ── 2. SOLEM CLI ─────────────────────────────────────────────
      echo "[2/6] SOLEM CLI"
      if command -v solem >/dev/null 2>&1; then
        echo "  ✓ solem CLI installato"
      else
        echo "  ⚠ solem CLI mancante"
      fi
      echo

      # ── 3. GAVIO API ─────────────────────────────────────────────
      echo "[3/6] GAVIO API (:8000)"
      if curl -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/health 2>/dev/null | grep -q "200"; then
        echo "  ✓ GAVIO risponde"
      else
        echo "  ○ GAVIO offline (avvialo: gavio-server &)"
      fi
      echo

      # ── 4. solem-api ─────────────────────────────────────────────
      echo "[4/6] Public APIs"
      if command -v solem-api >/dev/null 2>&1; then
        echo "  ✓ solem-api installato (36 endpoint)"
      else
        echo "  ○ solem-api non installato (solem.publicApis.enable)"
      fi
      echo

      # ── 5. Network ───────────────────────────────────────────────
      echo "[5/6] Network"
      NIF=$(ip -o link show 2>/dev/null | wc -l)
      echo "  Interfacce: $NIF"
      DEF=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
      echo "  Default:    ''${DEF:-nessuna}"
      echo

      # ── 6. Servizi SOLEM attivi ─────────────────────────────────
      echo "[6/6] Servizi"
      for svc in gavio solem-api solem-keep solem-update solem-backup; do
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        if [ "$STATUS" = "active" ]; then
          echo "  ✓ $svc"
        else
          echo "  ○ $svc ($STATUS)"
        fi
      done

      echo
      echo "════════════════════════════════════════════════════════════"
      echo "  Demo completato. Prossimo: solem-doctor (diagnosi completa)"
      echo "════════════════════════════════════════════════════════════"
    '';
  };
in {
  options.solem.demo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa il comando `solem-demo` (tour capability)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ demoCli ];
  };
}
