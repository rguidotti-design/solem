# SOLEM — packaging GAVIO backend Python come derivation Nix.
#
# Single responsibility: SOLO pacchettizzare il codice Python di GAVIO
# (https://github.com/rguidotti-design/gavio) in modo riproducibile.
#
# Usato da `solem.api` (systemd unit) e build via `nix build .#gavio`.
{ lib
, python312
, fetchFromGitHub
, makeWrapper
, tesseract
, ffmpeg
}:

let
  # GAVIO è un progetto fratello. Per ora referenziamo via GitHub.
  # Fallback locale: l'utente che ha il clone locale può sostituire
  # con `path:/home/$USER/Desktop/gavio`.
  gavioSrc = fetchFromGitHub {
    owner = "rguidotti-design";
    repo = "gavio";
    rev = "main";
    # Hash placeholder — `nix-prefetch` aggiorna a build time. Per ora
    # impacchettiamo a partire da TOFU.
    sha256 = lib.fakeSha256;
  };

  pythonEnv = python312.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
    pydantic-settings
    httpx
    requests
    python-dotenv
    supabase
    reportlab
    pypdf
    pillow
    python-multipart
    pyperclip
    pytest
    aiofiles
    sqlalchemy
    sse-starlette
    cryptography
    jinja2
    apscheduler
    psutil
    # ddgs, edge-tts, faster-whisper, youtube-transcript-api, pytesseract,
    # pywebpush — alcuni possono non essere in nixpkgs. L'utente fa pip
    # install dentro un venv overlay se servono.
  ]);
in
python312.pkgs.buildPythonApplication rec {
  pname   = "gavio";
  version = "0.1.0";
  format  = "other";
  src     = gavioSrc;

  nativeBuildInputs = [ makeWrapper ];

  propagatedBuildInputs = [
    pythonEnv
    tesseract
    ffmpeg
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/lib/gavio $out/bin

    # Copia interno
    cp -r solem_api $out/lib/gavio/ 2>/dev/null || cp -r . $out/lib/gavio/

    # Launcher wrapper
    cat > $out/bin/gavio-server <<EOF
    #!/usr/bin/env bash
    export PYTHONPATH=$out/lib/gavio:\$PYTHONPATH
    exec ${pythonEnv}/bin/python -m uvicorn solem_api.app:app \\
      --host \''${GAVIO_HOST:-127.0.0.1} \\
      --port \''${GAVIO_PORT:-8000} \\
      "\$@"
    EOF
    chmod +x $out/bin/gavio-server

    # Healthcheck wrapper
    cat > $out/bin/gavio-health <<EOF
    #!/usr/bin/env bash
    URL="\''${GAVIO_API_URL:-http://127.0.0.1:8000}/health"
    exec ${pythonEnv}/bin/python -c "import urllib.request, sys; \\
      r = urllib.request.urlopen('\$URL', timeout=3); \\
      sys.exit(0 if r.status == 200 else 1)"
    EOF
    chmod +x $out/bin/gavio-health
  '';

  meta = with lib; {
    description  = "GAVIO — AI personale gerarchica multi-agente (backend FastAPI)";
    homepage     = "https://github.com/rguidotti-design/gavio";
    license      = licenses.agpl3Plus;
    platforms    = platforms.linux;
    maintainers  = [ ];
    mainProgram  = "gavio-server";
  };
}
