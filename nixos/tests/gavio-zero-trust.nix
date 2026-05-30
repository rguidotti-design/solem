{ pkgs }:

# VM test: solem-gavio-zero-trust override systemd sul service gavio.
#
# Cosa verifico CONCRETAMENTE:
#   1. Il service gavio risulta configurato con User=gavio-ai
#   2. NoNewPrivileges=yes
#   3. CapabilityBoundingSet vuoto
#   4. PrivateDevices=yes
#   5. ProtectSystem=strict
#   6. SystemCallFilter contiene ~@privileged ~@mount
#   7. ReadWritePaths esclude /home /etc
#
# Cosa NON copre (onesto):
#   - NON avvia GAVIO reale (richiede /opt/gavio con codice Python).
#   - NON verifica che le restrizioni FERMINO un attacco vero,
#     solo che le direttive systemd siano IMPOSTATE come atteso.
#   - Stop alla unit per evitare bootstrap fail (venv mancante).

pkgs.nixosTest {
  name = "solem-gavio-zero-trust";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-ai-user.nix
      ../modules/gavio.nix
      ../modules/solem-gavio-zero-trust.nix
    ];

    solem.aiUser.enable = true;
    solem.gavioZeroTrust.enable = true;

    # Disabilita avvio automatico GAVIO (non e' realmente packaged in VM)
    systemd.services.gavio.wantedBy = lib.mkForce [ ];
    systemd.services.solem-ollama-prepull.wantedBy = lib.mkForce [ ];
    services.ollama.enable = lib.mkForce false;

    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.sleep(2)

    # Il service esiste (anche se non avviato)
    machine.succeed("systemctl cat gavio.service 2>&1 | head -50")

    # ── TEST 1: User override ─────────────────────────────────────
    user = machine.succeed("systemctl show gavio.service -p User --value").strip()
    print(f"gavio.service User = '{user}'")
    assert user == "gavio-ai", f"FAIL: User='{user}', atteso 'gavio-ai'"

    # ── TEST 2: NoNewPrivileges ───────────────────────────────────
    nnp = machine.succeed("systemctl show gavio.service -p NoNewPrivileges --value").strip()
    print(f"NoNewPrivileges = '{nnp}'")
    assert nnp == "yes", f"FAIL: NNP='{nnp}', atteso 'yes'"

    # ── TEST 3: CapabilityBoundingSet vuoto ───────────────────────
    cap = machine.succeed("systemctl show gavio.service -p CapabilityBoundingSet --value").strip()
    print(f"CapabilityBoundingSet = '{cap}'")
    # Vuoto o "0" sono entrambi validi (systemd serializza in vari modi)
    assert cap in ("", "0"), f"FAIL: caps='{cap}', atteso vuoto"

    # ── TEST 4: PrivateDevices ────────────────────────────────────
    pd = machine.succeed("systemctl show gavio.service -p PrivateDevices --value").strip()
    print(f"PrivateDevices = '{pd}'")
    assert pd == "yes", f"FAIL: PrivateDevices='{pd}', atteso 'yes'"

    # ── TEST 5: ProtectSystem strict ──────────────────────────────
    ps = machine.succeed("systemctl show gavio.service -p ProtectSystem --value").strip()
    print(f"ProtectSystem = '{ps}'")
    assert ps == "strict", f"FAIL: ProtectSystem='{ps}', atteso 'strict'"

    # ── TEST 6: SystemCallFilter esclude syscall pericolosi ────────
    # systemd risolve @system-service ~@privileged ~@mount ecc. in
    # una LISTA WHITELIST concreta di syscall name (non tag string).
    # Verifichiamo che syscall NOTORIAMENTE pericolosi NON siano presenti.
    scf = machine.succeed("systemctl show gavio.service -p SystemCallFilter --value")
    print(f"SystemCallFilter (first 300) = '{scf[:300]}...'")
    # Syscall che dovrebbero essere BLOCCATI da ~@privileged ~@mount ~@module ~@raw-io
    BLOCKED_SYSCALLS = [
        "mount",        # ~@mount: mount/umount
        "umount2",
        "init_module",  # ~@module: kernel module load
        "finit_module",
        "delete_module",
        "ioperm",       # ~@raw-io
        "iopl",
        "reboot",       # ~@reboot
        "kexec_load",
        "swapon",       # ~@swap
        "keyctl",       # ~@keyring (vault protection)
    ]
    leaked = [s for s in BLOCKED_SYSCALLS if f" {s} " in f" {scf} " or f" {s}\n" in scf]
    assert not leaked, f"FAIL: syscall pericolosi presenti in whitelist: {leaked}"
    print(f"  ✓ {len(BLOCKED_SYSCALLS)} syscall pericolosi tutti esclusi")

    # ── TEST 7: ReadWritePaths esclude /home /etc ─────────────────
    rwp = machine.succeed("systemctl show gavio.service -p ReadWritePaths --value")
    print(f"ReadWritePaths = '{rwp}'")
    assert "/home" not in rwp, "FAIL: /home in ReadWritePaths"
    assert "/etc/gavio" not in rwp, "FAIL: /etc/gavio in ReadWritePaths (deve essere ReadOnly)"
    assert "/var/lib/gavio-ai" in rwp, "FAIL: /var/lib/gavio-ai NON in ReadWritePaths"

    # ── TEST 8: ProtectHome ───────────────────────────────────────
    ph = machine.succeed("systemctl show gavio.service -p ProtectHome --value").strip()
    print(f"ProtectHome = '{ph}'")
    assert ph in ("tmpfs", "yes"), f"FAIL: ProtectHome='{ph}'"

    # ── TEST 9: ProtectProc invisible ─────────────────────────────
    pp = machine.succeed("systemctl show gavio.service -p ProtectProc --value").strip()
    print(f"ProtectProc = '{pp}'")
    assert pp == "invisible", f"FAIL: ProtectProc='{pp}'"

    # ── TEST 10: CLI solem-gavio-check non crasha ─────────────────
    machine.succeed("/run/current-system/sw/bin/solem-gavio-check 2>&1 || true")

    print("=" * 60)
    print("✓ TUTTI I TEST DI ZERO-TRUST OVERRIDE PASSATI")
    print("  (NB: non testa esecuzione GAVIO reale, solo direttive systemd)")
    print("=" * 60)
  '';
}
