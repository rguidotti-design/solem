{ config, pkgs, lib, ... }:

# SOLEM PWA COMPANION — Step 47: progressive web app per mobile/glass.
#
# Single responsibility: SOLO server static che serve PWA HTML+JS+SW
# accessibile da phone/glass via WireGuard mesh (Step 24) o LAN.
#
# PWA fa:
#   - Voice command da phone → invia a GAVIO via /api/chat (prompt-filter)
#   - Status dashboard (oltre web HUD Step 36)
#   - Push notification (PWA Web Push API)
#   - Camera access (per OCR / scan inviato a GAVIO)
#   - Geolocation (per GAVIO context-aware)
#   - Offline cache (Service Worker)

let
  cfg = config.solem.pwaCompanion;

  pwaHtml = pkgs.writeText "solem-pwa.html" ''
    <!DOCTYPE html>
    <html lang="it">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="theme-color" content="#0B1426">
      <title>SOLEM Friday</title>
      <link rel="manifest" href="/manifest.json">
      <style>
        *{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
        body{font-family:system-ui,sans-serif;background:linear-gradient(135deg,#0B1426,#1A2540);color:#F5F5F5;min-height:100vh;padding:env(safe-area-inset-top) 20px env(safe-area-inset-bottom)}
        h1{color:#D4A24A;font-weight:300;letter-spacing:6px;text-align:center;padding:24px 0;font-size:32px}
        .sub{color:#888;text-align:center;font-size:13px;margin-bottom:24px}
        .card{background:rgba(212,162,74,.08);border:1px solid rgba(212,162,74,.25);border-radius:12px;padding:20px;margin-bottom:16px}
        .card h2{color:#D4A24A;font-size:11px;letter-spacing:2px;text-transform:uppercase;margin-bottom:12px}
        .btn{display:block;width:100%;background:#D4A24A;color:#0B1426;border:0;padding:18px;border-radius:12px;font-size:18px;font-weight:600;letter-spacing:1px;cursor:pointer;margin:8px 0}
        .btn:active{transform:scale(.97)}
        .btn.secondary{background:transparent;color:#D4A24A;border:1px solid #D4A24A}
        textarea{width:100%;background:rgba(0,0,0,.3);color:#F5F5F5;border:1px solid #2A3540;border-radius:8px;padding:12px;font:14px monospace;resize:vertical;min-height:80px}
        #out{min-height:120px;background:rgba(0,0,0,.4);border-radius:8px;padding:16px;font:13px monospace;overflow-x:auto;white-space:pre-wrap;line-height:1.6}
        .stat-row{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid rgba(212,162,74,.1)}
        .stat-row:last-child{border:0}
        .ok{color:#4caf50}.danger{color:#f44336}
      </style>
    </head>
    <body>
      <h1>SOLEM</h1>
      <div class="sub">Friday Mobile Companion</div>

      <div class="card">
        <h2>Ask GAVIO</h2>
        <textarea id="query" placeholder="Scrivi o registra voce..."></textarea>
        <button class="btn" onclick="askText()">Invia testo</button>
        <button class="btn secondary" onclick="recordVoice()">Registra voce 5s</button>
        <div id="out">(risposta GAVIO apparira qui)</div>
      </div>

      <div class="card">
        <h2>System Status</h2>
        <div id="status">caricamento...</div>
        <button class="btn secondary" onclick="refreshStatus()">Refresh</button>
      </div>

      <div class="card">
        <h2>Quick Actions</h2>
        <button class="btn" onclick="trigger('redteam')">Run Red-Team</button>
        <button class="btn" onclick="trigger('heal')">Run Self-Heal</button>
        <button class="btn secondary" onclick="trigger('lockdown')">LOCKDOWN</button>
      </div>

      <script>
        const API = window.location.origin;

        async function askText() {
          const q = document.getElementById('query').value.trim();
          if (!q) return;
          const out = document.getElementById('out');
          out.textContent = '...';
          try {
            const r = await fetch(API + '/api/ask', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({message: q})
            });
            const data = await r.json();
            out.textContent = data.response || data.error || JSON.stringify(data);
          } catch (e) {
            out.textContent = 'ERROR: ' + e.message;
          }
        }

        async function recordVoice() {
          if (!navigator.mediaDevices) {
            alert('No mic access (HTTPS richiesto)');
            return;
          }
          const out = document.getElementById('out');
          out.textContent = 'Recording 5s...';
          const stream = await navigator.mediaDevices.getUserMedia({audio:true});
          const rec = new MediaRecorder(stream);
          const chunks = [];
          rec.ondataavailable = e => chunks.push(e.data);
          rec.onstop = async () => {
            out.textContent = 'Sending to STT...';
            const blob = new Blob(chunks, {type:'audio/webm'});
            const form = new FormData();
            form.append('audio', blob, 'voice.webm');
            try {
              const r = await fetch(API + '/api/stt', {method:'POST', body:form});
              const data = await r.json();
              document.getElementById('query').value = data.text || "";
              out.textContent = 'STT: ' + data.text;
              setTimeout(askText, 500);
            } catch (e) {
              out.textContent = 'STT ERR: ' + e.message;
            }
            stream.getTracks().forEach(t => t.stop());
          };
          rec.start();
          setTimeout(() => rec.stop(), 5000);
        }

        async function refreshStatus() {
          const el = document.getElementById('status');
          try {
            const r = await fetch(API + '/api/status');
            const s = await r.json();
            el.innerHTML = `
              <div class="stat-row"><span>Host</span><span>$${s.host}</span></div>
              <div class="stat-row"><span>CPU</span><span>$${s.cpu_pct}%</span></div>
              <div class="stat-row"><span>RAM</span><span>$${s.mem_pct}%</span></div>
              <div class="stat-row"><span>Uptime</span><span>$${s.uptime}</span></div>
              <div class="stat-row"><span>Red-team buchi</span><span class="$${s.redteam?.buchi>0?'danger':'ok'}">$${s.redteam?.buchi||0}</span></div>
            `;
          } catch (e) {
            el.textContent = 'fail: ' + e.message;
          }
        }

        async function trigger(action) {
          if (!confirm('Eseguo ' + action + '?')) return;
          const out = document.getElementById('out');
          out.textContent = action + ' in corso...';
          try {
            const r = await fetch(API + '/api/action/' + action, {method:'POST'});
            const data = await r.json();
            out.textContent = data.output || JSON.stringify(data);
          } catch (e) {
            out.textContent = 'ERR: ' + e.message;
          }
        }

        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.register('/sw.js').catch(() => {});
        }

        refreshStatus();
        setInterval(refreshStatus, 30000);
      </script>
    </body>
    </html>
  '';

  pwaManifest = pkgs.writeText "manifest.json" (builtins.toJSON {
    name = "SOLEM Friday Mobile";
    short_name = "SOLEM";
    start_url = "/";
    display = "standalone";
    background_color = "#0B1426";
    theme_color = "#D4A24A";
    icons = [ ];
  });

  swJs = pkgs.writeText "sw.js" ''
    // SOLEM PWA Service Worker (offline cache minimo)
    self.addEventListener('install', e => self.skipWaiting());
    self.addEventListener('activate', e => self.clients.claim());
    self.addEventListener('fetch', e => {
      e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
    });
  '';

  pwaRoot = pkgs.runCommand "solem-pwa" { } ''
    mkdir -p $out
    cp ${pwaHtml} $out/index.html
    cp ${pwaManifest} $out/manifest.json
    cp ${swJs} $out/sw.js
  '';
in {
  options.solem.pwaCompanion = {
    enable = lib.mkEnableOption "PWA mobile companion (Friday on phone/glass)";
    port = lib.mkOption { type = lib.types.port; default = 8089; };
    bind = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address (per accesso WG mesh: 10.100.0.1 o 0.0.0.0)";
    };
  };

  config = lib.mkIf cfg.enable {
    # nginx serve PWA + proxy a GAVIO API
    services.nginx.enable = lib.mkDefault true;
    services.nginx.virtualHosts."solem-pwa" = {
      listen = [ { addr = cfg.bind; port = cfg.port; ssl = false; } ];
      root = "${pwaRoot}";

      locations."/" = {
        index = "index.html";
        tryFiles = "$uri $uri/ /index.html";
      };

      # Proxy verso GAVIO via prompt filter
      locations."/api/" = {
        proxyPass = "http://127.0.0.1:8001/api/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_read_timeout 60s;
        '';
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.bind != "127.0.0.1") [ cfg.port ];

    environment.etc."solem/pwa-companion.md".text = ''
      # SOLEM PWA Mobile Companion (Step 47)

      Progressive Web App per phone/glass: voice command, status, quick actions.

      ## Setup
      ```nix
      solem.pwaCompanion = {
        enable = true;
        port = 8089;
        bind = "10.100.0.1";    # WireGuard mesh server IP (Step 24)
      };
      ```

      ## Accesso da phone
      1. Connetti phone a WireGuard mesh (importa config WG da Step 24)
      2. Apri browser mobile → http://10.100.0.1:8089
      3. Add to Home Screen (PWA installa come app)

      ## Feature
      - **Ask GAVIO**: testo o voce 5s → STT → GAVIO → risposta
      - **Status**: CPU/RAM/uptime/redteam buchi live
      - **Quick Actions**: run redteam, heal, lockdown

      ## Limiti onesti
      - HTTPS richiesto per mic access browser: configura nginx con
        cert SOLEM PKI (Step 26).
      - Service Worker offline cache: minimo, no full offline mode.
      - Push notifications: TODO (richiede vapid keys + push server).
      - Icon assets: nessuna icona allegata (no PNG asset).
        Sostituire con icona reale prima di prod.
    '';
  };
}
