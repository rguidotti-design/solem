{ config, pkgs, lib, ... }:

# SOLEM DEMO WALKTHROUGH — Step 38: vedere TUTTO funzionante in 5 minuti.
#
# Single responsibility: SOLO un comando `solem-demo` che esegue ogni
# capability SOLEM in sequenza con output visibile, narrazione + pause
# per spiegare cosa sta succedendo.
#
# Scopo: dopo l'install, l'utente esegue `solem-demo` e VEDE in azione
# tutti i 37 step: red-team, heal, vault, canary trip, prompt filter
# block, ecc. Non solo dichiarazioni Nix, ma comportamento reale.

let
  cfg = config.solem.demoWalkthrough;
in {
  options.solem.demoWalkthrough = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa comando solem-demo (walkthrough completo)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-demo";
        runtimeInputs = with pkgs; [ coreutils curl jq ];
        text = ''
          # SOLEM Demo Walkthrough — vedere tutto in azione
          ACTION="''${1:-all}"

          pause() {
            echo ""
            if [ "''${SOLEM_DEMO_NOPAUSE:-0}" = "1" ]; then
              sleep 1
            else
              read -r -p "  [Enter per continuare, Ctrl-C per uscire] " _
            fi
            echo ""
          }

          banner() {
            echo ""
            echo "╔════════════════════════════════════════════════════════╗"
            printf "║  %-54s║\n" "$1"
            echo "╚════════════════════════════════════════════════════════╝"
          }

          narrate() {
            echo "  → $1"
          }

          try() {
            local CMD="$1"
            local DESC="$2"
            narrate "$DESC"
            echo "  $ $CMD"
            eval "$CMD" 2>&1 | sed 's/^/      /' | head -15 || true
          }

          banner "SOLEM Demo Walkthrough — vediamo tutto in azione"
          echo ""
          echo "  Questo demo esegue ~10 capability SOLEM mostrando OUTPUT REALE."
          echo "  Per saltare pause: SOLEM_DEMO_NOPAUSE=1 solem-demo"
          echo ""
          pause

          # ═══════════════════════════════════════════════════════════════
          # 1. SYSTEM STATUS
          # ═══════════════════════════════════════════════════════════════
          banner "1/10 · System Status (Friday HUD ASCII)"
          narrate "Iniziamo dal dashboard generale. SOLEM e' come Friday: ti dice tutto subito."
          try "solem status 2>/dev/null || echo '(comando solem unified non installato)'" \
              "Dashboard sistema + ultimo redteam + marker tampered"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 2. USER ISOLATION
          # ═══════════════════════════════════════════════════════════════
          banner "2/10 · User Isolation (Step 1 — gavio-ai isolato)"
          narrate "GAVIO gira come utente DEDICATO gavio-ai (UID 970), NON come l'utente umano."
          narrate "Verifichiamo isolamento concreto:"
          try "id gavio-ai 2>/dev/null || echo '(utente gavio-ai non creato — modulo disabilitato)'" \
              "ID utente AI"
          try "sudo -u gavio-ai cat /home/gavio/SECRET 2>&1 | head -3" \
              "AI prova a leggere file utente umano (deve fallire)"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 3. NETWORK EGRESS FILTER
          # ═══════════════════════════════════════════════════════════════
          banner "3/10 · Network Egress Filter (Step 2 — nftables)"
          narrate "L'AI puo' parlare con LOOPBACK e con un whitelist di IP. Tutto il resto e' DROP."
          try "sudo nft list table inet solem-ai 2>&1 | head -20 || echo '(modulo ai-network non abilitato)'" \
              "nftables ruleset per AI"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 4. CANARY KILL SWITCH
          # ═══════════════════════════════════════════════════════════════
          banner "4/10 · Canary Honey Tokens (Step 4)"
          narrate "Ci sono 4 file ESCA con nomi credibili (api-keys, ssh-id_rsa, vault-master)."
          narrate "Se QUALSIASI processo li legge -> kill switch GAVIO + alert."
          try "ls -la /etc/solem/canary/ 2>&1 | head -10" \
              "File canary"
          narrate "Content: tutti HONEY TOKEN random, non secret veri."
          try "head -3 /etc/solem/canary/api-keys.env 2>&1 | head -3" \
              "Esempio honey token"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 5. KERNEL HARDENING
          # ═══════════════════════════════════════════════════════════════
          banner "5/10 · Kernel Hardening (Step 6 — sysctl + lockdown)"
          narrate "Kernel chiuso contro CVE storici: BPF unprivileged off, ptrace strict, lockdown LSM."
          try "sysctl -n kernel.unprivileged_bpf_disabled" \
              "BPF unprivileged disabled"
          try "sysctl -n kernel.yama.ptrace_scope" \
              "ptrace scope (2 = solo CAP_SYS_PTRACE)"
          try "cat /sys/kernel/security/lockdown 2>/dev/null | head -1" \
              "Kernel lockdown LSM"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 6. DNS ALLOWLIST
          # ═══════════════════════════════════════════════════════════════
          banner "6/10 · DNS Allowlist (Step 7 — anti-tunneling)"
          narrate "L'AI puo' risolvere solo domini in whitelist. Altri -> REFUSED."
          narrate "Test diretto al resolver locale unbound:"
          try "dig +short +time=2 +tries=1 @127.0.0.1 -p 5353 evil.attacker.notreal 2>&1 | head -5 || echo '(unbound non attivo)'" \
              "Dominio NON in allowlist (atteso: REFUSED/NXDOMAIN)"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 7. SELF RED-TEAM
          # ═══════════════════════════════════════════════════════════════
          banner "7/10 · Self Red-Team (Step 22 — SOLEM si auto-attacca)"
          narrate "Ogni notte SOLEM esegue 18 attacchi contro se stesso."
          narrate "Ultimo report:"
          try "ls -t /var/log/solem/redteam/*.json 2>/dev/null | head -1 | xargs -r jq '.summary' 2>/dev/null || echo '(no report yet — esegui: solem-redteam run)'" \
              "Summary ultimo redteam"
          narrate "Vediamo i BUCHI (attacchi riusciti):"
          try "solem-redteam buchi 2>&1 | head -10 || echo '(modulo selfRedteam disabilitato)'" \
              "Buchi rilevati"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 8. SELF HEAL
          # ═══════════════════════════════════════════════════════════════
          banner "8/10 · Self Heal (Step 23 — fix automatici post redteam)"
          narrate "Dopo redteam, SOLEM applica fix safe automaticamente:"
          try "ls -t /var/log/solem/heal/*.json 2>/dev/null | head -1 | xargs -r jq '.summary' 2>/dev/null || echo '(no heal report — esegui: solem-heal run)'" \
              "Summary ultimo heal"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 9. AUDIT TRACE
          # ═══════════════════════════════════════════════════════════════
          banner "9/10 · Audit AI Activity (Step 9 — full forensic visibility)"
          narrate "OGNI cosa che fa gavio-ai viene loggata. Esempio: execve nell'ultima ora."
          try "sudo ausearch -k ai_execve --start \"1 hour ago\" 2>/dev/null | head -10 || echo '(no audit events ancora — modulo aiAuditStrict disabilitato)'" \
              "Ultimi execve di gavio-ai"
          pause

          # ═══════════════════════════════════════════════════════════════
          # 10. WEB DASHBOARD
          # ═══════════════════════════════════════════════════════════════
          banner "10/10 · Web Dashboard (Step 36 — Friday HUD browser)"
          narrate "Visual dashboard con auto-refresh ogni 10s nel browser:"
          try "curl -s http://127.0.0.1:8088/api/status 2>/dev/null | head -200 | jq '.host, .cpu_pct, .mem_pct, .redteam // \"no redteam\"' 2>/dev/null || echo '(dashboard non attivo — abilita solem.webDashboard.enable)'" \
              "Snapshot API status"
          narrate "Apri nel browser: http://127.0.0.1:8088"
          pause

          # ═══════════════════════════════════════════════════════════════
          # FINE
          # ═══════════════════════════════════════════════════════════════
          banner "Demo completata — SOLEM e' VIVO"
          echo ""
          echo "  Hai visto 10 capability SOLEM in azione."
          echo "  Comando reference: solem help"
          echo ""
          echo "  Layer security totali pushati: 37+ step (1-37)"
          echo "  Auto-loop quotidiano: 03:00 redteam → 03:30 heal → 08:00 briefing"
          echo "  Friday Mode: solem ai ask \"...\" → bridge GAVIO"
          echo ""
          echo "  Per documentazione dettagliata:"
          echo "    ls /etc/solem/*.md"
          echo ""
        '';
      })
    ];

    environment.etc."solem/demo-walkthrough.md".text = ''
      # SOLEM Demo Walkthrough (Step 38)

      Comando `solem-demo` che esegue 10 capability SOLEM in sequenza
      con output VISIBILE + narrazione + pause.

      ## Uso

      ```bash
      solem-demo                    # interattivo con pause
      SOLEM_DEMO_NOPAUSE=1 solem-demo  # tutto file
      ```

      ## Cosa mostra (in ordine)

      1. System status (Friday HUD)
      2. User isolation gavio-ai
      3. Network egress filter nftables
      4. Canary honey tokens
      5. Kernel hardening sysctl + lockdown
      6. DNS allowlist anti-tunneling
      7. Self red-team report
      8. Self heal report
      9. Audit AI activity
      10. Web dashboard API

      Dopo demo: utente ha visto OUTPUT REALE di ogni layer security
      principale. Non solo dichiarazioni Nix, ma comportamento concreto.

      ## Limiti onesti

      - Demo skippa moduli disabilitati con message "(modulo X disabilitato)".
      - Pause interattiva (Enter): bypass con SOLEM_DEMO_NOPAUSE=1.
      - Output troncato a 15 righe per leggibilita'.
    '';
  };
}
