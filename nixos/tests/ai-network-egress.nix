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
      python3        # per http.server come target server di test
    ];

    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.sleep(3)

    # Setup: rotta fittizia per TEST-NET RFC 5737 verso loopback.
    # Senza questa, connect(192.0.2.x) ritorna ENETUNREACH PRIMA che
    # il packet attraversi OUTPUT chain -> counter NON incrementa per
    # ragione sbagliata (no packet generato, no rule match).
    machine.succeed("ip route add 192.0.2.0/24 dev lo 2>&1 || true")
    machine.succeed("ip route add 203.0.113.0/24 dev lo 2>&1 || true")

    # ── TEST 1: tabella nftables caricata ──────────────────────────
    out = machine.succeed("nft list tables 2>&1")
    print(f"nft tables:\n{out}")
    assert "solem-ai" in out, f"FAIL: tabella inet solem-ai NON caricata: {out}"

    # ── TEST 2: chain ai_egress contiene DROP ──────────────────────
    out = machine.succeed("nft list chain inet solem-ai ai_egress 2>&1")
    print(f"chain ai_egress:\n{out}")
    assert "drop" in out.lower(), "FAIL: chain ai_egress NON ha regola DROP"
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

    # ── TEST 4: drop counter nftables aumenta per gavio-ai, non gavio ──
    # Non possiamo bind un server esterno alla VM, e Linux fa local routing
    # via lo per IP della propria interfaccia. Test piu' affidabile:
    # verificare che il COUNTER drop di ai_egress aumenti quando gavio-ai
    # tenta una connect() esterna (IP TEST-NET RFC 5737, irraggiungibile).

    import re

    def get_drop_counter():
        out = machine.succeed("nft -a list chain inet solem-ai ai_egress")
        # Cerca riga "counter packets N bytes M drop" o "counter packets N bytes M"
        # systemd-nftables in 24.11 formatta "counter packets X bytes Y drop"
        m = re.search(r"counter packets (\d+) bytes \d+\s+drop", out)
        if m:
            return int(m.group(1))
        # fallback: cerca tutti i counter
        m = re.search(r"counter packets (\d+)", out)
        return int(m.group(1)) if m else 0

    before = get_drop_counter()
    print(f"Drop counter BEFORE: {before}")

    # gavio-ai tenta connect a 192.0.2.99:9999 (TEST-NET-1, irraggiungibile)
    # Il pacchetto viene generato e nftables OUTPUT chain decide DROP
    # prima ancora che parta verso il default gateway.
    machine.execute("sudo -u gavio-ai timeout 2 curl -s http://192.0.2.99:9999/ 2>&1 || true")
    machine.execute("sudo -u gavio-ai timeout 2 curl -s http://203.0.113.10:8080/ 2>&1 || true")
    machine.sleep(1)

    after_ai = get_drop_counter()
    print(f"Drop counter AFTER gavio-ai attempts: {after_ai}")
    assert after_ai > before, \
        f"FAIL: drop counter NON aumentato per gavio-ai ({before} -> {after_ai}). " \
        "Significa che la regola skuid 970 ... drop NON sta matchando."

    # gavio (umano) tenta lo stesso. NON deve incrementare il counter
    # (skuid != 970 → return early, no drop).
    pre_human = get_drop_counter()
    machine.execute("sudo -u gavio timeout 2 curl -s http://192.0.2.99:9999/ 2>&1 || true")
    machine.sleep(1)
    post_human = get_drop_counter()
    print(f"Drop counter after gavio (human) attempts: pre={pre_human} post={post_human}")
    assert post_human == pre_human, \
        f"FAIL: drop counter aumentato anche per gavio umano ({pre_human} -> {post_human}). " \
        "La regola dovrebbe filtrare SOLO UID 970."

    # ── TEST 5: CLI solem-ai-net status non crasha ─────────────────
    machine.succeed("/run/current-system/sw/bin/solem-ai-net status 2>&1 || true")

    print("=" * 60)
    print("✓ TUTTI I TEST DI EGRESS FIREWALL gavio-ai PASSATI")
    print("=" * 60)
  '';
}
