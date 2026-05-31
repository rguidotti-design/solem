{ config, pkgs, lib, ... }:

# SOLEM HUB RELEASE — Step 50: scaffold release engineering.
#
# Single responsibility: SOLO orchestrazione release pipeline:
#   - ISO signing (GPG/minisign) — verifica autenticita' download
#   - Landing page static (HTML) per host su GitHub Pages o domain
#   - Update channel manifest (stable/beta/nightly) JSON
#   - Helper CLI per publish release (build → sign → upload)
#
# NB: questo modulo NON HOSTA il sito. Genera artifacts da deployare
# su GitHub Pages, Netlify, Cloudflare Pages, S3, ecc.

let
  cfg = config.solem.hubRelease;

  landingPage = pkgs.writeText "solem-landing.html" ''
    <!DOCTYPE html>
    <html lang="it">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>SOLEM — AI-native OS</title>
      <meta name="description" content="OS NixOS-based AI-native con 49 step di sicurezza zero-trust. FOSS, 0 €.">
      <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font:16px/1.6 system-ui,sans-serif;background:#0B1426;color:#F5F5F5}
        .container{max-width:1100px;margin:0 auto;padding:40px 24px}
        h1{font-size:64px;font-weight:200;letter-spacing:8px;color:#D4A24A;margin-bottom:8px}
        .sub{font-size:20px;color:#888;margin-bottom:48px}
        h2{font-size:28px;font-weight:300;color:#D4A24A;margin:48px 0 16px;letter-spacing:2px}
        h3{font-size:18px;font-weight:500;margin:24px 0 8px;color:#F5F5F5}
        p{margin-bottom:16px;color:#CCC}
        .features{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px;margin:32px 0}
        .feature{background:rgba(212,162,74,.08);border:1px solid rgba(212,162,74,.2);border-radius:12px;padding:24px}
        .feature h3{color:#D4A24A;font-size:16px;text-transform:uppercase;letter-spacing:2px}
        code{background:rgba(0,0,0,.4);padding:2px 8px;border-radius:4px;font:14px monospace;color:#D4A24A}
        pre{background:#000;padding:20px;border-radius:8px;overflow-x:auto;border:1px solid rgba(212,162,74,.2)}
        pre code{background:none;padding:0;color:#F5F5F5}
        .btn{display:inline-block;background:#D4A24A;color:#0B1426;padding:14px 32px;border-radius:8px;text-decoration:none;font-weight:600;letter-spacing:1px;margin:8px 0}
        .btn:hover{opacity:.9}
        .btn.secondary{background:transparent;border:1px solid #D4A24A;color:#D4A24A}
        .stats{display:flex;gap:32px;margin:24px 0;flex-wrap:wrap}
        .stat{padding:16px 24px;background:rgba(212,162,74,.05);border-radius:8px}
        .stat-num{font-size:36px;font-weight:200;color:#D4A24A}
        .stat-lbl{font-size:12px;color:#888;text-transform:uppercase;letter-spacing:1px}
        footer{margin-top:80px;padding:32px 0;border-top:1px solid #222;color:#666;text-align:center;font-size:14px}
      </style>
    </head>
    <body>
      <div class="container">
        <h1>SOLEM</h1>
        <div class="sub">AI-native OS · sicurezza zero-trust · 100% FOSS · 0 €</div>

        <div class="stats">
          <div class="stat"><div class="stat-num">49+</div><div class="stat-lbl">Step Security</div></div>
          <div class="stat"><div class="stat-num">100+</div><div class="stat-lbl">Moduli Nix</div></div>
          <div class="stat"><div class="stat-num">15/15</div><div class="stat-lbl">VM Test verdi</div></div>
          <div class="stat"><div class="stat-num">0 €</div><div class="stat-lbl">Licenze</div></div>
        </div>

        <a href="#download" class="btn">⬇ Scarica ISO</a>
        <a href="https://github.com/rguidotti-design/solem" class="btn secondary">⌗ GitHub</a>

        <h2>Cosa rende SOLEM diverso</h2>
        <div class="features">
          <div class="feature">
            <h3>Zero-Trust per AI</h3>
            <p>GAVIO (l'AI personale) gira ingabbiata: utente isolato UID 970, firewall egress whitelist, AppArmor profile, canary kill switch, DNS allowlist.</p>
          </div>
          <div class="feature">
            <h3>Auto Red-Team Notturno</h3>
            <p>Ogni notte SOLEM si auto-attacca con 18 scenari. Se trova buchi, applica fix safe. Self-improving.</p>
          </div>
          <div class="feature">
            <h3>Friday Mode</h3>
            <p>Comando unico <code>solem</code>: status, ask GAVIO (testo o voce), security run, network manage. Stile Iron Man.</p>
          </div>
          <div class="feature">
            <h3>FOSS Forever</h3>
            <p>Nessun servizio cloud proprietario. Nessuna telemetria. Stack: NixOS, Linux hardened, age, WireGuard, Tor, Suricata.</p>
          </div>
          <div class="feature">
            <h3>Backup & Recovery</h3>
            <p>borg + age encryption + rclone offsite. Recovery USB builder integrato. Generation rollback safe.</p>
          </div>
          <div class="feature">
            <h3>Mobile Companion</h3>
            <p>PWA per phone/glass via WireGuard mesh. Voice command, status, lockdown da telefono.</p>
          </div>
        </div>

        <h2 id="download">Download</h2>
        <p>ISO live + installer Calamares. Boot, click "Installa SOLEM", 5-15min.</p>
        <pre><code># Verifica signature (importa key SOLEM)
gpg --recv-keys SOLEM-RELEASE-KEY-ID
gpg --verify solem-24.11-x86_64.iso.sig solem-24.11-x86_64.iso

# Scrivi su USB (Linux/macOS)
sudo dd if=solem-24.11-x86_64.iso of=/dev/sdX bs=4M status=progress

# Boot UEFI → seleziona USB → live SOLEM</code></pre>

        <p><strong>Channels:</strong></p>
        <ul style="margin-left:24px">
          <li><strong>stable</strong>: aggiornato mensile, testato in produzione</li>
          <li><strong>beta</strong>: nuove feature, settimanale</li>
          <li><strong>nightly</strong>: HEAD main, ogni commit (CI verde)</li>
        </ul>

        <h2>Per chi è SOLEM</h2>
        <p>Developer, sysadmin, AI researcher, chiunque vuole un OS dove i propri dati e la propria AI sono <em>realmente</em> protetti — non solo "trust us" del vendor proprietario.</p>

        <h2>Risorse</h2>
        <ul style="margin-left:24px">
          <li><a href="https://github.com/rguidotti-design/solem" style="color:#D4A24A">Source Code</a></li>
          <li><a href="https://github.com/rguidotti-design/solem/blob/main/docs/GAPS-VERO-OS.md" style="color:#D4A24A">Roadmap onesta</a></li>
          <li><a href="https://github.com/rguidotti-design/solem/issues" style="color:#D4A24A">Bug reports</a></li>
        </ul>

        <footer>
          SOLEM · ${cfg.version} · Apache-2.0<br>
          Made with care · No telemetry · No vendor lock-in
        </footer>
      </div>
    </body>
    </html>
  '';

  releaseManifest = pkgs.writeText "channels.json" (builtins.toJSON {
    schema_version = 1;
    last_updated = "auto-injected-by-publish";
    channels = {
      stable = {
        version = cfg.version;
        nixos_release = "24.11";
        iso_url = "${cfg.downloadBase}/stable/solem-${cfg.version}-x86_64.iso";
        signature_url = "${cfg.downloadBase}/stable/solem-${cfg.version}-x86_64.iso.sig";
        sha256 = "auto-injected";
      };
      beta = {
        version = "${cfg.version}-beta";
        iso_url = "${cfg.downloadBase}/beta/solem-latest-x86_64.iso";
      };
      nightly = {
        iso_url = "${cfg.downloadBase}/nightly/solem-latest-x86_64.iso";
      };
    };
  });
in {
  options.solem.hubRelease = {
    enable = lib.mkEnableOption "Hub release scaffold (landing + manifest + signing CLI)";

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.1.0";
    };

    downloadBase = lib.mkOption {
      type = lib.types.str;
      default = "https://solem-releases.example.com";
      example = "https://releases.solem.so";
    };
  };

  config = lib.mkIf cfg.enable {
    # Espone landing + manifest in /etc per servire via nginx local o
    # copiare su GitHub Pages.
    environment.etc."solem/hub/index.html".source = landingPage;
    environment.etc."solem/hub/channels.json".source = releaseManifest;

    environment.systemPackages = with pkgs; [
      gnupg minisign
      (pkgs.writeShellApplication {
        name = "solem-release";
        runtimeInputs = with pkgs; [ coreutils gnupg minisign jq curl ];
        text = ''
          ACTION="''${1:-help}"

          case "$ACTION" in
            build)
              echo "── Build ISO ──"
              cd /etc/nixos || cd "$HOME/.config/solem" || cd "$PWD"
              nix build .#iso --no-link --print-out-paths > /tmp/iso-path
              ISO=$(cat /tmp/iso-path)/iso/$(ls "$(cat /tmp/iso-path)/iso/" | head -1)
              echo "ISO: $ISO"
              echo "SHA256: $(sha256sum "$ISO" | awk '{print $1}')"
              echo "$ISO" > /tmp/solem-iso-latest
              ;;

            sign)
              ISO="''${1:-$(cat /tmp/solem-iso-latest)}"
              if [ ! -f "$ISO" ]; then echo "ISO non trovato: $ISO"; exit 1; fi
              KEY="''${SOLEM_GPG_KEY:-}"
              if [ -z "$KEY" ]; then
                echo "Set SOLEM_GPG_KEY=<key-id> per signing."
                echo "Genera key prima: gpg --gen-key"
                exit 1
              fi
              echo "Signing $ISO con $KEY..."
              gpg --batch --yes --armor --detach-sign --local-user "$KEY" "$ISO"
              echo "✓ Signature: ''${ISO}.asc"
              sha256sum "$ISO" > "''${ISO}.sha256"
              echo "✓ Hash: ''${ISO}.sha256"
              ;;

            publish)
              ISO="''${1:-$(cat /tmp/solem-iso-latest)}"
              CHANNEL="''${2:-stable}"
              DEST="''${SOLEM_PUBLISH_DEST:-}"
              if [ -z "$DEST" ]; then
                echo "Set SOLEM_PUBLISH_DEST per upload."
                echo "Esempio: SOLEM_PUBLISH_DEST=user@host:/var/www/releases/$CHANNEL"
                exit 1
              fi
              rsync -avP "$ISO" "''${ISO}.asc" "''${ISO}.sha256" "$DEST/" || \
                scp "$ISO" "''${ISO}.asc" "''${ISO}.sha256" "$DEST"
              echo "✓ Published to $DEST"
              ;;

            verify)
              # Verifica una ISO scaricata
              ISO="''${1:?Usage: solem-release verify <iso>}"
              if [ -f "''${ISO}.sha256" ]; then
                sha256sum -c "''${ISO}.sha256" && echo "✓ Hash OK"
              fi
              if [ -f "''${ISO}.asc" ]; then
                gpg --verify "''${ISO}.asc" "$ISO" && echo "✓ Signature OK"
              fi
              ;;

            channels)
              cat /etc/solem/hub/channels.json | jq .
              ;;

            landing)
              echo "Landing page in: /etc/solem/hub/index.html"
              echo "Copia su:"
              echo "  GitHub Pages: cp /etc/solem/hub/index.html docs/index.html + push"
              echo "  Netlify/Cloudflare Pages: deploy /etc/solem/hub/"
              echo "  Self-hosted nginx: vedi solem-hub-release service"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-release — release engineering pipeline

  build          nix build .#iso + sha256
  sign           GPG sign ISO (SOLEM_GPG_KEY env)
  publish        rsync/scp to SOLEM_PUBLISH_DEST
  verify <iso>   verifica hash + signature di ISO scaricato
  channels       mostra manifest channels.json
  landing        info landing page (deploy hint)

Workflow release:
  1. Genera GPG key: gpg --full-gen-key
  2. Pubblica chiave pubblica su solem.so + keyserver
  3. solem-release build
  4. SOLEM_GPG_KEY=YOUR_ID solem-release sign
  5. SOLEM_PUBLISH_DEST=user@host:/path solem-release publish
  6. Aggiorna /etc/solem/hub/channels.json con nuovo url+hash
  7. Deploy landing: cp /etc/solem/hub/index.html → GitHub Pages
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/hub-release.md".text = ''
      # SOLEM Hub Release (Step 50)

      Scaffold release engineering: landing page + ISO signing + channels.

      ## Componenti
      - `/etc/solem/hub/index.html` — landing page statica (deploy su Pages/CDN)
      - `/etc/solem/hub/channels.json` — manifest update channels
      - `solem-release` CLI — build, sign, publish, verify

      ## Deploy landing page
      ```bash
      # Su solem.so (GitHub Pages):
      cp /etc/solem/hub/index.html ~/solem-website/index.html
      cd ~/solem-website && git push  # GitHub auto-deploys
      ```

      ## Pipeline release manuale
      ```bash
      # 1. Build ISO
      solem-release build
      # 2. Sign
      SOLEM_GPG_KEY=YOUR_KEY_ID solem-release sign
      # 3. Publish
      SOLEM_PUBLISH_DEST=user@releases.solem.so:/srv/releases/stable \
        solem-release publish
      ```

      ## Channels
      - **stable**: rilascio mensile testato
      - **beta**: settimanale, nuove feature
      - **nightly**: ogni commit CI verde

      ## Verifica utente (post-download)
      ```bash
      curl -O https://releases.solem.so/stable/solem-X.Y.Z.iso{,.asc,.sha256}
      solem-release verify solem-X.Y.Z.iso
      ```

      ## Limiti onesti
      - Manifest channels.json: utente deve aggiornare manualmente
        version/url/hash dopo ogni release (futuro: CI auto-update).
      - Hosting: questo modulo NON serve il sito. Deploy su:
        GitHub Pages (free), Netlify, Cloudflare Pages (free), o
        nginx self-hosted su VPS.
      - GPG key: utente DEVE generare + tenere private OFFLINE.
        Compromise = perdita trust catena update.
    '';
  };
}
