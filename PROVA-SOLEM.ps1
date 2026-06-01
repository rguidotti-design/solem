# PROVA-SOLEM.ps1 — wrapper PowerShell per provare SOLEM
#
# Esegue automaticamente PROVA-SOLEM.sh dentro WSL Ubuntu.
#
# Uso:
#   Apri PowerShell e digita:
#     irm https://raw.githubusercontent.com/rguidotti-design/solem/main/PROVA-SOLEM.ps1 | iex
#
# Oppure scarica + esegui:
#   curl.exe -O https://raw.githubusercontent.com/rguidotti-design/solem/main/PROVA-SOLEM.ps1
#   powershell -ExecutionPolicy Bypass -File PROVA-SOLEM.ps1

$ErrorActionPreference = "Stop"

function Show-Banner {
@"

================================================================

       SOLEM - AI-native OS - prova in 5-30 minuti

   Wrapper PowerShell:
     1. Verifica WSL Ubuntu installato
     2. Esegue PROVA-SOLEM.sh dentro Ubuntu
     3. Build VM SOLEM + lancia QEMU

================================================================

"@
}

function Test-WSL {
    Write-Host "`n>> Step 1: Verifica WSL..." -ForegroundColor Cyan
    try {
        $wslOk = wsl --status 2>&1 | Out-String
        if ($wslOk -match "WSL") {
            Write-Host "OK WSL disponibile" -ForegroundColor Green
        }
        $distros = wsl -l -q 2>&1 | Out-String
        if ($distros -match "Ubuntu") {
            Write-Host "OK Distribuzione Ubuntu trovata" -ForegroundColor Green
            return $true
        } else {
            Write-Host "X Ubuntu NON installato in WSL" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "X WSL NON installato" -ForegroundColor Red
        return $false
    }
}

function Install-WSL {
    Write-Host "`n>> Installazione WSL Ubuntu (richiede sudo + reboot)..." -ForegroundColor Cyan
    Write-Host "Esegui in PowerShell ELEVATO (Admin):" -ForegroundColor Yellow
    Write-Host "  wsl --install -d Ubuntu" -ForegroundColor White
    Write-Host ""
    Write-Host "Dopo reboot:" -ForegroundColor Yellow
    Write-Host "  1. Si apre Ubuntu setup" -ForegroundColor White
    Write-Host "  2. Scegli username + password Linux" -ForegroundColor White
    Write-Host "  3. Ri-esegui questo script PowerShell" -ForegroundColor White
    exit 1
}

function Invoke-SolemSetup {
    Write-Host "`n>> Step 2: Lancio PROVA-SOLEM.sh dentro Ubuntu..." -ForegroundColor Cyan
    Write-Host "(scarica script + esegue tutto auto)" -ForegroundColor Gray
    Write-Host ""

    # Esegue dentro WSL Ubuntu
    $cmd = "bash <(curl -sSL https://raw.githubusercontent.com/rguidotti-design/solem/main/PROVA-SOLEM.sh)"
    wsl -d Ubuntu -- bash -lc $cmd
}

function Show-Manual {
    Write-Host ""
    Write-Host "Se vuoi farlo a mano:" -ForegroundColor Cyan
    Write-Host "  1. Apri PowerShell, digita: wsl" -ForegroundColor White
    Write-Host "  2. Una volta dentro Ubuntu, incolla:" -ForegroundColor White
    Write-Host "     bash <(curl -sSL https://raw.githubusercontent.com/rguidotti-design/solem/main/PROVA-SOLEM.sh)" -ForegroundColor Yellow
    Write-Host ""
}

# Main
Show-Banner

if (-not (Test-WSL)) {
    Install-WSL
    exit 1
}

Write-Host "`nWSL Ubuntu pronto. Avvio SOLEM setup..." -ForegroundColor Green
Write-Host "Premi Ctrl-C per annullare, qualsiasi tasto per continuare..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Invoke-SolemSetup

Show-Manual
