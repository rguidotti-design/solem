{ config, pkgs, lib, ... }:

# SOLEM VOICE WAKE — daemon wake-word detection sempre-attivo, opt-in.
#
# Single responsibility: SOLO orchestrare servizio openWakeWord. La logica
# di engine è nello script Python.
#
# Privacy: audio NON registrato. Detection inline su stream pulseaudio.
# Trigger → POST /solem/voice/wake/test (wire-up dispatch).
#
# 100% FOSS (openWakeWord Apache-2.0), 0 €.

let
  cfg = config.solem.voiceWake;

  wakeScript = pkgs.writers.writePython3 "solem-voice-wake" {
    libraries = [];
    flakeIgnore = [ "E501" "E302" "E305" "W291" "W293" ];
  } ''
    """SOLEM voice wake daemon — openWakeWord stub.

    Pre-Step 3: stub che logga ogni 60s "wake-listener alive" finché
    openWakeWord package non è disponibile in nixpkgs. Quando attivato,
    sostituisce con detection reale via pyaudio stream + Model.predict.
    """
    import json
    import os
    import time
    import urllib.request
    import urllib.error
    from pathlib import Path

    API = os.environ.get("SOLEM_API_URL", "http://127.0.0.1:8001")
    STATE = Path("/var/lib/solem/voice-wake.json")

    def heartbeat():
        msg = {"ts": time.time(), "alive": True, "engine": "openwakeword-stub"}
        print(json.dumps(msg), flush=True)

    def trigger(word: str, confidence: float):
        data = json.dumps({"word": word, "confidence": confidence}).encode()
        req = urllib.request.Request(
            f"{API}/solem/voice/wake/test?word={word}",
            data=data, method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=2) as r:
                r.read()
        except urllib.error.URLError as e:
            print(json.dumps({"ts": time.time(), "trigger_error": str(e)}), flush=True)

    def main():
        STATE.parent.mkdir(parents=True, exist_ok=True)
        print(json.dumps({"ts": time.time(), "starting": True, "stub": True}), flush=True)
        while True:
            heartbeat()
            time.sleep(60)

    if __name__ == "__main__":
        main()
  '';
in {
  options.solem.voiceWake = {
    enable = lib.mkEnableOption "Wake-word detection daemon (stub openWakeWord)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "gavio";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/solem 0755 ${cfg.user} users - -"
    ];

    systemd.services.solem-voice-wake = {
      description = "SOLEM — wake-word detection daemon";
      after = [ "solem-api.service" "sound.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = wakeScript;
        Restart = "on-failure";
        RestartSec = "5s";
        Nice = 10;

        # Hardening: audio-only, niente network in ingresso
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/solem" ];
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" ];
        SupplementaryGroups = [ "audio" ];
      };
    };
  };
}
