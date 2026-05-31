{ config, pkgs, lib, ... }:

# SOLEM WEB DASHBOARD — Step 36: Friday HUD nel browser.

let
  cfg = config.solem.webDashboard;

  serverScript = pkgs.writers.writePython3Bin "solem-dashboard-server" {
    libraries = [ ];
    flakeIgnore = [ "E501" "E302" "W291" "W293" "E305" "E402" ];
  } ''
    """SOLEM Web Dashboard — Friday HUD nel browser (stdlib only)."""
    import json
    import os
    import socketserver
    import subprocess
    from datetime import datetime, timezone
    from http.server import BaseHTTPRequestHandler
    from pathlib import Path

    PORT = int(os.environ.get("LISTEN_PORT", "8088"))
    BIND = os.environ.get("LISTEN_BIND", "127.0.0.1")

    def run(cmd, timeout=5):
        try:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
            return r.stdout.strip()
        except Exception:
            return ""

    def collect_status():
        s = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "host": os.uname().nodename,
            "uptime": run("uptime -p"),
            "kernel": os.uname().release,
            "load": run("cut -d' ' -f1-3 /proc/loadavg"),
            "cpu_pct": None, "mem_pct": None, "disk_root_pct": None,
            "redteam": None, "services": {}, "markers": [],
        }
        try:
            line = open("/proc/stat").readline().split()
            idle = int(line[4]); total = sum(int(x) for x in line[1:8])
            s["cpu_pct"] = round(100 - idle * 100 / total, 1) if total else 0
        except Exception:
            pass
        try:
            mem = {}
            for line in open("/proc/meminfo"):
                k, v = line.split(":")
                mem[k.strip()] = int(v.strip().split()[0])
            total = mem.get("MemTotal", 1)
            avail = mem.get("MemAvailable", 0)
            s["mem_pct"] = round((total - avail) * 100 / total, 1)
        except Exception:
            pass
        try:
            stat = os.statvfs("/")
            s["disk_root_pct"] = round(100 - (stat.f_bavail * 100 / stat.f_blocks), 1)
        except Exception:
            pass

        rt_dir = Path("/var/log/solem/redteam")
        if rt_dir.exists():
            jsons = sorted(rt_dir.glob("*.json"), reverse=True)
            if jsons:
                try:
                    s["redteam"] = json.loads(jsons[0].read_text())["summary"]
                except Exception:
                    pass

        for marker_path in ["/var/lib/solem/CANARY_TRIPPED",
                            "/var/lib/solem/MODEL_TAMPERED",
                            "/var/lib/solem/IDS_ALERT"]:
            if Path(marker_path).exists():
                s["markers"].append({"path": marker_path,
                                     "size": Path(marker_path).stat().st_size})

        services_to_check = [
            "gavio", "ollama", "auditd",
            "solem-canary-watcher", "solem-prompt-filter",
            "tor", "fail2ban", "suricata", "usbguard", "unbound", "nginx",
            "prometheus", "grafana", "loki",
        ]
        for svc in services_to_check:
            s["services"][svc] = run(f"systemctl is-active {svc}.service", timeout=2) or "n/a"
        return s

    HTML = """<!DOCTYPE html><html lang='it'><head><meta charset='utf-8'><title>SOLEM Friday HUD</title>
    <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Segoe UI',system-ui,sans-serif;background:linear-gradient(135deg,#0B1426,#1A2540);color:#F5F5F5;padding:20px;min-height:100vh}
    h1{color:#D4A24A;font-weight:300;letter-spacing:4px;margin-bottom:8px}
    .subtitle{color:#888;font-size:14px;margin-bottom:24px}
    .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}
    .card{background:rgba(212,162,74,.05);border:1px solid rgba(212,162,74,.2);border-radius:8px;padding:16px}
    .card h2{color:#D4A24A;font-size:13px;text-transform:uppercase;letter-spacing:2px;margin-bottom:12px}
    .stat{font-size:32px;font-weight:200}
    .stat-label{font-size:11px;color:#888;text-transform:uppercase}
    .bar{width:100%;height:4px;background:rgba(255,255,255,.1);border-radius:2px;margin-top:8px;overflow:hidden}
    .bar-fill{height:100%;background:#D4A24A;transition:width .3s}
    .bar-fill.warn{background:#ff9800}
    .bar-fill.danger{background:#f44336}
    .svc-list{display:grid;grid-template-columns:1fr 1fr;gap:4px;font-size:12px}
    .svc-active{color:#4caf50}
    .svc-inactive{color:#888}
    .alert{background:rgba(244,67,54,.2);border:2px solid #f44336;padding:12px;border-radius:4px;margin-bottom:16px}
    .ok{color:#4caf50}
    .danger{color:#f44336}
    .footer{margin-top:24px;font-size:11px;color:#555;text-align:center}
    </style></head><body>
    <h1>SOLEM</h1>
    <div class='subtitle'>Friday HUD - Updated <span id='ts'>...</span></div>
    <div id='alerts'></div>
    <div class='grid'>
      <div class='card'><h2>System</h2><div class='stat' id='hostname'>-</div>
        <div class='stat-label'>Host - <span id='kernel'>-</span></div>
        <div style='margin-top:12px;font-size:12px'>Uptime: <span id='uptime'>-</span></div>
        <div style='font-size:12px'>Load: <span id='load'>-</span></div></div>
      <div class='card'><h2>CPU</h2><div class='stat'><span id='cpu_pct'>-</span>%</div>
        <div class='bar'><div class='bar-fill' id='cpu_bar' style='width:0%'></div></div></div>
      <div class='card'><h2>Memory</h2><div class='stat'><span id='mem_pct'>-</span>%</div>
        <div class='bar'><div class='bar-fill' id='mem_bar' style='width:0%'></div></div></div>
      <div class='card'><h2>Disk Root</h2><div class='stat'><span id='disk_pct'>-</span>%</div>
        <div class='bar'><div class='bar-fill' id='disk_bar' style='width:0%'></div></div></div>
      <div class='card' style='grid-column:span 2'><h2>Last Red-Team</h2>
        <div id='redteam-summary'>No report</div></div>
      <div class='card' style='grid-column:span 2'><h2>Services</h2>
        <div class='svc-list' id='services'>-</div></div>
    </div>
    <div class='footer'>SOLEM Friday Mode - solem-dashboard-server</div>
    <script>
    async function refresh(){
      try{
        const r=await fetch('/api/status');const s=await r.json();
        document.getElementById('ts').textContent=new Date().toLocaleTimeString();
        document.getElementById('hostname').textContent=s.host;
        document.getElementById('kernel').textContent=s.kernel;
        document.getElementById('uptime').textContent=s.uptime||'?';
        document.getElementById('load').textContent=s.load||'?';
        function setBar(id,pct){
          const el=document.getElementById(id+'_pct');const bar=document.getElementById(id+'_bar');
          if(pct===null||pct===undefined){el.textContent='?';return;}
          el.textContent=pct;bar.style.width=pct+'%';
          bar.className='bar-fill'+(pct>90?' danger':pct>70?' warn':"");
        }
        setBar('cpu',s.cpu_pct);setBar('mem',s.mem_pct);setBar('disk',s.disk_root_pct);
        const rt=document.getElementById('redteam-summary');
        if(s.redteam){
          const b=s.redteam.buchi||0;
          rt.innerHTML='<span class="'+(b>0?'danger':'ok')+'">'+b+' buchi</span> - '+s.redteam.blocked+' blocked - '+s.redteam.total+' total';
        }
        const alerts=document.getElementById('alerts');alerts.innerHTML="";
        for(const m of s.markers||[]){alerts.innerHTML+='<div class="alert">CRITICAL marker: '+m.path+'</div>';}
        const svc=document.getElementById('services');svc.innerHTML="";
        for(const [name,state] of Object.entries(s.services)){
          const cls=state==='active'?'svc-active':'svc-inactive';
          const icon=state==='active'?'OK':'--';
          svc.innerHTML+='<span class="'+cls+'">'+icon+' '+name+': '+state+'</span>';
        }
      }catch(e){console.error('refresh fail',e);}
    }
    refresh();setInterval(refresh,10000);
    </script></body></html>"""

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args): pass
        def do_GET(self):
            if self.path == "/":
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("X-Frame-Options", "DENY")
                self.end_headers()
                self.wfile.write(HTML.encode("utf-8"))
            elif self.path == "/api/status":
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(collect_status()).encode("utf-8"))
            else:
                self.send_response(404); self.end_headers()

    class TCPServer(socketserver.ThreadingTCPServer):
        allow_reuse_address = True

    if __name__ == "__main__":
        with TCPServer((BIND, PORT), Handler) as srv:
            print(f"SOLEM Dashboard listening on http://{BIND}:{PORT}", flush=True)
            srv.serve_forever()
  '';
