{ config, pkgs, lib, ... }:

# SOLEM HPC TOOLKIT — CLI utente + Apptainer + job templates.
#
# Single responsibility: SOLO tooling utente per usare HPC.
# Non configura SLURM (vedi solem-hpc.nix), non gestisce cluster
# distribuito (vedi solem-cluster.nix). Solo:
#
#   - `solem-hpc` CLI helper (wrap sbatch/squeue/scancel + status)
#   - Apptainer (ex Singularity, FOSS) per container HPC reproducible
#   - Job templates Python/MPI/GPU pronti in /etc/solem/hpc-templates/
#   - Auto-detect risorse (CPU/RAM) per single-node setup
#
# Risponde a: "deve far funzionare i super computer". Single-node oggi,
# multi-node domani (basta cambiare partition nel job script).
#
# 100% FOSS: Apptainer (BSD-3), SLURM (GPL), OpenMPI (BSD).

let
  cfg = config.solem.hpcToolkit;

  hpcCli = pkgs.writeShellApplication {
    name = "solem-hpc";
    runtimeInputs = with pkgs; [ coreutils slurm util-linux gawk procps ];
    text = ''
      ACTION="''${1:-status}"
      shift || true

      TEMPLATES_DIR="/etc/solem/hpc-templates"
      JOBS_DIR="$HOME/.local/share/solem/hpc-jobs"
      mkdir -p "$JOBS_DIR"

      case "$ACTION" in
        # ── Status cluster + risorse locali ──────────────────────────
        status)
          echo "── SOLEM HPC ──"
          if command -v sinfo >/dev/null 2>&1; then
            sinfo -h 2>/dev/null && echo "✓ SLURM attivo" || echo "SLURM non disponibile (abilita solem.hpc.enable=true)"
          else
            echo "SLURM non installato"
          fi
          echo
          echo "── Risorse locali ──"
          CPU=$(nproc)
          RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
          RAM_GB=$((RAM_KB / 1024 / 1024))
          echo "CPU cores:  $CPU"
          echo "RAM:        $RAM_GB GB"
          if command -v nvidia-smi >/dev/null 2>&1; then
            nvidia-smi -L 2>/dev/null || echo "GPU NVIDIA: nessuna"
          else
            echo "GPU:        nessuna NVIDIA (CPU-only HPC)"
          fi
          ;;

        # ── Submit job da template ───────────────────────────────────
        submit|run)
          TEMPLATE="''${1:?Usage: solem-hpc submit <template> [args...]}"
          shift || true
          TPL_FILE="$TEMPLATES_DIR/$TEMPLATE.sbatch"
          if [ ! -f "$TPL_FILE" ]; then
            echo "Template non trovato: $TEMPLATE"
            echo "Disponibili:"
            ls "$TEMPLATES_DIR"/*.sbatch 2>/dev/null | xargs -n1 basename | sed 's/.sbatch$//' | sed 's/^/  /'
            exit 1
          fi
          JOB_FILE="$JOBS_DIR/$(date +%s)-$TEMPLATE.sbatch"
          cp "$TPL_FILE" "$JOB_FILE"
          echo "→ Job script: $JOB_FILE"
          if command -v sbatch >/dev/null 2>&1; then
            sbatch "$JOB_FILE" "$@"
          else
            echo "(sbatch non disponibile — eseguo localmente come test)"
            bash "$JOB_FILE" "$@"
          fi
          ;;

        # ── Queue (jobs in coda) ─────────────────────────────────────
        queue|q)
          if command -v squeue >/dev/null 2>&1; then
            squeue -u "$USER" 2>/dev/null || squeue
          else
            echo "SLURM non disponibile"
          fi
          ;;

        # ── Cancel job ───────────────────────────────────────────────
        cancel|kill)
          JOB_ID="''${1:?Usage: solem-hpc cancel <job-id>}"
          scancel "$JOB_ID"
          echo "✓ Job $JOB_ID cancellato"
          ;;

        # ── Templates ────────────────────────────────────────────────
        templates|tpl|ls)
          echo "── Templates HPC disponibili ──"
          if [ -d "$TEMPLATES_DIR" ]; then
            for T in "$TEMPLATES_DIR"/*.sbatch; do
              [ -f "$T" ] || continue
              NAME=$(basename "$T" .sbatch)
              DESC=$(head -5 "$T" | grep -E '^# Description:' | sed 's/^# Description: //')
              printf "  %-20s %s\n" "$NAME" "$DESC"
            done
          fi
          ;;

        # ── Apptainer wrapper (run container HPC) ────────────────────
        container|apptainer)
          if ! command -v apptainer >/dev/null 2>&1; then
            echo "Apptainer non disponibile (abilita solem.hpcToolkit.apptainer=true)"
            exit 1
          fi
          apptainer "$@"
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-hpc — toolkit utente per HPC SLURM

  status                stato cluster + risorse locali
  submit <tpl> [args]   submit job da template
  queue                 jobs in coda (tuoi)
  cancel <id>           annulla job
  templates             elenca templates disponibili
  container <args>      wrapper apptainer (container HPC)

Templates default:
  python-cpu            job Python single-CPU
  python-multicpu       job Python OpenMP multi-core
  gpu-pytorch           job PyTorch su GPU (richiede CUDA)
  mpi-hello             job MPI distributed (single/multi node)

Esempio:
  solem-hpc submit python-cpu --array=1-10
  solem-hpc queue
  solem-hpc status

Storage job: $HOME/.local/share/solem/hpc-jobs/

Tutto FOSS (SLURM + Apptainer + OpenMPI). 0 €.
HELP
          ;;
      esac
    '';
  };

  # Templates HPC pronti
  templatePythonCpu = ''
    #!/usr/bin/env bash
    # Description: Job Python single-CPU (template SOLEM)
    #SBATCH --job-name=solem-python
    #SBATCH --output=%j-%x.out
    #SBATCH --error=%j-%x.err
    #SBATCH --time=01:00:00
    #SBATCH --cpus-per-task=1
    #SBATCH --mem=2G

    echo "Job $SLURM_JOB_ID su nodo $SLURMD_NODENAME"
    echo "Argomenti: $*"

    # Esegui Python con args passati
    python3 "$@"
  '';

  templatePythonMulticpu = ''
    #!/usr/bin/env bash
    # Description: Python multi-core OpenMP/threading
    #SBATCH --job-name=solem-python-mp
    #SBATCH --output=%j-%x.out
    #SBATCH --time=02:00:00
    #SBATCH --cpus-per-task=8
    #SBATCH --mem=8G

    export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
    echo "Esegui con $OMP_NUM_THREADS threads"
    python3 "$@"
  '';

  templateGpuPytorch = ''
    #!/usr/bin/env bash
    # Description: PyTorch GPU (richiede CUDA + GPU partition)
    #SBATCH --job-name=solem-gpu
    #SBATCH --output=%j-%x.out
    #SBATCH --time=04:00:00
    #SBATCH --gres=gpu:1
    #SBATCH --cpus-per-task=4
    #SBATCH --mem=16G

    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi
    fi
    python3 "$@"
  '';

  templateMpiHello = ''
    #!/usr/bin/env bash
    # Description: MPI distributed hello-world (test multi-node)
    #SBATCH --job-name=solem-mpi
    #SBATCH --output=%j-%x.out
    #SBATCH --time=00:10:00
    #SBATCH --ntasks=4
    #SBATCH --mem-per-cpu=1G

    mpirun --map-by ppr:1:node ./hello_mpi
  '';
in {
  options.solem.hpcToolkit = {
    enable = lib.mkEnableOption "Toolkit HPC utente (CLI + templates + Apptainer)";

    apptainer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Installa Apptainer (ex Singularity, FOSS) per container HPC.
        Default off (pacchetto grosso, opt-in solo per HPC reali).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      hpcCli
      slurm  # client CLI (sbatch, squeue, scancel)
    ] ++ lib.optional cfg.apptainer pkgs.apptainer;

    # Templates pronti in /etc
    environment.etc."solem/hpc-templates/python-cpu.sbatch".text = templatePythonCpu;
    environment.etc."solem/hpc-templates/python-multicpu.sbatch".text = templatePythonMulticpu;
    environment.etc."solem/hpc-templates/gpu-pytorch.sbatch".text = templateGpuPytorch;
    environment.etc."solem/hpc-templates/mpi-hello.sbatch".text = templateMpiHello;

    environment.etc."solem/hpc-toolkit.md".text = ''
      # SOLEM HPC Toolkit

      Toolkit utente per usare SLURM single-node o multi-node.
      Single responsibility: tooling + templates, non configura SLURM
      (vedi `solem.hpc.enable`).

      ## Quick start single-node

      ```
      # 1. Abilita SLURM (vedi solem-hpc.nix)
      solem.hpc.enable = true;
      solem.hpc.role = "both";    # ctld + slurmd su stesso host

      # 2. Stato
      solem-hpc status

      # 3. Submit job test
      solem-hpc submit python-cpu my_script.py

      # 4. Coda
      solem-hpc queue
      ```

      ## Da single-node a multi-node

      Stesso script `.sbatch` funziona su entrambi. Cambia solo:
      - `solem.hpc.nodes`: aggiungi worker nodes
      - `solem.hpc.partitions`: definisci queue (gpu/cpu/highmem)
      - `solem.hpc.controlMachine`: hostname controller

      Worker nodes installano solo `solem.hpc.role = "worker"`.

      ## Apptainer (container HPC)

      ```
      solem.hpcToolkit.apptainer = true;
      ```

      ```
      solem-hpc container pull docker://python:3.12
      solem-hpc container exec python_latest.sif python -c 'print("ok")'
      ```

      ## Templates inclusi

      Tutti in `/etc/solem/hpc-templates/`:
        - python-cpu        — Python single-CPU
        - python-multicpu   — Python multi-core (OpenMP)
        - gpu-pytorch       — PyTorch su GPU
        - mpi-hello         — MPI distributed (test multi-node)

      Personalizza copiando in `~/.local/share/solem/hpc-jobs/`.

      ## Costo

      Tutto FOSS:
        - SLURM (GPL-2.0) — scheduler standard de-facto HPC
        - Apptainer (BSD-3) — container reproducible
        - OpenMPI (BSD-3) — MPI distributed

      0 € licenze. Stessa stack su top500 supercomputer.
    '';
  };
}
