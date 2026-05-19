# Wizard primo setup: crea /etc/gavio/env nella VM da template e apre editor.
#
# Uso: .\scripts\setup-env.ps1
#
# Dopo la modifica, restart automatico di gavio.service.

$ErrorActionPreference = "Stop"

Write-Host "[solem] copio template env e apro editor nella VM..." -ForegroundColor Cyan

ssh -t -p 2222 `
    -o StrictHostKeyChecking=no `
    -o UserKnownHostsFile=NUL `
    -o LogLevel=ERROR `
    gavio@localhost @'
set -e
if [ ! -f /etc/gavio/env ]; then
  sudo cp /etc/gavio/env.example /etc/gavio/env
  sudo chmod 600 /etc/gavio/env
  sudo chown gavio:users /etc/gavio/env
fi
sudo -E vim /etc/gavio/env
echo ""
echo "[solem] restart gavio.service..."
sudo systemctl restart gavio
sleep 2
sudo systemctl status gavio --no-pager -l | head -20
'@
