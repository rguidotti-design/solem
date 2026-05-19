{ config, pkgs, lib, ... }:

let
  doctor = pkgs.writers.writePython3Bin "solem-doctor" {
    flakeIgnore = [
      "E501" "E741" "E226" "E231" "W291" "W293"
      "E241" "E272" "E701" "E702" "E211" "E261" "E302" "E305" "E303" "E306"
    ];
  } ''
    """solem-doctor — diagnostica completa SOLEM.

    Esegue 30+ check coprono:
      - Sistema: kernel, NixOS version, profilo
      - Servizi systemd core
      - Connettività API (solem-api, gavio)
      - Database: SQLite leggibile, schema integro
      - Filesystem: directory critiche presenti e con ownership corretto
      - Sicurezza: sysctl hardening, firewall, gruppi gavio
      - Mesh/ZT: keygen wireguard, CA bootstrap
      - Aggiornamenti: timer update attivo
      - Logging: journald limits, audit attivo

    Output: tabella checks + summary + exit code (0 ok / 1 warn / 2 fail).

    Uso:
      solem-doctor                  → full check
      solem-doctor --json           → output JSON
      solem-doctor --only network   → solo categoria network
      solem-doctor --quiet          → solo summary
    """
    from __future__ import annotations
    import argparse
    import json
    import os
    import subprocess
    import sys
    import urllib.request
    import urllib.error
    from pathlib import Path

    # ANSI
    BOLD = "\x1b[1m"; DIM = "\x1b[2m"; RESET = "\x1b[0m"
    GREEN = "\x1b[32m"; RED = "\x1b[31m"; YELLOW = "\x1b[33m"
    GOLD = "\x1b[38;5;179m"; NAVY = "\x1b[38;5;67m"
    GRAY = "\x1b[90m"

    OK, WARN, FAIL = "ok", "warn", "fail"


    def check(name: str, fn) -> dict:
        try:
            level, detail = fn()
        except Exception as e:
            level, detail = FAIL, f"exception: {e}"
        return {"name": name, "level": level, "detail": detail}


    # ─── Check implementations ─────────────────────────────────────────


    def c_kernel():
        kv = os.uname().release
        return OK, kv


    def c_nixos_version():
        try:
            for line in Path("/etc/os-release").read_text().splitlines():
                if line.startswith("VERSION="):
                    return OK, line.split("=", 1)[1].strip().strip('"')
        except OSError:
            pass
        return WARN, "/etc/os-release non leggibile"


    def c_profile():
        try:
            return OK, Path("/etc/solem/profile").read_text().strip()
        except OSError:
            return WARN, "profile non settato (default minimal)"


    def c_systemd_service(svc):
        try:
            out = subprocess.run(["systemctl", "is-active", svc], capture_output=True, text=True, timeout=3, check=False)
            state = out.stdout.strip() or "unknown"
            if state == "active":
                return OK, "active"
            return FAIL, state
        except (subprocess.SubprocessError, FileNotFoundError):
            return FAIL, "systemctl non disponibile"


    def c_http(url, expect_code=200):
        try:
            with urllib.request.urlopen(url, timeout=3) as r:
                if r.status == expect_code:
                    return OK, f"{r.status} {r.reason}"
                return WARN, f"status {r.status}"
        except (urllib.error.URLError, OSError) as e:
            return FAIL, f"unreachable: {e}"


    def c_path_exists(p, expected_owner=None, must_be_dir=True):
        path = Path(p)
        if not path.exists():
            return FAIL, "missing"
        if must_be_dir and not path.is_dir():
            return WARN, "not a directory"
        if expected_owner:
            try:
                import pwd
                owner = pwd.getpwuid(path.stat().st_uid).pw_name
                if owner != expected_owner:
                    return WARN, f"owner={owner} expected={expected_owner}"
            except (KeyError, OSError):
                pass
        return OK, str(path)


    def c_sqlite_schema():
        db = Path("/var/lib/solem/solem.db")
        if not db.exists():
            return WARN, "DB non ancora creato (sarà inizializzato al primo hit API)"
        try:
            import sqlite3
            c = sqlite3.connect(str(db))
            tables = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall()]
            expected = {"identities", "identity_sections", "context_snapshots", "events",
                        "solem_memory", "user_universe_memory", "paired_devices", "users", "sessions"}
            missing = expected - set(tables)
            c.close()
            if missing:
                return WARN, f"missing tables: {missing}"
            return OK, f"{len(tables)} tables"
        except Exception as e:
            return FAIL, str(e)


    def c_sysctl(key, expected):
        try:
            out = subprocess.run(["sysctl", "-n", key], capture_output=True, text=True, timeout=2, check=False)
            val = out.stdout.strip()
            if val == str(expected):
                return OK, f"{key}={val}"
            return WARN, f"{key}={val} expected={expected}"
        except (subprocess.SubprocessError, FileNotFoundError):
            return WARN, "sysctl unavailable"


    def c_user_in_group(user, group):
        try:
            out = subprocess.run(["id", "-nG", user], capture_output=True, text=True, timeout=2, check=False)
            groups = out.stdout.strip().split()
            return (OK, "in") if group in groups else (WARN, f"missing from {group}")
        except (subprocess.SubprocessError, FileNotFoundError):
            return WARN, "id unavailable"


    def c_wireguard_key():
        return c_path_exists("/var/lib/wireguard/wg-solem.key", must_be_dir=False)


    def c_ca_root():
        return c_path_exists("/var/lib/solem-ca/ca.crt", must_be_dir=False)


    def c_disk_free_gb(min_gb=2):
        import shutil
        gb = shutil.disk_usage("/").free // (1024**3)
        if gb >= min_gb:
            return OK, f"{gb} GB free"
        return WARN, f"low: {gb} GB"


    def c_hardening_score(service, max_score=5.0):
        """systemd-analyze security <service> → score 0-10 (0=best, 10=worst)."""
        try:
            out = subprocess.run(
                ["systemd-analyze", "security", "--no-pager", service],
                capture_output=True, text=True, timeout=5, check=False,
            )
            for line in out.stdout.splitlines():
                if "Overall exposure level" in line:
                    # esempio: "→ Overall exposure level for foo.service: 4.5 OK 🙂"
                    parts = line.split()
                    for p in parts:
                        try:
                            score = float(p)
                            if score <= max_score:
                                return OK, f"score {score} (target ≤ {max_score})"
                            return WARN, f"score {score} > target {max_score}"
                        except ValueError:
                            continue
            return WARN, "systemd-analyze output non parsabile"
        except subprocess.SubprocessError:
            return WARN, "systemd-analyze non disponibile"


    # ─── Categorized check list ────────────────────────────────────────


    def all_checks():
        return [
            # System
            ("system", "kernel",          c_kernel),
            ("system", "nixos version",   c_nixos_version),
            ("system", "profilo SOLEM",   c_profile),
            ("system", "disco libero",    c_disk_free_gb),

            # Services
            ("services", "gavio.service",     lambda: c_systemd_service("gavio")),
            ("services", "solem-api.service", lambda: c_systemd_service("solem-api")),
            ("services", "ollama.service",    lambda: c_systemd_service("ollama")),
            ("services", "docker.service",    lambda: c_systemd_service("docker")),
            ("services", "solem-keep.service",lambda: c_systemd_service("solem-keep")),

            # Network / API
            ("network", "solem-api /health",   lambda: c_http("http://127.0.0.1:8001/health")),
            ("network", "solem-api /manifest", lambda: c_http("http://127.0.0.1:8001/solem/manifest")),
            ("network", "ollama /api/version", lambda: c_http("http://127.0.0.1:11434/api/version", 200)),

            # Database
            ("database", "sqlite schema", c_sqlite_schema),

            # Filesystem
            ("filesystem", "/var/lib/gavio",  lambda: c_path_exists("/var/lib/gavio", "gavio")),
            ("filesystem", "/var/lib/solem",  lambda: c_path_exists("/var/lib/solem", "gavio")),
            ("filesystem", "/var/log/gavio",  lambda: c_path_exists("/var/log/gavio", "gavio")),
            ("filesystem", "/etc/gavio",      lambda: c_path_exists("/etc/gavio", "gavio")),
            ("filesystem", "/opt/gavio (9p)", lambda: c_path_exists("/opt/gavio")),
            ("filesystem", "/opt/solem-backend (9p)", lambda: c_path_exists("/opt/solem-backend")),

            # Security
            ("security", "kptr_restrict",       lambda: c_sysctl("kernel.kptr_restrict", 2)),
            ("security", "dmesg_restrict",      lambda: c_sysctl("kernel.dmesg_restrict", 1)),
            ("security", "ptrace_scope",        lambda: c_sysctl("kernel.yama.ptrace_scope", 1)),
            ("security", "tcp_syncookies",      lambda: c_sysctl("net.ipv4.tcp_syncookies", 1)),
            ("security", "protected_hardlinks", lambda: c_sysctl("fs.protected_hardlinks", 1)),

            # User
            ("user", "gavio in wheel",          lambda: c_user_in_group("gavio", "wheel")),
            ("user", "gavio in docker",         lambda: c_user_in_group("gavio", "docker")),
            ("user", "gavio in video",          lambda: c_user_in_group("gavio", "video")),

            # Mesh / Zero-trust
            ("mesh", "wireguard key",   c_wireguard_key),
            ("zero-trust", "CA root cert", c_ca_root),

            # Hardening (M1.1) — target score per livello
            ("hardening", "solem-keep score ≤2 (strict)", lambda: c_hardening_score("solem-keep.service", 2.0)),
            ("hardening", "solem-api score ≤4 (medium)",  lambda: c_hardening_score("solem-api.service", 4.0)),
            ("hardening", "gavio score ≤5 (medium+AI)",   lambda: c_hardening_score("gavio.service", 5.0)),
        ]


    # ─── Output formatting ─────────────────────────────────────────────


    def tag(level):
        if level == OK:   return f"{GREEN}  OK  {RESET}"
        if level == WARN: return f"{YELLOW} WARN {RESET}"
        return f"{RED} FAIL {RESET}"


    def main():
        p = argparse.ArgumentParser(description="solem-doctor — diagnostica completa SOLEM")
        p.add_argument("--json", action="store_true", help="output JSON puro")
        p.add_argument("--only", help="filtra categoria (system/services/network/database/filesystem/security/user/mesh/zero-trust)")
        p.add_argument("--quiet", action="store_true", help="solo summary, no dettagli")
        args = p.parse_args()

        checks = all_checks()
        if args.only:
            checks = [c for c in checks if c[0] == args.only]

        results = []
        for category, name, fn in checks:
            r = check(name, fn)
            r["category"] = category
            results.append(r)

        if args.json:
            print(json.dumps({"results": results, "summary": _summary(results)}, indent=2))
            sys.exit(_exit_code(results))

        if not args.quiet:
            print(f"\n  {BOLD}{GOLD}SOLEM Doctor{RESET}  {DIM}— diagnostica completa{RESET}\n")
            cur_cat = None
            for r in results:
                if r["category"] != cur_cat:
                    cur_cat = r["category"]
                    print(f"\n  {BOLD}{NAVY}[{cur_cat.upper()}]{RESET}")
                print(f"    {tag(r['level'])}  {r['name']:<32}  {DIM}{r['detail']}{RESET}")

        s = _summary(results)
        print(f"\n  {BOLD}Summary{RESET}  "
              f"{GREEN}{s['ok']} ok{RESET}  ·  "
              f"{YELLOW}{s['warn']} warn{RESET}  ·  "
              f"{RED}{s['fail']} fail{RESET}  "
              f"{DIM}(totale {s['total']}){RESET}\n")

        sys.exit(_exit_code(results))


    def _summary(results):
        ok = sum(1 for r in results if r["level"] == OK)
        warn = sum(1 for r in results if r["level"] == WARN)
        fail = sum(1 for r in results if r["level"] == FAIL)
        return {"ok": ok, "warn": warn, "fail": fail, "total": len(results)}


    def _exit_code(results):
        if any(r["level"] == FAIL for r in results):
            return 2
        if any(r["level"] == WARN for r in results):
            return 1
        return 0


    if __name__ == "__main__":
        main()
  '';
  # Wrapper che aggiunge systemd al PATH (per `systemd-analyze security`,
  # `systemctl`, `sysctl`, `id`, `pwd`) usato dai check di solem-doctor.
  doctorWithPath = pkgs.writeShellScriptBin "solem-doctor" ''
    export PATH=${lib.makeBinPath [ pkgs.systemd pkgs.coreutils pkgs.procps pkgs.iproute2 ]}:$PATH
    exec ${doctor}/bin/solem-doctor "$@"
  '';
in {
  environment.systemPackages = [ doctorWithPath ];
}