in {
  options.solem.webDashboard = {
    enable = lib.mkEnableOption "SOLEM web dashboard Friday HUD (browser)";
    port = lib.mkOption { type = lib.types.port; default = 8088; };
    bind = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.solem-dashboard = {
      description = "SOLEM Web Dashboard (Friday HUD)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        LISTEN_PORT = toString cfg.port;
        LISTEN_BIND = cfg.bind;
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${serverScript}/bin/solem-dashboard-server";
        Restart = "on-failure";
        RestartSec = 10;
        User = "root";
        ProtectSystem = "strict";
        ReadOnlyPaths = [ "/var/log/solem" "/var/lib/solem" "/proc" ];
        PrivateTmp = true;
      };
    };

    environment.systemPackages = [
      serverScript
      (pkgs.writeShellApplication {
        name = "solem-dashboard";
        runtimeInputs = with pkgs; [ coreutils curl xdg-utils ];
        text = ''
          ACTION="''${1:-open}"
          URL="http://${cfg.bind}:${toString cfg.port}/"
          case "$ACTION" in
            open|browse) xdg-open "$URL" 2>/dev/null || echo "Visita: $URL" ;;
            status) systemctl status solem-dashboard --no-pager 2>/dev/null | head -10; echo "URL: $URL" ;;
            json) curl -s "$URL/api/status" | head -200 ;;
            *) echo "Usage: solem-dashboard {open|status|json}" ;;
          esac
        '';
      })
    ];
  };
}
