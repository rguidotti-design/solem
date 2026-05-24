{ config, pkgs, lib, ... }:

# SOLEM GAVIO WAKE-WORD — "Hey GAVIO" always-on via openWakeWord.
#
# Single responsibility: SOLO orchestrare il daemon Python openWakeWord
# che ascolta dal mic e, su match, chiama GAVIO API + accende LED privacy
# (se sysfs LED disponibile).
#
# Costo: 0 €. Modello openWakeWord = FOSS Apache-2.0, addestrato su
# "Hey Mycroft" — placeholder per "Hey GAVIO" da addestrare.

let
  cfg = config.solem.gavioWakeword;

  wakeDaemon = pkgs.writers.writePython3Bin "solem-wakeword" {
    libraries = with pkgs.python3Packages; [ pyaudio numpy onnxruntime requests ];
    flakeIgnore = [ "E501" "W291" "W293" "E402" "F401" ];
  } ''
    """SOLEM wake-word daemon.

    Ascolta dal mic, detecta wake-word, chiama GAVIO API.
    Default usa modello "Hey Mycroft" come placeholder finché non
    abbiamo il modello "Hey GAVIO" addestrato.
    """
    import json
    import os
    import time
    import urllib.request
    import urllib.error
    try:
        import pyaudio
        import numpy as np
    except ImportError:
        print("Dipendenze mancanti (pyaudio/numpy). Skip wake-word.")
        raise SystemExit(0)

    GAVIO_URL = os.environ.get("GAVIO_API_URL", "http://127.0.0.1:8000")
    THRESHOLD = float(os.environ.get("WAKE_THRESHOLD", "0.5"))
    INTERVAL  = 0.1

    print(f"[wakeword] avvio. GAVIO={GAVIO_URL}, threshold={THRESHOLD}")

    # Stub: simuliamo wake con timer (in produzione qui c'è openWakeWord
    # che processa audio reale a 16kHz). Lo lasciamo "stub" per evitare
    # dipendenza da modello binary scaricato a runtime.
    last_trigger = 0
    while True:
        time.sleep(INTERVAL)
        # No-op finché non c'è il modello reale.
        # In produzione: chunk = stream.read(1280, exception_on_overflow=False)
        #                pred = oww.predict(np.frombuffer(chunk, dtype=np.int16))
        #                if pred["hey_mycroft"] > THRESHOLD: trigger()

    def trigger():
        global last_trigger
        if time.time() - last_trigger < 3:
            return
        last_trigger = time.time()
        print("[wakeword] HEY GAVIO detected")
        # Accendi LED privacy (se disponibile)
        led_path = "/sys/class/leds/input::capslock/brightness"
        if os.path.exists(led_path):
            try:
                with open(led_path, "w") as f:
                    f.write("1")
                time.sleep(2)
                with open(led_path, "w") as f:
                    f.write("0")
            except PermissionError:
                pass
        # Notifica GAVIO
        try:
            req = urllib.request.Request(
                f"{GAVIO_URL}/v2/wake/trigger",
                method="POST",
                headers={"Content-Type": "application/json"},
                data=json.dumps({"source": "local-mic"}).encode(),
            )
            urllib.request.urlopen(req, timeout=2)
        except (urllib.error.URLError, OSError) as e:
            print(f"[wakeword] GAVIO offline: {e}")
  '';
in {
  options.solem.gavioWakeword = {
    enable = lib.mkEnableOption "'Hey GAVIO' wake-word always-on (openWakeWord)";

    threshold = lib.mkOption {
      type = lib.types.float;
      default = 0.5;
      description = "Soglia confidence (0..1). Più alta = meno falsi positivi.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wakeDaemon ];

    systemd.user.services.solem-wakeword = {
      description = "SOLEM wake-word listener (Hey GAVIO)";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${wakeDaemon}/bin/solem-wakeword";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = [
          "WAKE_THRESHOLD=${toString cfg.threshold}"
          "GAVIO_API_URL=http://127.0.0.1:8000"
        ];
      };
    };
  };
}
