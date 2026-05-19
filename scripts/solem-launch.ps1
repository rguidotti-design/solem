# SOLEM Launch — esperienza "OS visibile" su Windows
#
# Lancia VM SOLEM headless (no finestra QEMU) + apre browser fullscreen
# sulla dashboard navy come "il sistema operativo".
#
# Uso: .\scripts\solem-launch.ps1
# Per chiudere: Ctrl-C nella finestra terminale + chiudi browser fullscreen (F11)

$ErrorActionPreference = "Continue"
$SolemRoot = Split-Path -Parent $PSScriptRoot
$WslPath = ($SolemRoot -replace '^([A-Za-z]):', '/mnt/$1' -replace '\\', '/').ToLower()

Write-Host ""
Write-Host "  SOLEM — AI-native OS" -ForegroundColor DarkYellow
Write-Host "  Avvio sistema..." -ForegroundColor DarkGray
Write-Host ""

# 1. Kill VM precedente se esiste
Write-Host "  [1/3] Pulizia VM precedente..." -ForegroundColor DarkGray
wsl -d Ubuntu -- bash -c "pkill -9 -f qemu-kvm 2>/dev/null; sleep 1" | Out-Null

# 2. Lancia VM SOLEM headless in background WSL
Write-Host "  [2/3] Boot VM SOLEM (headless, ~2-4 min in TCG)..." -ForegroundColor DarkGray
$wslCmd = ". ~/.nix-profile/etc/profile.d/nix.sh && cd '$WslPath' && rm -f solem.qcow2 && nohup nix run .#vm > /tmp/solem.log 2>&1 &"
wsl -d Ubuntu -- bash -lc "$wslCmd" | Out-Null

# 3. Polling fino a quando :8001 risponde
Write-Host "  [3/3] Attendo SOLEM API..." -ForegroundColor DarkGray
$maxWait = 600  # 10 minuti max
$elapsed = 0
$apiReady = $false
while ($elapsed -lt $maxWait) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:8001/health" -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) {
            $apiReady = $true
            break
        }
    } catch {
        # ignore, retry
    }
    Start-Sleep -Seconds 3
    $elapsed += 3
    if ($elapsed % 30 -eq 0) {
        Write-Host "        ...attendo SOLEM API (${elapsed}s/${maxWait}s)" -ForegroundColor DarkGray
    }
}

if (-not $apiReady) {
    Write-Host ""
    Write-Host "  TIMEOUT — SOLEM API non risponde dopo ${maxWait}s." -ForegroundColor Red
    Write-Host "  Vedi log: wsl -- cat /tmp/solem.log" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "  SOLEM ATTIVO." -ForegroundColor Green
Write-Host "  Apertura dashboard a fullscreen..." -ForegroundColor DarkYellow
Write-Host ""

# 4. Apri browser su localhost:8001 a fullscreen (kiosk mode)
# Preferenza: Edge (preinstallato Windows) → Chrome → Firefox → default browser

$browsers = @(
    @{ name = "Microsoft Edge"; path = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; args = "--kiosk http://localhost:8001 --edge-kiosk-type=fullscreen --no-first-run" },
    @{ name = "Microsoft Edge (alt)"; path = "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"; args = "--kiosk http://localhost:8001 --edge-kiosk-type=fullscreen --no-first-run" },
    @{ name = "Google Chrome"; path = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"; args = "--kiosk http://localhost:8001 --no-first-run" },
    @{ name = "Firefox"; path = "${env:ProgramFiles}\Mozilla Firefox\firefox.exe"; args = "--kiosk http://localhost:8001" }
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
    Write-Host "  Nessun browser trovato. Apri manualmente: http://localhost:8001" -ForegroundColor Yellow
    Start-Process "http://localhost:8001"
}

Write-Host ""
Write-Host "  La dashboard SOLEM e' aperta a fullscreen." -ForegroundColor Green
Write-Host "  Per uscire dal kiosk browser: ALT+F4 (Edge) o F11 (toggle fullscreen)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  VM rimane viva in background. Per spegnerla:" -ForegroundColor DarkGray
Write-Host "    wsl -- pkill -9 -f qemu-kvm" -ForegroundColor DarkYellow
Write-Host ""
