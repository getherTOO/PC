# fix-parsec-wddm.ps1
# Parsec 에러 -14003 해결: RDP + WDDM 충돌 시 XDDM 모드로 전환
# 참고: Windows 10 빌드 1903 이상에서 RDP와 Parsec 동시 사용 시 발생하는 버그 수정
#
# 실행 방법 (관리자 PowerShell):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\fix-parsec-wddm.ps1

#Requires -RunAsAdministrator

$RED    = "Red"
$GREEN  = "Green"
$YELLOW = "Yellow"
$CYAN   = "Cyan"

function Log-Ok   { param($msg) Write-Host "[OK]  $msg" -ForegroundColor $GREEN }
function Log-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor $YELLOW }
function Log-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor $RED }
function Log-Info { param($msg) Write-Host "       $msg" }
function Log-Fix  { param($msg) Write-Host "[FIX]  $msg" -ForegroundColor $CYAN }

Write-Host "=== Parsec -14003 Fix: WDDM → XDDM 전환 ===" -ForegroundColor Cyan
Write-Host ""

$FIXES_APPLIED = 0

# ─────────────────────────────────────────────
# 1. 관리자 권한 확인
# ─────────────────────────────────────────────
Write-Host "▶ [1/5] 관리자 권한 확인..."
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Log-Err "관리자 권한으로 실행해야 합니다."
    Log-Info "PowerShell을 우클릭 → '관리자로 실행' 후 다시 시도하세요."
    exit 1
}
Log-Ok "관리자 권한 확인됨"

# ─────────────────────────────────────────────
# 2. Windows 버전 확인 (1903 이상에서 버그 발생)
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "▶ [2/5] Windows 버전 확인..."
$build = [System.Environment]::OSVersion.Version.Build
$caption = (Get-WmiObject Win32_OperatingSystem).Caption
Log-Ok "OS: $caption (빌드 $build)"

if ($build -ge 18362) {
    Log-Warn "빌드 1903($build) 이상 — RDP+Parsec WDDM 버그 영향 범위입니다"
} else {
    Log-Ok "빌드 $build — WDDM 버그 범위 외 (참고용으로 계속 진행)"
}

# ─────────────────────────────────────────────
# 3. 현재 WDDM 설정 확인
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "▶ [3/5] 현재 WDDM 그래픽 설정 확인..."

$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$regName = "fEnableWddmDriver"

# 레지스트리 키 없으면 생성
if (-not (Test-Path $regPath)) {
    Log-Warn "레지스트리 경로 없음 → 새로 생성"
    New-Item -Path $regPath -Force | Out-Null
}

$currentVal = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName

if ($null -eq $currentVal) {
    Log-Warn "fEnableWddmDriver 값 없음 (기본값 = WDDM 사용 중)"
} elseif ($currentVal -eq 0) {
    Log-Ok "이미 WDDM 비활성화(XDDM 모드) 상태입니다"
    Log-Info "이미 적용됐는데도 문제가 있다면 아래 [5]번 추가 조치를 확인하세요"
} else {
    Log-Warn "현재 fEnableWddmDriver = $currentVal (WDDM 활성화 상태)"
}

# ─────────────────────────────────────────────
# 4. WDDM 비활성화 적용 (그룹 정책 레지스트리 직접 수정)
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "▶ [4/5] WDDM 그래픽 드라이버 비활성화 적용..."

# 그룹 정책 경로:
# 로컬 컴퓨터 정책 > 컴퓨터 구성 > 관리 템플릿 > Windows 구성 요소
# > 원격 데스크톱 서비스 > 원격 데스크톱 세션 호스트 > 원격 세션 환경
# > "WDDM 그래픽 디스플레이 드라이버 사용" = 사용 안 함

try {
    Set-ItemProperty -Path $regPath -Name $regName -Value 0 -Type DWord -Force
    $verify = (Get-ItemProperty -Path $regPath -Name $regName).$regName
    if ($verify -eq 0) {
        Log-Fix "fEnableWddmDriver = 0 적용 완료 (XDDM 모드로 전환)"
        $FIXES_APPLIED++
    } else {
        Log-Err "레지스트리 적용 실패 (현재 값: $verify)"
    }
} catch {
    Log-Err "레지스트리 수정 중 오류: $_"
}

# gpupdate로 그룹 정책 즉시 반영
Write-Host ""
Log-Fix "그룹 정책 강제 업데이트 중 (gpupdate /force)..."
try {
    $gpResult = & gpupdate /force 2>&1
    Log-Ok "그룹 정책 업데이트 완료"
    $FIXES_APPLIED++
} catch {
    Log-Warn "gpupdate 실패 — 재부팅 후 적용됩니다"
}

# ─────────────────────────────────────────────
# 5. 활성 RDP 세션 확인 및 종료 안내
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "▶ [5/5] 활성 RDP 세션 확인..."

try {
    $sessions = query session 2>&1 | Select-String "rdp-tcp|Active" | Where-Object { $_ -notmatch "console" }
    if ($sessions) {
        Log-Warn "활성 RDP 세션 감지됨:"
        $sessions | ForEach-Object { Log-Info "  $_" }
        Log-Info "→ Parsec 연결 전에 RDP 세션을 모두 종료하세요"
        Log-Info "  종료 명령: logoff <세션ID>  (위 목록의 숫자)"
    } else {
        Log-Ok "활성 RDP 세션 없음"
    }
} catch {
    Log-Info "RDP 세션 조회 불가 (무시 가능)"
}

# ─────────────────────────────────────────────
# 요약
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan

if ($FIXES_APPLIED -gt 0) {
    Write-Host "수정 $FIXES_APPLIED 건 적용됨" -ForegroundColor Green
} else {
    Write-Host "적용된 수정 없음 (이미 설정됐거나 수동 조치 필요)"
}

Write-Host ""
Write-Host "▶ 다음 단계:" -ForegroundColor Yellow
Write-Host "  1. PC를 재부팅하여 XDDM 모드 완전 적용"
Write-Host "  2. 재부팅 후 Parsec으로 다시 연결 시도"
Write-Host "  3. 그래도 안 되면:"
Write-Host "     - 모든 RDP 세션 완전 종료 후 Parsec 재연결"
Write-Host "     - Parsec 앱 재시작 (트레이 아이콘 우클릭 → Quit → 재실행)"
Write-Host "     - GPU 드라이버 최신 버전으로 재설치"
Write-Host ""
Write-Host "▶ 설정 되돌리기 (WDDM 다시 활성화):"
Write-Host "  Remove-ItemProperty -Path '$regPath' -Name '$regName'"
Write-Host ""
