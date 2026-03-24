# setup-remote-control.ps1
# Windows PC 원격 제어 환경 통합 설정 스크립트
# - OpenSSH 서버 설치 및 설정
# - RDP(원격 데스크톱) 활성화
# - Parsec 설치 확인 및 방화벽 규칙 설정
# - 절전 모드 비활성화
#
# 실행 방법 (관리자 PowerShell):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\setup-remote-control.ps1

#Requires -RunAsAdministrator

$RED    = "Red"
$GREEN  = "Green"
$YELLOW = "Yellow"
$CYAN   = "Cyan"
$BLUE   = "Blue"

function Log-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor $GREEN }
function Log-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor $YELLOW }
function Log-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor $RED }
function Log-Info { param($msg) Write-Host "       $msg" }
function Log-Fix  { param($msg) Write-Host "[FIX]  $msg" -ForegroundColor $BLUE }
function Log-Step { param($msg) Write-Host "`n▶ $msg" -ForegroundColor $CYAN }

Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PC 원격 제어 환경 설정 (Windows)       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$STEPS_OK   = 0
$STEPS_WARN = 0

# ─────────────────────────────────────────────
# 1. OpenSSH 서버 설치 및 설정
# ─────────────────────────────────────────────
Log-Step "[1/5] OpenSSH 서버 설정"

$sshCapability = Get-WindowsCapability -Online -Name "OpenSSH.Server*" -ErrorAction SilentlyContinue
if ($sshCapability -and $sshCapability.State -ne "Installed") {
    Log-Fix "OpenSSH 서버 설치 중..."
    Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" | Out-Null
    Log-Ok "OpenSSH 서버 설치 완료"
    $STEPS_OK++
} elseif ($sshCapability.State -eq "Installed") {
    Log-Ok "OpenSSH 서버 이미 설치됨"
    $STEPS_OK++
} else {
    Log-Warn "OpenSSH 기능 확인 불가 — Windows 설정에서 수동 설치 필요"
    $STEPS_WARN++
}

# SSH 서비스 시작 및 자동 시작 설정
$sshService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
if ($sshService) {
    Set-Service -Name "sshd" -StartupType Automatic
    if ($sshService.Status -ne "Running") {
        Start-Service -Name "sshd"
    }
    Log-Ok "SSH 서비스 자동 시작 설정 완료"
}

# 기본 쉘 PowerShell 로 설정
$regPath = "HKLM:\SOFTWARE\OpenSSH"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "DefaultShell" -Value (Get-Command powershell).Source -ErrorAction SilentlyContinue
Log-Info "SSH 기본 쉘: PowerShell"

# 현재 IP 출력
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress
Log-Info "SSH 접속: ssh $env:USERNAME@$localIP"

# ─────────────────────────────────────────────
# 2. RDP (원격 데스크톱) 활성화
# ─────────────────────────────────────────────
Log-Step "[2/5] RDP(원격 데스크톱) 설정"

