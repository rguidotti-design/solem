# SOLEM Launch — esperienza "OS visibile" su Windows
#
# Lancia VM SOLEM headless (no finestra QEMU) + apre browser fullscreen
# sulla dashboard navy come "il sistema operativo".
#
# WSL2 NON forwarda automaticamente le porte QEMU al localhost Windows.
# Questo script trova l'IP WSL e apre il browser su quello.
#
# Uso: .\scripts\solem-launch.ps1
# Per chiudere: chiudi browser (Alt+F4) + wsl -- pkill -9 -f qemu-kvm

$ErrorActionPreference = "Continue"
$SolemRoot = Split-Path -Parent $PSScriptRoot
$WslPath = ($SolemRoot -replace '^([A-Za-z]):', '/mnt/$1' -replace '\\', '/').ToLower()

Write-Host ""
Write-Host "  SOLEM - AI-native OS" -ForegroundColor DarkYellow
Write-Host "  Avvio sistema..." -ForegroundColor DarkGray
Write-Host ""

# 1. Pulizia VM precedente
Write-Host "  [1/4] Pulizia VM precedente..." -ForegroundColor DarkGray
wsl -d Ubuntu -- bash -c "pkill -9 -f qemu-kvm 2>/dev/null; sleep 1" | Out-Null

# 2. Trova IP WSL
$wslIp = (wsl -d Ubuntu -- bash -c "hostname -I | awk '{print `$1}'").Trim()
if (-not $wslIp) {
    Write-Host "  ERRORE: WSL non risponde" -ForegroundColor Red
    exit 1
}
Write-Host "  [2/4] IP WSL rilevato: $wslIp" -ForegroundColor DarkGray

# 3. Lancia VM headless in WSL background
Write-Host "  [3/4] Boot VM SOLEM (headless, ~2-4 min in TCG)..." -ForegroundColor DarkGray
$wslCmd = ". ~/.nix-profile/etc/profile.d/nix.sh && cd '$WslPath' && rm -f solem.qcow2 && nohup nix run .#vm > /tmp/solem.log 2>&1 &"
wsl -d Ubuntu -- bash -lc "$wslCmd" | Out-Null

# 4. Polling fino a quando :8001 risponde sull'IP WSL
$dashboardUrl = "http://${wslIp}:8001"
Write-Host "  [4/4] Attendo SOLEM API su $dashboardUrl ..." -ForegroundColor DarkGray
$maxWait = 600
$elapsed = 0
$apiReady = $false
while ($elapsed -lt $maxWait) {
    try {
        $r = Invoke-WebRequest -Uri "$dashboardUrl/health" -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) {
            $apiReady = $true
            break
        }
    } catch {
        # ignora, retry
    }
    Start-Sleep -Seconds 3
    $elapsed += 3
    if ($elapsed % 30 -eq 0) {
        Write-Host "        ...attendo SOLEM API (${elapsed}s/${maxWait}s)" -ForegroundColor DarkGray
    }
}

if (-not $apiReady) {
    Write-Host ""
    Write-Host "  TIMEOUT - API non risponde dopo ${maxWait}s." -ForegroundColor Red
    Write-Host "  Log: wsl -- cat /tmp/solem.log" -ForegroundColor DarkGray
    Write-Host "  Apri manualmente: $dashboardUrl" -ForegroundColor DarkYellow
    Start-Process $dashboardUrl
    exit 1
}

Write-Host ""
Write-Host "  SOLEM ATTIVO su $dashboardUrl" -ForegroundColor Green
Write-Host "  Apertura dashboard a fullscreen..." -ForegroundColor DarkYellow
Write-Host ""

# 5. Apri browser kiosk: Edge > Chrome > Firefox > default
$browsers = @(
    @{ name = "Microsoft Edge";   path = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; args = "--kiosk $dashboardUrl --edge-kiosk-type=fullscreen --no-first-run" },
    @{ name = "Microsoft Edge";   path = "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe";      args = "--kiosk $dashboardUrl --edge-kiosk-type=fullscreen --no-first-run" },
    @{ name = "Google Chrome";    path = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe";       args = "--kiosk $dashboardUrl --no-first-run" },
    @{ name = "Google Chrome 86"; path = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe";  args = "--kiosk $dashboardUrl --no-first-run" },
    @{ name = "Firefox";          path = "${env:ProgramFiles}\Mozilla Firefox\firefox.exe";                args = "--kiosk $dashboardUrl" }
)

$launched = $false
foreach ($b in $browsers) {
    if (Test-Path $b.path) {
        Write-Host "  Browser: $($b.name)" -ForegroundColor DarkGray
        Start-Process -FilePath $b.path -ArgumentList $b.args
        $launched = $true
        break
    }
}

if (-not $launched) {
    Write-Host "  Nessun browser trovato. Apro default browser..." -ForegroundColor Yellow
    Start-Process $dashboardUrl
}

Write-Host ""
Write-Host "  Dashboard SOLEM aperta a fullscreen." -ForegroundColor Green
Write-Host "  URL: $dashboardUrl" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Per uscire: Alt+F4 (chiudi browser)" -ForegroundColor DarkGray
Write-Host "  Per spegnere VM: wsl -- pkill -9 -f qemu-kvm" -ForegroundColor DarkGray
Write-Host ""
