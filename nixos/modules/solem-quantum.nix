{ config, pkgs, lib, ... }:

# SOLEM QUANTUM — toolchain Qiskit + simulatori locali, opt-in.
#
# Single responsibility: SOLO installazione Python env Qiskit + Aer +
# pacchetti correlati. La logica orchestratore è in solem_api/layers/quantum.py.
#
# 100% FOSS:
#   - qiskit       (Apache 2.0)
#   - qiskit-aer   (simulator C++ ad alte prestazioni)
#   - cirq         (Google, Apache 2.0) — alternativa
#   - pyquil       (Rigetti, Apache 2.0) — solo client (Forest cloud è a pagamento)
#
# Costo: 0 € per simulatori. IBM Quantum free-tier per hardware reale.

let
  cfg = config.solem.quantum;

  pyQuantum = pkgs.python312.withPackages (ps: with ps; [
    qiskit
    qiskit-aer
  ] ++ lib.optionals cfg.includeCirq [
    cirq
  ] ++ lib.optionals cfg.includePyquil [
    pyquil
  ]);
in {
  options.solem.quantum = {
    enable = lib.mkEnableOption "Qiskit + Aer simulator + tool quantum locali";

    includeCirq = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Includi Cirq (Google) come alternativa a Qiskit";
    };

    includePyquil = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Includi pyquil (Rigetti) — client only";
    };

    enableJupyter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Avvia jupyter-lab su :8888 per quantum notebook";
    };

    enableIbmQuantum = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Abilita IBM Quantum client (richiede token in
        /var/lib/solem-secrets/ibm_quantum.token, mode 0600 root).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pyQuantum ];

    systemd.tmpfiles.rules = [
      "d /var/lib/solem-secrets        0700 root root - -"
    ];

    # Jupyter opt-in per development quantum
    systemd.services.solem-jupyter = lib.mkIf cfg.enableJupyter {
      description = "SOLEM — Jupyter Lab (quantum playground)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "gavio";
        WorkingDirectory = "/home/gavio";
        ExecStart = "${pyQuantum}/bin/jupyter-lab --no-browser --ip=127.0.0.1 --port=8888";
        Restart = "on-failure";
      };
    };
  };
}
