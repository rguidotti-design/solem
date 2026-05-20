{ config, pkgs, lib, ... }:

# SOLEM CLUSTER — worker daemon che registra il device nel cluster +
# llama.cpp RPC server per inference distribuita.
#
# Single responsibility: SOLO orchestrare l'iscrizione di QUESTO device
# al cluster (registry sul gateway) + esporre llama.cpp RPC per inference
# remota. La policy di routing è in solem_api/layers/cluster.py.
#
# Architettura:
#
#    [Gateway SOLEM (Beelink)] ─── /cluster/register (HTTP, mesh)
#         │
#         │ POST heartbeat ogni 30s
#         ├── [Laptop]  worker · CPU 8c · 16GB
#         ├── [NVIDIA server] worker · GPU 24GB VRAM
#         └── [smartphone via PWA] worker leggero · STT/TTS only
#
# Quando GAVIO vuole inference grande → /cluster/dispatch → NVIDIA server.
# Quando vuole embedding → laptop. Quando STT (microfono) → device locale.
#
# 100% FOSS, costo 0 €.

let
  cfg = config.solem.cluster;

  workerScript = pkgs.writers.writePython3 "solem-cluster-worker" {
    flakeIgnore = [ "E501" "E302" "E305" "W291" "W293" ];
  } ''
    """SOLEM cluster worker — register + heartbeat al gateway.

    Loop:
      1. Al boot: detect capabilities (cpu/ram/gpu) → POST /cluster/register
      2. Ogni 30s: misura load (psutil) → POST /cluster/heartbeat
    """
    import json
    import os
    import socket
    import subprocess
    import time
    import urllib.request
    import urllib.error
    from pathlib import Path

    GATEWAY = os.environ.get("SOLEM_CLUSTER_GATEWAY", "http://127.0.0.1:8001")
    DEVICE_ID = os.environ.get("SOLEM_DEVICE_ID") or socket.gethostname()
    DEVICE_NAME = os.environ.get("SOLEM_DEVICE_NAME") or socket.gethostname()
    ENDPOINT = os.environ.get("SOLEM_DEVICE_ENDPOINT") or f"http://{socket.gethostname()}.solem.local:8001"

    def cpu_cores():
        try:
            return os.cpu_count() or 1
        except Exception:
            return 1

    def ram_gb():
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        return round(int(line.split()[1]) / 1024 / 1024, 1)
        except Exception:
            pass
        return 0.0

    def disk_free_gb(path="/"):
        try:
            st = os.statvfs(path)
            return round(st.f_bavail * st.f_frsize / (1024**3), 1)
        except Exception:
            return 0.0

    def cpu_model():
        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("model name"):
                        return line.split(":", 1)[1].strip()
        except Exception:
            pass
        return "?"

    def detect_gpu():
        # NVIDIA
        try:
            r = subprocess.run(["nvidia-smi", "--query-gpu=name,memory.total",
                                "--format=csv,noheader,nounits"],
                               capture_output=True, text=True, timeout=2)
            if r.returncode == 0 and r.stdout.strip():
                line = r.stdout.strip().splitlines()[0]
                parts = [p.strip() for p in line.split(",")]
                if len(parts) >= 2:
                    return {"kind": "nvidia", "model": parts[0], "vram_gb": float(parts[1]) / 1024}
        except Exception:
            pass
        # AMD ROCm
        try:
            r = subprocess.run(["rocm-smi", "--showmeminfo", "vram"],
                               capture_output=True, text=True, timeout=2)
            if r.returncode == 0 and "MB" in r.stdout:
                return {"kind": "amd", "model": "ROCm GPU", "vram_gb": 8}
        except Exception:
            pass
        return {"kind": "none", "model": None, "vram_gb": 0}

    def load_pct():
        try:
            l = os.getloadavg()[0]
            return min(100.0, l * 100 / cpu_cores())
        except Exception:
            return 0.0

    def ram_used_pct():
        try:
            mem = {}
            with open("/proc/meminfo") as f:
                for line in f:
                    if ":" in line:
                        k, v = line.split(":", 1)
                        mem[k.strip()] = int(v.split()[0])
            total = mem.get("MemTotal", 1)
            available = mem.get("MemAvailable", total)
            return round(100 * (total - available) / total, 1)
        except Exception:
            return 0.0

    def gpu_used_pct():
        try:
            r = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu",
                                "--format=csv,noheader,nounits"],
                               capture_output=True, text=True, timeout=2)
            if r.returncode == 0:
                return float(r.stdout.strip().splitlines()[0])
        except Exception:
            pass
        return 0.0

    def http_post(path, body):
        url = GATEWAY + path
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST",
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())

    def register():
        gpu = detect_gpu()
        payload = {
            "device_id": DEVICE_ID,
            "name": DEVICE_NAME,
            "endpoint": ENDPOINT,
            "capabilities": {
                "cpu_cores": cpu_cores(),
                "cpu_model": cpu_model(),
                "ram_gb": ram_gb(),
                "disk_free_gb": disk_free_gb(),
                "gpu": gpu,
                "arch": os.uname().machine,
                "os": "linux",
            },
            "roles": (["worker", "gpu-server"] if gpu["kind"] != "none" else ["worker"]),
        }
        print(json.dumps({"event": "register", "payload": payload}), flush=True)
        return http_post("/solem/cluster/register", payload)

    def beat():
        payload = {
            "device_id": DEVICE_ID,
            "load_pct": load_pct(),
            "ram_used_pct": ram_used_pct(),
            "gpu_used_pct": gpu_used_pct(),
            "inflight_tasks": 0,
        }
        return http_post("/solem/cluster/heartbeat", payload)

    def main():
        # Register con retry (gateway può tardare al boot)
        for attempt in range(20):
            try:
                register()
                print(json.dumps({"event": "registered"}), flush=True)
                break
            except (urllib.error.URLError, OSError) as e:
                print(json.dumps({"event": "register_fail", "attempt": attempt, "err": str(e)}), flush=True)
                time.sleep(5)
        # Heartbeat loop
        while True:
            try:
                beat()
            except (urllib.error.URLError, OSError) as e:
                print(json.dumps({"event": "beat_fail", "err": str(e)}), flush=True)
            time.sleep(30)

    if __name__ == "__main__":
        main()
  '';
