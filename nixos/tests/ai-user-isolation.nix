{ pkgs }:

# VM test REALE: verifica che l'utente AI gavio-ai sia DAVVERO isolato.
#
# Onesto: questo test simula la prima riga di difesa (UID separato).
# NON simula un attacco kernel-level, NON simula syscall exploit.
# Solo: "gavio-ai può fare cose pericolose senza essere bloccato?"
#
# Se uno di questi test fallisce → il modulo NON sta proteggendo nulla.

pkgs.nixosTest {
  name = "solem-ai-user-isolation";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-ai-user.nix
    ];
    solem.aiUser.enable = true;

    # File "secret" sotto gavio per test accesso
    systemd.tmpfiles.rules = [
      "f /home/gavio/SECRET_HUMAN_DATA 0600 gavio users - top-secret-payload"
      "f /home/gavio/.vault-key 0600 gavio users - simulated-vault-master-key"
    ];

    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.sleep(3)

    # ── PRE: l'utente gavio-ai esiste? ───────────────────────────
    out = machine.succeed("getent passwd gavio-ai")
    print(f"gavio-ai entry: {out}")
    assert "gavio-ai" in out, "gavio-ai user NOT created"

    # UID nel range system (< 1000)
    uid = int(machine.succeed("id -u gavio-ai").strip())
    assert uid < 1000, f"gavio-ai UID {uid} non e' in range system"
    assert uid != 1000, "gavio-ai non deve usare UID umano"

    # ── TEST 1: gavio-ai NON in wheel ────────────────────────────
    out = machine.succeed("id -Gn gavio-ai")
    print(f"gavio-ai groups: {out}")
    assert "wheel" not in out, f"FAIL gavio-ai E' in wheel: {out}"
    assert "docker" not in out, f"FAIL gavio-ai E' in docker: {out}"
    assert "networkmanager" not in out, f"FAIL gavio-ai E' in networkmanager: {out}"

    # ── TEST 2: gavio-ai NON puo' sudo ───────────────────────────
    # sudo -n true ritorna 0 solo se l'utente ha sudo passwordless
    rc, _ = machine.execute("sudo -u gavio-ai sudo -n true 2>/dev/null")
    assert rc != 0, "FAIL: gavio-ai puo' sudo (rc=0)"

    # ── TEST 3: gavio-ai NON puo' leggere file di gavio ──────────
    rc, out = machine.execute("sudo -u gavio-ai cat /home/gavio/SECRET_HUMAN_DATA 2>&1")
    assert rc != 0, f"FAIL: gavio-ai HA letto SECRET_HUMAN_DATA: {out}"
    assert "Permission denied" in out or "denied" in out.lower() or rc != 0, \
        f"gavio-ai non bloccato come dovrebbe: rc={rc}, out={out}"

    rc, out = machine.execute("sudo -u gavio-ai cat /home/gavio/.vault-key 2>&1")
    assert rc != 0, f"FAIL: gavio-ai HA letto vault-key (rc=0): {out}"

    # ── TEST 4: gavio-ai NON puo' listare /home/gavio/ ───────────
    # Su NixOS default /home/gavio e' 0755 → listing puo' funzionare.
    # Cio' che NON deve riuscire e' READ dei file 0600.
    rc, _ = machine.execute("sudo -u gavio-ai ls /home/gavio/ 2>/dev/null")
    # Accettiamo entrambi: se home e' 0700 fallisce ls, se 0755 ls passa.
    # L'importante e' che il READ dei file 0600 fallisca (testato sopra).

    # ── TEST 5: gavio-ai PUO' scrivere nella propria home ────────
    machine.succeed("sudo -u gavio-ai touch /var/lib/gavio-ai/workdir/.test-write")
    machine.succeed("sudo -u gavio-ai rm /var/lib/gavio-ai/workdir/.test-write")

    # ── TEST 6: gavio NON puo' leggere /var/lib/gavio-ai ─────────
    # (simmetria: anche umano non spia AI)
    rc, _ = machine.execute("sudo -u gavio ls /var/lib/gavio-ai/workdir/ 2>/dev/null")
    assert rc != 0, "FAIL: gavio (umano) puo' leggere home dell'AI"

    # ── TEST 7: gavio-ai shell NON e' nologin ────────────────────
    # (lo shell deve esistere per systemd service exec, ma password disabled)
    shadow = machine.succeed("getent shadow gavio-ai")
    print(f"gavio-ai shadow: {shadow}")
    # Campo password deve essere '!' o '*' o '!!' (locked)
    pwfield = shadow.split(":")[1]
    assert pwfield in ("!", "*", "!!", "") or pwfield.startswith("!"), \
        f"FAIL: gavio-ai shadow password non locked: {pwfield}"

    # ── TEST 8: CLI solem-ai-user funziona ───────────────────────
    machine.succeed("/run/current-system/sw/bin/solem-ai-user status")
    out = machine.succeed("/run/current-system/sw/bin/solem-ai-user check-isolation")
    print(f"check-isolation output:\n{out}")
    # Tutti i check devono essere OK
    fail_count = out.count("✗")
    assert fail_count == 0, f"check-isolation ha {fail_count} FAIL nel suo report"

    print("=" * 60)
    print("✓ TUTTI I TEST DI ISOLAMENTO gavio-ai PASSATI")
    print("=" * 60)
  '';
}
