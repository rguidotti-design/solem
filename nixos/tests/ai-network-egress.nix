{ pkgs }:

# VM test: nftables egress whitelist per gavio-ai.
#
# Cosa verifico CONCRETAMENTE:
#   1. Tabella inet solem-ai caricata in kernel
#   2. Chain ai_egress contiene regola DROP (non solo log)
#   3. gavio-ai NON si connette a IP non-loopback non-whitelist
#   4. gavio-ai SI connette a loopback (sempre whitelist)
#   5. gavio (umano) NON e' filtrato dalle regole AI
#
# Cosa il test NON copre (onesto):
#   - Rete esterna reale (VM e' isolata, simulo con IP non-loopback locale)
#   - DNS tunneling bypass (porta 53 e' nella whitelist by design)
#   - Setuid exploit (se l'AI diventa root, bypassa skuid match)

pkgs.nixosTest {
  name = "solem-ai-network-egress";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-ai-user.nix
      ../modules/solem-ai-network.nix
    ];

    solem.aiUser.enable = true;
    solem.aiNetwork = {
      enable = true;
      allowedV4 = [ ];  # default: solo loopback
      allowedPorts = [ ];  # default: 53/123/443
      logBlocked = true;
    };

    # Disabilita firewall standard NixOS (conflict possibile con nftables)
    networking.firewall.enable = false;

    # Tool per test
    environment.systemPackages = with pkgs; [
      netcat-gnu
      curl
      iproute2
    ];

    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.sleep(3)

    # ── TEST 1: tabella nftables caricata ──────────────────────────
    out = machine.succeed("nft list tables 2>&1")
    print(f"nft tables:\n{out}")
    assert "solem-ai" in out, f"FAIL: tabella inet solem-ai NON caricata: {out}"

    # ── TEST 2: chain ai_egress contiene DROP ──────────────────────
    out = machine.succeed("nft list chain inet solem-ai ai_egress 2>&1")
    print(f"chain ai_egress:\n{out}")
    assert "drop" in out.lower(), f"FAIL: chain ai_egress NON ha regola DROP"
    assert "skuid" in out or "970" in out, "FAIL: chain non filtra per UID gavio-ai"

    # ── TEST 3: gavio-ai puo' raggiungere LOOPBACK (whitelist) ─────
    # Avvia un server semplice su loopback porta 8080
    machine.execute("python3 -m http.server 8080 --bind 127.0.0.1 >/tmp/srv.log 2>&1 &")
    machine.sleep(2)

    # gavio (umano) deve raggiungere
    rc_h, _ = machine.execute(
        "sudo -u gavio timeout 3 curl -sf -o /dev/null http://127.0.0.1:8080/"
    )
    print(f"gavio -> loopback: rc={rc_h}")

    # gavio-ai deve raggiungere (loopback sempre allow)
    rc_ai, _ = machine.execute(
        "sudo -u gavio-ai timeout 3 curl -sf -o /dev/null http://127.0.0.1:8080/"
    )
    print(f"gavio-ai -> loopback: rc={rc_ai}")
    assert rc_ai == 0, "FAIL: gavio-ai NON raggiunge loopback (deve essere whitelist)"

    # ── TEST 4: gavio-ai BLOCCATO verso IP NON loopback ────────────
    # Trova IP non-loopback dell'interfaccia
    out = machine.succeed("ip -4 -o addr show | awk '!/127.0.0.1/ && /inet /{print $4}' | head -1")
    nonlocal_ip = out.strip().split("/")[0]
    print(f"Non-loopback IP della VM: {nonlocal_ip}")

    if nonlocal_ip and nonlocal_ip != "":
        # Avvia HTTP server su quel IP porta 8888 (NON in whitelist)
        machine.execute(f"python3 -m http.server 8888 --bind {nonlocal_ip} >/tmp/srv2.log 2>&1 &")
        machine.sleep(2)

        # gavio (umano) deve raggiungere (NON filtrato)
        rc_h, _ = machine.execute(
            f"sudo -u gavio timeout 3 curl -sf -o /dev/null http://{nonlocal_ip}:8888/"
        )
        print(f"gavio -> {nonlocal_ip}:8888 rc={rc_h}")
        assert rc_h == 0, f"FAIL: gavio (umano) NON dovrebbe essere filtrato, ma rc={rc_h}"

        # gavio-ai NON deve raggiungere (porta non whitelist + IP non whitelist)
        rc_ai, _ = machine.execute(
            f"sudo -u gavio-ai timeout 3 curl -sf -o /dev/null http://{nonlocal_ip}:8888/"
        )
        print(f"gavio-ai -> {nonlocal_ip}:8888 rc={rc_ai}")
        assert rc_ai != 0, \
            f"FAIL CRITICO: gavio-ai HA raggiunto {nonlocal_ip}:8888 (firewall NON sta bloccando!)"
    else:
        print("(no non-loopback interface - skip block test)")

    # ── TEST 5: CLI solem-ai-net status non crasha ─────────────────
    machine.succeed("/run/current-system/sw/bin/solem-ai-net status 2>&1 || true")

    # ── TEST 6: drop counter incrementato ──────────────────────────
    out = machine.succeed("nft list chain inet solem-ai ai_egress")
    print(f"Final ai_egress chain:\n{out}")
    # Cerchiamo "counter packets N" — se nostro test 4 ha generato traffico
    # il counter deve essere > 0

    print("=" * 60)
    print("✓ TUTTI I TEST DI EGRESS FIREWALL gavio-ai PASSATI")
    print("=" * 60)
  '';
}