in {
  options.solem.cluster = {
    enable = lib.mkEnableOption "Worker cluster (registra device + heartbeat al gateway)";

    role = lib.mkOption {
      type = lib.types.enum [ "gateway" "worker" "both" ];
      default = "both";
      description = ''
        - gateway: ospita il registry (solem-api con cluster.py)
        - worker:  questo nodo si registra a un altro gateway
        - both:    locale fa entrambe (single-box default)
      '';
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8001";
      description = "URL gateway (mesh-only). Es. http://beelink.solem.local:8001";
    };

    deviceName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
    };

    enableLlamaRpc = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Avvia llama.cpp RPC server (porta 50052) per inference distribuita.
        Permette a un altro nodo SOLEM di usare la GPU di QUESTO nodo.
      '';
    };

    llamaRpcPort = lib.mkOption {
      type = lib.types.port;
      default = 50052;
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Worker daemon ──
    systemd.services.solem-cluster-worker = lib.mkIf (cfg.role != "gateway") {
      description = "SOLEM — cluster worker (register + heartbeat)";
      after = [ "network-online.target" "solem-api.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        SOLEM_CLUSTER_GATEWAY = cfg.gateway;
        SOLEM_DEVICE_NAME = cfg.deviceName;
      };
      serviceConfig = {
        Type = "simple";
        User = "gavio";
        ExecStart = workerScript;
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # ── llama.cpp RPC server (opzionale, su nodi GPU) ──
    systemd.services.solem-llama-rpc = lib.mkIf cfg.enableLlamaRpc {
      description = "SOLEM — llama.cpp RPC server (distributed inference)";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "gavio";
        ExecStart = "${pkgs.llama-cpp}/bin/rpc-server -p ${toString cfg.llamaRpcPort} -H 0.0.0.0";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enableLlamaRpc [ cfg.llamaRpcPort ];

    environment.systemPackages = [ pkgs.llama-cpp ];
  };
}
