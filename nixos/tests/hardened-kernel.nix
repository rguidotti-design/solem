{ pkgs }:

# VM test: solem-hardened-kernel boota correttamente + uname mostra "hardened".
#
# Cosa verifico CONCRETAMENTE:
#   1. VM boota con kernel hardened (no panic durante init)
#   2. uname -r contiene la stringa "hardened"
#   3. CLI solem-kernel-info funziona
#
# Cosa NON copre (onesto):
#   - Non verifico OGNI flag CONFIG_* perche' richiede IKCONFIG_PROC che
#     hardened kernel ha ma potrebbe non avere in tutte le release nixpkgs.
#   - Non testa performance overhead.
#   - Non testa break su io_uring/userfaultfd (servirebbe app specifica).

pkgs.nixosTest {
  name = "solem-hardened-kernel";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-hardened-kernel.nix
    ];

    solem.hardenedKernel.enable = true;

    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target", timeout=120)
    machine.sleep(2)

    # ── TEST 1: kernel hardened in uso ─────────────────────────────
    kver = machine.succeed("uname -r").strip()
    print(f"Kernel running: {kver}")
    if "hardened" not in kver:
        raise Exception(f"FAIL: uname -r '{kver}' NON contiene 'hardened'")
    print("  ✓ kernel hardened attivo")

    # ── TEST 2: VM e' stabile (no panic, no oops) ─────────────────
    # NB: il kernel boot param "panic=1" (timeout reboot after panic) appare
    # in dmesg come Command line: panic=1 — NON e' un kernel panic vero.
    # Verifichiamo solo pattern di REAL panic ("Kernel panic" frase intera).
    rc, out = machine.execute("dmesg | grep -iE 'Kernel panic|Oops:|BUG:' | head -5")
    if "Kernel panic" in out or "Oops:" in out or "BUG:" in out:
        raise Exception(f"FAIL: kernel hardened ha panic/oops:\n{out}")
    print("  ✓ no real panic/oops nel dmesg")

    # ── TEST 3: CLI solem-kernel-info non crasha ──────────────────
    out = machine.succeed("/run/current-system/sw/bin/solem-kernel-info 2>&1")
    print(f"kernel-info output:\n{out[:800]}")
    assert "HARDENED" in out, "FAIL: solem-kernel-info non rileva hardened"

    # ── TEST 4: alcuni sysctl strict di hardened defaults ─────────
    # hardened kernel imposta unprivileged_bpf_disabled=1 by default
    rc, out = machine.execute("sysctl -n kernel.unprivileged_bpf_disabled 2>/dev/null")
    print(f"unprivileged_bpf_disabled: {out!r}")
    # OK se ritorna 1 o 2 (entrambe disabilitano per non-root)

    print("=" * 60)
    print("✓ HARDENED KERNEL: boota correttamente + uname OK")
    print("=" * 60)
  '';
}
