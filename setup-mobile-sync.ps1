# setup-mobile-sync.ps1
# Android-PC 파일/클립보드 연동 환경 자동 설정
# KDE Connect + LocalSend 설치 및 방화벽 구성
#
# 실행 방법 (관리자 PowerShell):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\setup-mobile-sync.ps1

#Requires -RunAsAdministrator

$GREEN  = "Green"
$YELLOW = "Yellow"
$RED    = "Red"
$CYAN   = "Cyan"

function Log-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor $GREEN }
function Log-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor $YELLOW }
function Log-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor $RED }
function Log-Info { param($msg) Write-Host "       $msg" }
function Log-Step { param($msg) Write-Host "[>>]   $msg" -ForegroundColor $CYAN }

Write-Host ""
Write-Host "=== Android-PC 모바일 연동 설정 ===" -ForegroundColor Cyan
Write-Host "    KDE Connect + LocalSend 자동 설치"
Write-Host ""

$INSTALLED = @()

# ─────────────────────────────────────────────
# 1. winget 사용 가능 여부 확인
# ─────────────────────────────────────────────
Log-Step "[1/5] winget 패키지 관리자 확인..."

try {
    $wingetVer = winget --version 2>$null
    if ($wingetVer) {
        Log-Ok "winget $wingetVer 사용 가능"
    } else {
        throw "winget not found"
    }
} catch {
    Log-Err "winget을 찾을 수 없습니다"
    Log-Info "Microsoft Store에서 '앱 설치 관리자'를 설치하세요"
    Log-Info "또는: https://aka.ms/getwinget"
    exit 1
}

# ─────────────────────────────────────────────
# 2. KDE Connect 설치
# ─────────────────────────────────────────────
Write-Host ""
Log-Step "[2/5] KDE Connect 설치..."
Log-Info "기능: 클립보드 공유, 파일 전송, 알림 동기화, 원격 입력"

$kdeInstalled = winget list --id "KDE.KDEConnect" 2>$null | Select-String "KDE.KDEConnect"
if ($kdeInstalled) {
    Log-Ok "KDE Connect 이미 설치됨"
} else {
    Log-Info "KDE Connect 설치 중..."
    winget install --id "KDE.KDEConnect" --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Log-Ok "KDE Connect 설치 완료"
        $INSTALLED += "KDE Connect"
    } else {
        Log-Err "KDE Connect 설치 실패 (수동 설치: https://kdeconnect.kde.org)"
    }
}

# ─────────────────────────────────────────────
# 3. LocalSend 설치
# ─────────────────────────────────────────────
Write-Host ""
Log-Step "[3/5] LocalSend 설치..."
Log-Info "기능: 같은 네트워크에서 AirDrop처럼 파일 즉시 전송"

$localSendInstalled = winget list --id "LocalSend.LocalSend" 2>$null | Select-String "LocalSend"
if ($localSendInstalled) {
    Log-Ok "LocalSend 이미 설치됨"
} else {
    Log-Info "LocalSend 설치 중..."
    winget install --id "LocalSend.LocalSend" --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Log-Ok "LocalSend 설치 완료"
        $INSTALLED += "LocalSend"
    } else {
        Log-Err "LocalSend 설치 실패 (수동 설치: https://localsend.org)"
    }
}

# ─────────────────────────────────────────────
# 4. Windows 방화벽 규칙 설정
# ─────────────────────────────────────────────
Write-Host ""
Log-Step "[4/5] Windows 방화벽 규칙 설정..."

# KDE Connect 포트: TCP/UDP 1714-1764
$kdeRuleName = "KDE Connect (TCP+UDP 1714-1764)"
$existingKdeRule = Get-NetFirewallRule -DisplayName $kdeRuleName -ErrorAction SilentlyContinue

