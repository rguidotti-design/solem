{ config, pkgs, lib, ... }:

let
  # Dipendenze sistema richieste da GAVIO (vedi audit del codice esistente).
  # Sono installate globalmente così l'AI può invocarle via subprocess.
  gavioSystemDeps = with pkgs; [
    # Core runtime
    python312
    uv                 # gestore venv (sostituisce pip, 10× più veloce)
    git

    # OCR + audio + browser automation (richiesti da GAVIO)
    # NB: pkgs.chromium è self-contained (rpath patchato) — niente shared
    # libs da listare a parte. Playwright lo usa via env var sotto.
    tesseract
    ffmpeg
    chromium

    # Networking / debug
    iproute2 dnsutils netcat curl wget jq
  ];
in {
  # Pacchetti sistema disponibili in PATH per gavio
  environment.systemPackages = gavioSystemDeps;

  # Variabili globali: Playwright usa Chromium di sistema (NixOS) anziché
  # scaricarne uno proprio (che non funzionerebbe per via dei link patchelf)
  environment.variables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
  };

  # ── OLLAMA (LLM locale per fallback offline) ────────────────────────
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
    acceleration = false;   # in VM: solo CPU. Sul Beelink+GPU futuro: "cuda"
    # Modelli auto-scaricati al primo boot via systemd job dedicato sotto
    # (services.ollama.loadModels è async ma non aspetta il pull → spostato
    # in systemd service che logga progresso)
  };

  # Pre-pull modelli per Multi-AI registry (gavio + coder + researcher + writer)
  # + nomic-embed-text per L5 vector search.
  # Scarica in background al primo boot (~15-20GB tot, una volta).
  systemd.services.solem-ollama-prepull = {
    description = "SOLEM — pre-pull modelli Ollama per Multi-AI";
    after = [ "ollama.service" "network-online.target" ];
    wants = [ "ollama.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "ollama";
      Nice = 19;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "0";   # download può durare ore
    };

    script = ''
      MODELS="llama3.2:3b qwen2.5-coder:7b phi3:medium nomic-embed-text"
      # Skip se file marker esiste (idempotente)
      MARKER=/var/lib/ollama/.solem-models-pulled
      if [ -f "$MARKER" ]; then
        echo "[ollama-prepull] modelli già scaricati (marker $MARKER)"
        exit 0
      fi

      # Wait ollama API ready
      for i in $(seq 1 30); do
        if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:11434/api/version > /dev/null 2>&1; then
          break
        fi
        sleep 2
      done

      for m in $MODELS; do
        echo "[ollama-prepull] pulling $m..."
        ${pkgs.curl}/bin/curl -fsS -X POST http://127.0.0.1:11434/api/pull \
          -d "{\"name\":\"$m\",\"stream\":false}" \
          -o /tmp/ollama-pull-$m.log || echo "[ollama-prepull] WARN: $m fallito (continua)"
      done

      touch "$MARKER"
      echo "[ollama-prepull] tutti i modelli scaricati."
    '';
  };

  # ── DOCKER (richiesto se GAVIO_ENABLE_DOCKER=1) ─────────────────────
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    autoPrune.dates = "weekly";
  };

  # ── ENV FILE PER GAVIO ──────────────────────────────────────────────
  # Esempio sempre presente; il file reale va creato dall'utente.
  environment.etc."gavio/env.example" = {
    mode = "0644";
    text = ''
      # File env per GAVIO — copia in /etc/gavio/env e compila.
      # I valori MAI committarli in git.
      #
      # SOLEM è 100% gratis: configurazione default usa SOLO Ollama locale.
      # Groq è opzionale (free tier ~14K richieste/giorno, no carta richiesta).
      # Niente provider a pagamento di default.

      # ── LLM (Ollama locale = default, gratis illimitato) ──
      LLM_BACKEND=auto
      OLLAMA_HOST=http://127.0.0.1:11434
      OLLAMA_MODEL=llama3.2:3b

      # ── Groq (opzionale, FREE TIER — solo se vuoi velocità extra) ──
      # Registrati gratis su console.groq.com (no carta richiesta)
      # GROQ_API_KEY=

      # ── Supabase (opzionale Step 2+, free tier sufficiente) ──
      # 500MB DB + 50K Auth users gratis, no carta richiesta
      # SUPABASE_URL=
      # SUPABASE_SERVICE_KEY=
      # SUPABASE_ANON_KEY=

      # ── GAVIO core ──
      GAVIO_HTTPS=0
      GAVIO_FOUNDER_EMAIL=guidottrbn@gmail.com
      GAVIO_ENABLE_DOCKER=0

      # ── NIENTE provider a pagamento ──
      # Non aggiungere chiavi Claude/OpenAI/Gemini paid — SOLEM è 100% gratis.
    '';
  };

  # ── SERVIZIO GAVIO ──────────────────────────────────────────────────
  # Strategia bootstrap:
  #   1. ExecStartPre crea/aggiorna venv via uv
  #   2. Installa deps da pyproject.toml / requirements.txt / fallback
  #   3. ExecStart avvia server.py (entrypoint identificato da audit)
  systemd.services.gavio = {
    description = "GAVIO — AI personale di Ruben Guidotti";
    after = [ "network-online.target" "ollama.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "gavio";
      Group = "users";
      WorkingDirectory = "/opt/gavio";

      # "-" davanti al path: se il file manca, non fallire (utile primo boot)
      EnvironmentFile = "-/etc/gavio/env";

      # Bootstrap venv + deps
      ExecStartPre = pkgs.writeShellScript "gavio-bootstrap" ''
        set -euo pipefail
        export PATH=${lib.makeBinPath gavioSystemDeps}:$PATH
        cd /opt/gavio

        VENV=/var/lib/gavio/venv
        if [ ! -d "$VENV" ]; then
          echo "[gavio-bootstrap] creating venv at $VENV"
          ${pkgs.uv}/bin/uv venv "$VENV" --python ${pkgs.python312}/bin/python3
        fi

        # shellcheck source=/dev/null
        . "$VENV/bin/activate"

        # Strategia: requirements.txt ha le vere deps; pyproject (se presente)
        # serve solo per registrare il package. Quindi facciamo entrambi.
        if [ -f requirements.txt ]; then
          echo "[gavio-bootstrap] uv pip install -r requirements.txt"
          ${pkgs.uv}/bin/uv pip install -r requirements.txt
        fi

        if [ -f pyproject.toml ]; then
          echo "[gavio-bootstrap] uv pip install -e . (no-deps, dep gestite sopra)"
          ${pkgs.uv}/bin/uv pip install -e . --no-deps || true
        fi

        # Se non c'è né requirements né pyproject, fallback deps minime
        if [ ! -f requirements.txt ] && [ ! -f pyproject.toml ]; then
          echo "[gavio-bootstrap] fallback deps (no project files)"
          ${pkgs.uv}/bin/uv pip install \
            fastapi uvicorn pydantic requests python-dotenv supabase \
            httpx ddgs python-multipart pypdf reportlab Pillow \
            youtube-transcript-api pytesseract faster-whisper \
            pywebpush edge-tts
        fi
      '';

      ExecStart = pkgs.writeShellScript "gavio-start" ''
        set -euo pipefail
        export PATH=${lib.makeBinPath gavioSystemDeps}:$PATH
        cd /opt/gavio
        # shellcheck source=/dev/null
        . /var/lib/gavio/venv/bin/activate

        if [ -f server.py ]; then
          exec python server.py
        elif [ -f app.py ]; then
          exec python -m uvicorn app:app --host 0.0.0.0 --port 8000
        else
          echo "Nessun entrypoint trovato (atteso server.py o app.py)" >&2
          exit 1
        fi
      '';

      Restart = "always";
      RestartSec = "10s";

      # ── HARDENING MEDIUM (M1.1) ─────────────────────────────────────
      # GAVIO è la primary AI: deve restare libera DENTRO i suoi confini
      # (ai-freedom.nix mantiene sudo NOPASSWD per gavio user, polkit aperto).
      # Hardening qui protegge il SISTEMA da attacchi che usano GAVIO come
      # vettore — NON limita le azioni intenzionali dell'AI.
      #
      # NON applichiamo NoNewPrivileges/PrivateDevices/MemoryDenyWriteExecute
      # perché GAVIO necessita:
      #   - subprocess sudo per system_control.py / pc_actions.py
      #   - /dev/ uinput/video per computer use (opt-in)
      #   - JIT compile in Python (httpx + supabase + faster-whisper)

      # Filesystem: protegge sistema, lascia accesso a /opt/gavio e /var/lib/gavio
      ProtectSystem = "strict";
      ReadWritePaths = [
        "/opt/gavio"            # 9p mount workspace (lettura+scrittura GAVIO)
        "/var/lib/gavio"        # venv, dati, dataset, conversations
        "/var/log/gavio"
        "/var/lib/solem"        # cross-share con SOLEM API se serve
      ];
      ReadOnlyPaths = [
        "/etc/gavio"            # env file SOLO read
      ];
      ProtectHome = "tmpfs";    # GAVIO non accede a /home di altri user
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;

      # Process flags
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;

      # System call filter — permissivo (GAVIO esegue tanti subprocess)
      SystemCallFilter = [
        "@system-service"
        "~@cpu-emulation"
        "~@obsolete"
      ];
      SystemCallErrorNumber = "EPERM";
      SystemCallArchitectures = "native";

      # Network: tutto libero. GAVIO chiama Groq API + Supabase cloud + Ollama.
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];

      # UMask
      UMask = "0027";

      # NB: i seguenti flag NON sono applicati per coerenza con ai-freedom.nix:
      #   - NoNewPrivileges (GAVIO può eseguire sudo)
      #   - PrivateDevices (computer use opt-in usa /dev/uinput)
      #   - MemoryDenyWriteExecute (Python JIT)
      #   - RestrictNamespaces (Docker sandbox opt-in)
      #   - ProtectProc (GAVIO ispeziona processi sistema in alcuni nodi)

      # Health check: dopo l'avvio aspetta che :8000 risponda, max 90s.
      # Se non risponde → service marcato "failed" → restart automatico.
      TimeoutStartSec = "180s";
      ExecStartPost = pkgs.writeShellScript "gavio-healthcheck" ''
        set -u
        for i in $(seq 1 30); do
          if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:8000/health > /dev/null 2>&1 \
             || ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:8000/ > /dev/null 2>&1; then
            echo "[gavio-healthcheck] up (after ''${i}*3s)"
            exit 0
          fi
          sleep 3
        done
        echo "[gavio-healthcheck] :8000 non risponde dopo 90s" >&2
        exit 1
      '';

      # Limiti risorse (regolabili in base all'hw)
      MemoryMax = "3G";
      CPUQuota = "300%";

      # NB IMPORTANTE: NESSUNA opzione di sandboxing systemd (ProtectSystem,
      # NoNewPrivileges, PrivateTmp, ecc.). Vedi ai-freedom.nix: GAVIO ha
      # libertà operativa totale.
    };
  };
}