$rdpReg = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
$currentRdp = (Get-ItemProperty -Path $rdpReg -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections

if ($currentRdp -eq 0) {
    Log-Ok "RDP 이미 활성화됨"
    $STEPS_OK++
} else {
    Set-ItemProperty -Path $rdpReg -Name "fDenyTSConnections" -Value 0 -Type DWord
    Log-Fix "RDP 활성화 완료"
    $STEPS_OK++
}

# NLA(네트워크 수준 인증) — 보안 권장
$nlaPath = "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
Set-ItemProperty -Path $nlaPath -Name "UserAuthentication" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Log-Info "NLA(네트워크 수준 인증) 활성화됨 (보안)"

# RDP 방화벽 규칙
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
Log-Ok "RDP 방화벽 규칙 활성화 완료 (포트 3389)"

# ─────────────────────────────────────────────
# 3. Parsec 방화벽 설정
# ─────────────────────────────────────────────
Log-Step "[3/5] Parsec 방화벽 설정"

$parsecPaths = @(
    "$env:LocalAppData\Parsec\parsecd.exe",
    "C:\Program Files\Parsec\parsecd.exe",
    "C:\Program Files (x86)\Parsec\parsecd.exe"
)

$parsecBin = $parsecPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($parsecBin) {
    Log-Ok "Parsec 설치됨: $parsecBin"

    # 방화벽 규칙 추가 (이미 있으면 스킵)
    $existingRule = Get-NetFirewallRule -DisplayName "Parsec Remote Desktop" -ErrorAction SilentlyContinue
    if (-not $existingRule) {
        New-NetFirewallRule -DisplayName "Parsec Remote Desktop" `
            -Direction Inbound -Action Allow `
            -Program $parsecBin `
            -Protocol TCP -LocalPort 8000 | Out-Null
        New-NetFirewallRule -DisplayName "Parsec Remote Desktop UDP" `
            -Direction Inbound -Action Allow `
            -Program $parsecBin `
            -Protocol UDP -LocalPort 8000 | Out-Null
        Log-Fix "Parsec 방화벽 규칙 추가 완료 (포트 8000 TCP/UDP)"
    } else {
        Log-Ok "Parsec 방화벽 규칙 이미 존재함"
    }
    $STEPS_OK++
} else {
    Log-Warn "Parsec이 설치되지 않음"
    Log-Info "다운로드: https://parsec.app/downloads"
    Log-Info "설치 후 이 스크립트를 다시 실행하세요"
    $STEPS_WARN++
}

# ─────────────────────────────────────────────
# 4. 절전 모드 비활성화 (원격 접속 유지용)
# ─────────────────────────────────────────────
Log-Step "[4/5] 절전 모드 비활성화"

try {
    # 고성능 전원 관리 계획 설정
    powercfg /setactive SCHEME_MIN 2>/dev/null
    # 절전 타임아웃 비활성화
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    powercfg /change monitor-timeout-ac 0
    Log-Fix "절전 모드 비활성화 완료 (전원 연결 시)"
    $STEPS_OK++
} catch {
    Log-Warn "절전 모드 설정 실패: $_"
    $STEPS_WARN++
}

# 원격 연결 시 화면 잠금 방지 (Parsec 요구사항)
$screenSaverPath = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $screenSaverPath -Name "ScreenSaveActive" -Value "0" -ErrorAction SilentlyContinue
Log-Ok "화면 보호기 비활성화"

# ─────────────────────────────────────────────
# 5. Windows Defender 방화벽 — 원격 접속 포트 일괄 개방
# ─────────────────────────────────────────────
Log-Step "[5/5] 방화벽 포트 일괄 설정"

$ports = @(
    @{Port=22;   Proto="TCP"; Name="SSH"},
    @{Port=3389; Proto="TCP"; Name="RDP"},
    @{Port=8000; Proto="TCP"; Name="Parsec TCP"},
    @{Port=8000; Proto="UDP"; Name="Parsec UDP"}
)

foreach ($p in $ports) {
    $ruleName = "Remote-Control: $($p.Name)"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName $ruleName `
            -Direction Inbound -Action Allow `
            -Protocol $p.Proto -LocalPort $p.Port | Out-Null
        Log-Fix "방화벽 규칙 추가: $($p.Name) ($($p.Proto)/$($p.Port))"
    } else {
        Log-Ok "방화벽 규칙 이미 존재: $($p.Name)"
    }
}
$STEPS_OK++

# ─────────────────────────────────────────────
# 요약
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║             설정 완료 요약               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  성공: $STEPS_OK 건 | 경고: $STEPS_WARN 건"
Write-Host ""
Write-Host "▶ 원격 접속 정보:" -ForegroundColor Yellow
Write-Host "  • SSH   : ssh $env:USERNAME@$localIP  (포트 22)"
Write-Host "  • RDP   : mstsc → $localIP  (포트 3389)"
Write-Host "  • Parsec: https://parsec.app 에서 동일 계정으로 접속"
Write-Host ""
Write-Host "▶ Parsec -14003 오류 발생 시:" -ForegroundColor Yellow
Write-Host "  .\fix-parsec-wddm.ps1  (WDDM → XDDM 전환)"
Write-Host ""
Write-Host "▶ 보안 권고사항:" -ForegroundColor Yellow
Write-Host "  1. SSH 키 인증 설정 후 비밀번호 인증 비활성화"
Write-Host "  2. RDP 포트를 기본(3389)에서 변경 권장"
Write-Host "  3. Parsec은 계정 기반 암호화 연결이므로 별도 조치 불필요"
Write-Host ""