if ($existingKdeRule) {
    Log-Ok "KDE Connect 방화벽 규칙 이미 존재"
} else {
    try {
        # TCP 인바운드
        New-NetFirewallRule -DisplayName "$kdeRuleName - TCP In" `
            -Direction Inbound -Protocol TCP `
            -LocalPort 1714-1764 -Action Allow `
            -Profile Private -ErrorAction Stop | Out-Null

        # UDP 인바운드
        New-NetFirewallRule -DisplayName "$kdeRuleName - UDP In" `
            -Direction Inbound -Protocol UDP `
            -LocalPort 1714-1764 -Action Allow `
            -Profile Private -ErrorAction Stop | Out-Null

        # TCP 아웃바운드
        New-NetFirewallRule -DisplayName "$kdeRuleName - TCP Out" `
            -Direction Outbound -Protocol TCP `
            -LocalPort 1714-1764 -Action Allow `
            -Profile Private -ErrorAction Stop | Out-Null

        # UDP 아웃바운드
        New-NetFirewallRule -DisplayName "$kdeRuleName - UDP Out" `
            -Direction Outbound -Protocol UDP `
            -LocalPort 1714-1764 -Action Allow `
            -Profile Private -ErrorAction Stop | Out-Null

        Log-Ok "KDE Connect 방화벽 규칙 추가 완료 (Private 네트워크)"
    } catch {
        Log-Err "KDE Connect 방화벽 규칙 추가 실패: $_"
    }
}

# LocalSend 포트: TCP/UDP 53317
$lsRuleName = "LocalSend (TCP+UDP 53317)"
$existingLsRule = Get-NetFirewallRule -DisplayName $lsRuleName -ErrorAction SilentlyContinue

if ($existingLsRule) {
    Log-Ok "LocalSend 방화벽 규칙 이미 존재"
} else {
    try {
        New-NetFirewallRule -DisplayName "$lsRuleName - TCP In" `
            -Direction Inbound -Protocol TCP `
            -LocalPort 53317 -Action Allow `
            -Profile Private -ErrorAction Stop | Out-Null

        New-NetFirewallRule -DisplayName "$lsRuleName - UDP In" `
            -Direction Inbound -Protocol UDP `
            -LocalPort 53317 -Action Allow `
            -Profile Private -ErrorAction Stop | Out-Null

        Log-Ok "LocalSend 방화벽 규칙 추가 완료 (Private 네트워크)"
    } catch {
        Log-Err "LocalSend 방화벽 규칙 추가 실패: $_"
    }
}

# ─────────────────────────────────────────────
# 5. 요약 및 Android 측 안내
# ─────────────────────────────────────────────
Write-Host ""
Log-Step "[5/5] 설정 완료 요약"
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

if ($INSTALLED.Count -gt 0) {
    Write-Host "  새로 설치됨: $($INSTALLED -join ', ')" -ForegroundColor Green
}

Write-Host ""
Write-Host "  [Android 앱 설치 필요]" -ForegroundColor Yellow
Write-Host "  1. KDE Connect  - Play Store에서 설치"
Write-Host "     → 클립보드 공유, 파일 전송, 알림, 원격 입력"
Write-Host ""
Write-Host "  2. LocalSend    - Play Store에서 설치"
Write-Host "     → 대용량 파일 빠른 전송 (AirDrop 대체)"
Write-Host ""
Write-Host "  [페어링 방법]" -ForegroundColor Yellow
Write-Host "  1. PC와 폰을 같은 Wi-Fi에 연결"
Write-Host "  2. PC에서 KDE Connect 실행"
Write-Host "  3. 폰에서 KDE Connect 앱 → 기기 검색 → PC 선택"
Write-Host "  4. 양쪽에서 페어링 승인"
Write-Host ""
Write-Host "  [KDE Connect 추천 설정]" -ForegroundColor Yellow
Write-Host "  - 클립보드 동기화: 설정 → 플러그인 → 클립보드 ON"
Write-Host "  - 알림 동기화:     설정 → 플러그인 → 알림 수신 ON"
Write-Host "  - 파일 전송:       공유 메뉴에서 KDE Connect 선택"
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
