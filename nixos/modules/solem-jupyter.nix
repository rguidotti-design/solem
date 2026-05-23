{ config, pkgs, lib, ... }:

# SOLEM JUPYTER — JupyterLab + Python ML stack preconfigured.
#
# Single responsibility: SOLO installazione Jupyter + librerie ML/data
# science comuni. Niente CUDA (sta in solem-drivers.nix nvidia).

let
  cfg = config.solem.jupyter;

  pyMl = pkgs.python312.withPackages (ps: with ps; [
    jupyter jupyterlab notebook
    ipywidgets ipykernel
    # Core scientific
    numpy scipy pandas matplotlib seaborn plotly
    # ML
    scikit-learn
    # Stats
    statsmodels
    # Image
    pillow opencv4
    # Notebook utility
    requests httpx
    # AI client
    openai
  ]);
in {
  options.solem.jupyter = {
    enable = lib.mkEnableOption "JupyterLab + Python ML stack preconfigured";

    serveOnBoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-start jupyter-lab daemon su :8888 al boot";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pyMl ];

    systemd.user.services.solem-jupyter = lib.mkIf cfg.serveOnBoot {
      description = "SOLEM — Jupyter Lab daemon";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pyMl}/bin/jupyter-lab --no-browser --ip=127.0.0.1 --port=${toString cfg.port}";
        Restart = "on-failure";
        Environment = "PATH=${pkgs.coreutils}/bin:${pkgs.git}/bin";
      };
    };

    environment.etc."solem/jupyter.md".text = ''
      # SOLEM Jupyter

      ## Quick start
      jupyter-lab --no-browser --port=8888
      Apri http://127.0.0.1:8888

      ## Librerie precaricate
      - numpy, scipy, pandas, matplotlib, seaborn, plotly
      - scikit-learn, statsmodels
      - Pillow, opencv (PIL)
      - openai (compat con GAVIO_API_URL via /v1)

      ## Esempio: chiama GAVIO da notebook
      ```python
      import os
      from openai import OpenAI
      c = OpenAI(base_url=os.environ.get("GAVIO_API_URL","http://127.0.0.1:8000")+"/v1",
                 api_key="not-needed")
      r = c.chat.completions.create(model="gavio",
            messages=[{"role":"user","content":"analizza questo CSV"}])
      print(r.choices[0].message.content)
      ```
    '';
  };
}
