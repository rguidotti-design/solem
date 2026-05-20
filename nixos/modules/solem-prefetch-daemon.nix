{ config, pkgs, lib, ... }:

# SOLEM PREFETCH DAEMON — esegue le suggested_actions di /prefetch/plan.
#
# Single responsibility: SOLO timer systemd che ogni 15 min chiama
# /solem/prefetch/plan e ESEGUE comandi sicuri (ollama pull, prewarm app).
# Niente decisione: l'analisi statistica è in layers/prefetch.py.
#
# Allowlist comandi: ollama pull, systemctl --user start (solo *.service
# whitelisted), curl prewarm. NIENTE shell arbitraria.

let
  cfg = config.solem.prefetchDaemon;

  prefetchScript = pkgs.writers.writePython3 "solem-prefetch-runner" {
    flakeIgnore = [ "E501" "E302" "E305" "W291" "W293" ];
  } ''
    """SOLEM prefetch runner — esegue plan da /solem/prefetch/plan.

    Allowlist:
      - ollama pull <model>  (solo se model regex valida)
      - systemctl --user start <svc>.service (whitelist)
      - (NO eval, NO arbitrary shell)
    """
    import json
    import os
    import re
    import subprocess
    import sys
    import urllib.request
    import urllib.error

    API = os.environ.get("SOLEM_API_URL", "http://127.0.0.1:8001")
    HORIZON_MIN = int(os.environ.get("SOLEM_PREFETCH_HORIZON_MIN", "60"))
    MIN_SCORE = float(os.environ.get("SOLEM_PREFETCH_MIN_SCORE", "0.25"))

    # Whitelist servizi che possono essere pre-warmed (NON arbitrari)
    WHITELIST_SERVICES = {
        "logseq", "geary", "vscodium", "firefox", "thunderbird",
    }

    OLLAMA_MODEL_RX = re.compile(r"^[a-zA-Z0-9._\-:]+$")


    def http_get_json(url):
        with urllib.request.urlopen(url, timeout=5) as r:
            return json.loads(r.read())


    def run_ollama_pull(model):
        if not OLLAMA_MODEL_RX.match(model):
            return f"skip-invalid-model: {model}"
        try:
            r = subprocess.run(["ollama", "pull", model],
                               capture_output=True, text=True, timeout=600, check=False)
            return f"ollama pull {model}: rc={r.returncode}"
        except (FileNotFoundError, subprocess.SubprocessError) as e:
            return f"ollama pull {model}: error {e}"


    def run_systemctl_start(svc):
        if svc not in WHITELIST_SERVICES:
            return f"skip-not-whitelisted: {svc}"
        try:
            r = subprocess.run(
                ["systemctl", "--user", "start", f"{svc}.service"],
                capture_output=True, text=True, timeout=10, check=False,
            )
            return f"systemctl --user start {svc}: rc={r.returncode}"
        except (FileNotFoundError, subprocess.SubprocessError) as e:
            return f"systemctl start {svc}: error {e}"


    def main():
        try:
            plan = http_get_json(f"{API}/solem/prefetch/plan?horizon_min={HORIZON_MIN}")
        except (urllib.error.URLError, OSError) as e:
            print(json.dumps({"event": "fetch_fail", "err": str(e)}), flush=True)
            sys.exit(0)

        executed = []
        for pred in plan.get("predictions", []):
            if pred["score"] < MIN_SCORE:
                continue
            tag = pred["tag"]
            if tag.startswith("ollama:"):
                executed.append(run_ollama_pull(tag.split(":", 1)[1]))
            elif tag.startswith("app:"):
                executed.append(run_systemctl_start(tag.split(":", 1)[1]))

        print(json.dumps({
            "event": "prefetch_done",
            "predictions_total": len(plan.get("predictions", [])),
            "executed": executed,
        }), flush=True)


    if __name__ == "__main__":
        main()
  '';
in {
  options.solem.prefetchDaemon = {
    enable = lib.mkEnableOption "Daemon che esegue prefetch plan ogni 15 min (allowlist)";

    horizonMin = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Orizzonte predizione (minuti nel futuro)";
    };

    minScore = lib.mkOption {
      type = lib.types.float;
      default = 0.25;
      description = "Soglia minima score per eseguire l'azione (0..1)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.solem-prefetch = {
      description = "SOLEM — prefetch runner (esegue plan AI)";
      environment = {
        SOLEM_API_URL = "http://127.0.0.1:8001";
        SOLEM_PREFETCH_HORIZON_MIN = toString cfg.horizonMin;
        SOLEM_PREFETCH_MIN_SCORE = toString cfg.minScore;
      };
      path = with pkgs; [ ollama systemd curl ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = prefetchScript;
      };
    };

    systemd.user.timers.solem-prefetch = {
      description = "Trigger prefetch ogni 15 min";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "15min";
        Persistent = true;
      };
    };
  };
}
