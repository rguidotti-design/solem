{ config, pkgs, lib, ... }:

let
  # CLI `solem` — interroga SOLEM API e mostra output formattato in console.
  # Zero deps: usa solo urllib + json (Python stdlib).
  # NB: flakeIgnore skippa check cosmetici PEP8 — manteniamo il codice
  # idiomatico (var `l` per layer è chiarissima in contesto, righe lunghe
  # OK per f-string colorate).
  solemCli = pkgs.writers.writePython3Bin "solem" {
    flakeIgnore = [
      "E501" "E741" "E226" "E231" "W291" "W293"
      "E241" "E272" "E701" "E702" "E211" "E261" "E302" "E305" "E303" "E306"
    ];
  } ''
    """solem — CLI di SOLEM. Parla con SOLEM API su localhost:8001."""
    from __future__ import annotations
    import argparse
    import json
    import sys
    import urllib.request
    import urllib.error
    from typing import Any

    API = "http://127.0.0.1:8001"
    TIMEOUT = 3.0

    # ── ANSI colors ──────────────────────────────────────────────────
    BOLD = "\x1b[1m"
    DIM = "\x1b[2m"
    GOLD = "\x1b[38;5;179m"
    BORDEAUX = "\x1b[38;5;88m"
    GREEN = "\x1b[32m"
    RED = "\x1b[31m"
    BLUE = "\x1b[34m"
    YELLOW = "\x1b[33m"
    GRAY = "\x1b[90m"
    RESET = "\x1b[0m"


    def api(path: str, method: str = "GET", data: dict | None = None) -> Any:
        url = API + path
        body = None
        headers = {"Accept": "application/json"}
        if data is not None:
            body = json.dumps(data).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                return json.loads(r.read())
        except urllib.error.URLError as e:
            print(f"{RED}solem-api irraggiungibile su {API}{RESET}", file=sys.stderr)
            print(f"{DIM}  → {e}{RESET}", file=sys.stderr)
            print(f"{DIM}  prova: sudo systemctl status solem-api{RESET}", file=sys.stderr)
            sys.exit(2)


    def tag(status: str) -> str:
        colors = {
            "ok": GREEN, "active": GREEN, "up": GREEN,
            "partial": YELLOW,
            "stub": GRAY,
            "down": RED, "err": RED,
        }
        c = colors.get(status, GRAY)
        return f"{c}{status:<8}{RESET}"


    def fmt_uptime(s: int) -> str:
        if not s:
            return "—"
        d, s = divmod(s, 86400)
        h, s = divmod(s, 3600)
        m, _ = divmod(s, 60)
        if d:
            return f"{d}d {h}h {m}m"
        if h:
            return f"{h}h {m}m"
        return f"{m}m"


    # ── Commands ─────────────────────────────────────────────────────
    def cmd_status(args):
        m = api("/solem/manifest")
        if args.json:
            print(json.dumps(m, indent=2))
            return
        rt = m.get("runtime", {})
        print()
        print(f"  {BOLD}{GOLD}{m['name']}{RESET}  {DIM}v{m['version']}  ·  step {m['step']}{RESET}")
        print()
        print(f"  {BOLD}Runtime{RESET}")
        print(f"    uptime          {fmt_uptime(rt.get('uptime_seconds', 0))}")
        print(f"    memoria         {rt.get('memory_mb', 0)} MB")
        print(f"    disco libero    {rt.get('disk_free_gb', 0)} GB")
        active = rt.get("active_services", [])
        print(f"    servizi attivi  {len(active)}  {DIM}({', '.join(active)}){RESET}")
        print()
        print(f"  {BOLD}Servizi{RESET}")
        for name, url in m.get("services", {}).items():
            print(f"    {name:<14}  {GOLD}{url}{RESET}")
        print()
        print(f"  {BOLD}Layer{RESET}")
        for l in m.get("layers", []):
            print(f"    {l['layer']}  {l['name']:<28}  {tag(l['status'])}  {DIM}{l['description']}{RESET}")
        print()


    def cmd_layers(args):
        m = api("/solem/manifest")
        if args.json:
            print(json.dumps(m.get("layers", []), indent=2))
            return
        print()
        for l in m.get("layers", []):
            print(f"  {BOLD}{l['layer']}{RESET}  {l['name']}")
            print(f"     {tag(l['status'])}  {DIM}{l['description']}{RESET}")
            print()


    def cmd_caps(args):
        r = api("/solem/capabilities")
        caps = r.get("capabilities", [])
        if args.source:
            caps = [c for c in caps if c["source"] == args.source]
        if args.json:
            print(json.dumps(caps, indent=2))
            return
        print()
        print(f"  {BOLD}Capabilities{RESET}  {DIM}({len(caps)} di {r.get('total', 0)}){RESET}")
        print()
        for c in caps:
            src = c["source"]
            src_color = GOLD if src == "solem" else (BLUE if src == "gavio" else GRAY)
            print(f"  {src_color}{src:<10}{RESET}  {c['id']:<40}  {DIM}{c['name']}{RESET}")
        print()


    def cmd_identity(args):
        i = api("/solem/identity/me")
        if args.json:
            print(json.dumps(i, indent=2))
            return
        print()
        print(f"  {BOLD}Identity{RESET}  {GRAY}[L1 stub]{RESET}")
        print(f"    user_id   {i['user_id']}")
        print(f"    nome      {BOLD}{i['name']}{RESET}")
        print(f"    email     {i['email']}")
        print(f"    ruoli     {', '.join(i['roles'])}")
        if i.get("note"):
            print(f"    {DIM}{i['note']}{RESET}")
        print()


    def cmd_pair(args):
        r = api("/solem/pairing/start", method="POST")
        if args.json:
            print(json.dumps(r, indent=2))
            return
        print()
        print(f"  {BOLD}PIN pairing generato{RESET}")
        print()
        print(f"  {BOLD}{GOLD}    {r['pin']}    {RESET}")
        print()
        print(f"  {DIM}scade:   {r['expires_at']}{RESET}")
        print(f"  {DIM}coord:   {r['coordinator_endpoint']}{RESET}")
        print()
        print(f"  {r['instructions']}")
        print()


    def cmd_devices(args):
        r = api("/solem/pairing/devices")
        devices = r.get("devices", [])
        if args.json:
            print(json.dumps(devices, indent=2))
            return
        print()
        if not devices:
            print(f"  {DIM}nessun device paired{RESET}")
            print()
            return
        print(f"  {BOLD}Device paired{RESET}  {DIM}({len(devices)}){RESET}")
        for d in devices:
            paired_at = d.get("paired_at", "")
            print(f"    {d['name']:<20}  {GOLD}{d['assigned_ip']:<18}{RESET}  {DIM}{paired_at}{RESET}")
        print()


    def cmd_version(args):
        try:
            r = api("/health")
            print(f"solem {r['version']}")
        except SystemExit:
            print("solem (api offline)")


    def cmd_panic(args):
        print(f"  {RED}{BOLD}!!! KILL SWITCH ATTIVO !!!{RESET}")
        print(f"  {DIM}Fermo tutti gli agenti AI + gavio.service...{RESET}")
        r = api("/solem/panic", method="POST", data={"reason": "cli_panic"})
        if args.json:
            print(json.dumps(r, indent=2))
            return
        for action in r.get("actions", []):
            print(f"    {GOLD}{action}{RESET}")
        print(f"  {GREEN if r.get('success') else RED}{'OK' if r.get('success') else 'PARTIAL FAILURE'}{RESET}")
        print(f"  {DIM}Recover: solem recover{RESET}")


    def cmd_recover(args):
        r = api("/solem/panic/recover", method="POST")
        if args.json:
            print(json.dumps(r, indent=2))
            return
        for action in r.get("actions", []):
            print(f"    {GOLD}{action}{RESET}")
        print(f"  {GREEN}Recovery completato{RESET}")


    # ── Main ─────────────────────────────────────────────────────────
    def main():
        p = argparse.ArgumentParser(
            prog="solem",
            description="CLI per SOLEM — l'OS AI-native",
        )
        p.add_argument("--json", action="store_true", help="output JSON puro (per AI/scripting)")
        sub = p.add_subparsers(dest="cmd")

        sub.add_parser("status", help="quadro generale del sistema")
        sub.add_parser("layers", help="stato dei 7 layer architetturali")
        cap_p = sub.add_parser("caps", help="capabilities discovered")
        cap_p.add_argument("--source", choices=["solem", "gavio", "extension"])
        sub.add_parser("identity", help="identity utente corrente (L1)")
        sub.add_parser("pair", help="genera PIN per aggiungere device alla mesh")
        sub.add_parser("devices", help="lista device paired")
        sub.add_parser("version", help="versione SOLEM")
        sub.add_parser("panic", help="KILL SWITCH — ferma tutte le AI e gavio.service")
        sub.add_parser("recover", help="recover post-panic")

        args = p.parse_args()
        cmd = args.cmd or "status"

        dispatch = {
            "status": cmd_status,
            "layers": cmd_layers,
            "caps": cmd_caps,
            "identity": cmd_identity,
            "pair": cmd_pair,
            "devices": cmd_devices,
            "version": cmd_version,
            "panic": cmd_panic,
            "recover": cmd_recover,
        }
        dispatch[cmd](args)


    if __name__ == "__main__":
        main()
  '';
in {
  # Installa `solem` globalmente — chiunque sulla VM può digitare `solem ...`
  environment.systemPackages = [ solemCli ];
}
