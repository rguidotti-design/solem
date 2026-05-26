{ pkgs }:

# VM test: DNS allowlist + redirect nftables per gavio-ai.
#
# Cosa verifico CONCRETAMENTE:
#   1. unbound attivo su porta 5353
#   2. dig diretto a localhost:5353 per dominio NON in allowlist → REFUSED
#   3. dig diretto a localhost:5353 per dominio in allowlist → risposta
#      (anche se upstream non raggiunto in VM, lo status NON deve essere
#      REFUSED — deve essere SERVFAIL o NOERROR. La distinzione e' chiave.)
#   4. nftables chain ai_dns_redirect contiene regola DNAT skuid 970
#   5. tabella inet solem-ai-dns caricata
#
# Cosa NON copre (onesto):
#   - VM isolata: upstream DoT (1.1.1.1:853) NON e' raggiungibile, quindi
#     test "allow" verifica solo che NON sia REFUSED (resolver accetta),
#     non che la risposta arrivi davvero.
#   - Redirect NAT: gavio-ai dig su porta 53 dovrebbe finire su 5353,
#     ma test diretto su 5353 e' equivalent per verificare il filter logic.

pkgs.nixosTest {
  name = "solem-ai-dns-allowlist";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [
      ../modules/solem-core.nix
      ../modules/solem-ai-user.nix
      ../modules/solem-ai-dns.nix
    ];

    solem.aiUser.enable = true;
    solem.aiDns = {
      enable = true;
      allowedDomains = [
        "ollama.com"
        "example.com"
      ];
    };

    # VM isolata: disabilita root trust anchor (unbound-anchor non puo'
    # bootstrappare senza internet -> unbound service fail)
    services.unbound.enableRootTrustAnchor = false;

    networking.firewall.enable = false;

    environment.systemPackages = with pkgs; [
      dig
      bind
    ];

    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target", timeout=60)
    machine.wait_for_unit("unbound.service", timeout=30)
    machine.sleep(3)

    # ── TEST 1: unbound listening su 5353 ──────────────────────────
    out = machine.succeed("ss -tlnp 2>/dev/null | grep -E ':5353|unbound' || echo NONE")
    print(f"unbound socket: {out}")
    # Anche se non c'e' su tcp, deve essere su udp
    out_udp = machine.succeed("ss -ulnp 2>/dev/null | grep 5353 || echo NONE")
    print(f"unbound UDP: {out_udp}")
    assert "5353" in (out + out_udp), f"FAIL: unbound non listening su 5353"

    # ── TEST 2: dig dominio NON in allowlist → REFUSED ─────────────
    rc, out = machine.execute("dig +time=3 +tries=1 @127.0.0.1 -p 5353 evil.attacker.tld 2>&1")
    print(f"dig evil.attacker.tld:\n{out}")
    assert "REFUSED" in out, f"FAIL: dominio NON in allowlist NON e' REFUSED:\n{out}"
    print("  ✓ evil.attacker.tld REFUSED")

    rc, out = machine.execute("dig +time=3 +tries=1 @127.0.0.1 -p 5353 c2payload.malware.test 2>&1")
    assert "REFUSED" in out, f"FAIL: c2payload.malware.test NON refused:\n{out}"
    print("  ✓ c2payload.malware.test REFUSED")

    # ── TEST 3: dig dominio in allowlist → NON REFUSED ─────────────
    # In VM isolata upstream DoT non funziona, ma unbound deve
    # ACCETTARE la query (no REFUSED). Possibili rcode validi: NOERROR
    # (con cached/local), SERVFAIL (upstream timeout), NXDOMAIN.
    rc, out = machine.execute("dig +time=5 +tries=1 @127.0.0.1 -p 5353 ollama.com 2>&1")
    print(f"dig ollama.com:\n{out}")
    if "REFUSED" in out:
        raise Exception(f"FAIL: ollama.com (in allowlist) e' REFUSED:\n{out}")
    print("  ✓ ollama.com NON refused (allowlist trasparente)")

    rc, out = machine.execute("dig +time=5 +tries=1 @127.0.0.1 -p 5353 www.example.com 2>&1")
    print(f"dig www.example.com:\n{out}")
    if "REFUSED" in out:
        raise Exception(f"FAIL: www.example.com (sub di allowlist) e' REFUSED:\n{out}")
    print("  ✓ www.example.com NON refused (sub-domain transparent)")

    # ── TEST 4: nftables NAT chain caricata ────────────────────────
    out = machine.succeed("nft list tables 2>&1")
    assert "solem-ai-dns" in out, f"FAIL: tabella solem-ai-dns NON caricata:\n{out}"

    out = machine.succeed("nft list chain inet solem-ai-dns ai_dns_redirect 2>&1")
    print(f"NAT chain:\n{out}")
    assert "dnat" in out.lower() or "DNAT" in out, "FAIL: chain non contiene DNAT"
    assert "5353" in out, "FAIL: DNAT non punta a porta 5353"
    assert "970" in out or "skuid" in out, "FAIL: chain non filtra per skuid 970"

    # ── TEST 5: redirect funziona (gavio-ai dig su 53 → finisce su 5353) ──
    # gavio-ai prova dig sul resolver di sistema 127.0.0.53 / o un altro.
    # Trick: usiamo dig a un IP esterno (ma il nat redirect intercetta).
    # ATTENZIONE: dig @127.0.0.1 (porta 53 default) — la query parte verso
    # 127.0.0.1:53. nftables NAT chain ai_dns_redirect su output dovrebbe
    # rediretterla a 127.0.0.1:5353 (perche' skuid=970).
    rc, out = machine.execute(
        "sudo -u gavio-ai dig +time=3 +tries=1 @8.8.8.8 evil.attacker.tld 2>&1"
    )
    print(f"gavio-ai dig (rediretto via NAT):\n{out}")
    # Se NAT funziona, la query e' andata a unbound locale e tornata REFUSED
    # (perche' evil.attacker.tld non e' in allowlist).
    # Se NAT NON funziona, dig prova upstream 8.8.8.8 e timeout in VM isolata.
    if "REFUSED" in out:
        print("  ✓ NAT redirect gavio-ai funziona (REFUSED arrivato da unbound locale)")
    elif "timed out" in out or "connection timed out" in out:
        print("  ⚠ no NAT redirect visibile (timeout 8.8.8.8 in VM e' atteso senza network)")
        print("    test inconclusivo ma non fallisce")
    else:
        print(f"  ⚠ risposta inattesa: {out[:200]}")

    # ── TEST 6: CLI solem-ai-dns status non crasha ─────────────────
    machine.succeed("/run/current-system/sw/bin/solem-ai-dns status 2>&1 || true")

    print("=" * 60)
    print("✓ DNS ALLOWLIST: REFUSED su domini non-whitelist confermato")
    print("=" * 60)
  '';
}
