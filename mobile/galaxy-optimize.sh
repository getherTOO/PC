#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════
# Samsung Galaxy 배터리/성능 최적화 (Termux + ADB)
# ═══════════════════════════════════════════════
# 사용법: bash galaxy-optimize.sh
#
# 일부 항목은 ADB 권한이 필요합니다:
#   - 설정 → 개발자 옵션 → USB 디버깅 ON
#   - Termux에서: pkg install android-tools
#   - 무선 디버깅 또는 자기자신 ADB 연결 필요

set -uo pipefail

G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
R='\033[0;31m'
N='\033[0m'

ok()   { echo -e "${G}[OK]${N} $1"; }
info() { echo -e "${C}[>>]${N} $1"; }
warn() { echo -e "${Y}[!!]${N} $1"; }
err()  { echo -e "${R}[ERR]${N} $1"; }
ask()  { echo -ne "${Y}[?]${N} $1 (y/n): "; read -r ans; [[ "$ans" =~ ^[Yy] ]]; }

echo ""
echo "═══════════════════════════════════════════"
echo "  Samsung Galaxy 최적화"
echo "═══════════════════════════════════════════"
echo ""

# ADB 사용 가능 여부 확인
HAS_ADB=false
if command -v adb &>/dev/null; then
    # 자기자신에게 ADB 연결 시도 (무선 디버깅)
    ADB_DEVICES=$(adb devices 2>/dev/null | grep -c "device$")
    if [ "$ADB_DEVICES" -gt 0 ]; then
        HAS_ADB=true
        ok "ADB 연결 확인됨"
    fi
fi

if [ "$HAS_ADB" = false ]; then
    warn "ADB 미연결 - 일부 최적화는 수동으로 진행해야 합니다"
    echo "  ADB 셀프 연결 방법:"
    echo "  1. 설정 → 개발자 옵션 → 무선 디버깅 ON"
    echo "  2. 무선 디버깅 → 페어링 코드로 기기 페어링"
    echo "  3. Termux: adb pair <IP>:<PORT>"
    echo "  4. Termux: adb connect <IP>:<PORT>"
    echo ""
fi

# ─────────────────────────────────────────────
# 1. 배터리 상태 진단
# ─────────────────────────────────────────────
info "[1/5] 배터리 상태 진단..."

BAT=$(termux-battery-status 2>/dev/null)
if [ -n "$BAT" ]; then
    PCT=$(echo "$BAT" | jq -r '.percentage')
    STAT=$(echo "$BAT" | jq -r '.status')
    TEMP=$(echo "$BAT" | jq -r '.temperature')
    HEALTH=$(echo "$BAT" | jq -r '.health // "unknown"')

    echo "  배터리: ${PCT}% | 상태: ${STAT} | 온도: ${TEMP}°C | 건강: ${HEALTH}"

    if (( $(echo "$TEMP > 40" | bc -l 2>/dev/null || echo 0) )); then
        warn "배터리 온도가 높습니다 (${TEMP}°C) - 충전 중단 권장"
    fi
    if [ "$PCT" -gt 80 ] && [ "$STAT" = "CHARGING" ]; then
        warn "80% 이상 충전 중 - 배터리 수명을 위해 '배터리 보호' 기능 사용 권장"
        echo "  설정 → 배터리 → 배터리 보호 → 최대 85%로 설정"
    fi
else
    warn "배터리 정보 조회 실패 (Termux:API 앱 설치 필요)"
fi

# ─────────────────────────────────────────────
# 2. 불필요한 삼성 서비스 비활성화 (ADB 필요)
# ─────────────────────────────────────────────
echo ""
info "[2/5] 블로트웨어/불필요 서비스 확인..."

# 비활성화 대상 (안전한 항목만)
BLOAT_APPS=(
    "com.samsung.android.app.spage"          # Samsung Free (뉴스피드)
    "com.samsung.android.ardrawing"           # AR 낙서
    "com.samsung.android.aremoji"             # AR 이모지
    "com.samsung.android.app.tips"            # Tips
    "com.samsung.android.game.gamehome"       # Game Launcher
    "com.samsung.android.game.gametools"      # Game Tools
    "com.samsung.android.mobileservice"       # Samsung Experience Service
    "com.samsung.android.app.watchmanagerstub" # Watch Manager stub
    "com.microsoft.skydrive"                  # OneDrive (사전설치)
    "com.facebook.services"                   # Facebook 서비스
    "com.facebook.system"                     # Facebook 시스템
    "com.facebook.appmanager"                 # Facebook 앱 매니저
)

if [ "$HAS_ADB" = true ]; then
    DISABLED=0
    for app in "${BLOAT_APPS[@]}"; do
        # 설치 여부 확인
        if pm list packages 2>/dev/null | grep -q "$app"; then
            SHORT_NAME=$(echo "$app" | awk -F. '{print $NF}')
            if ask "  ${SHORT_NAME} 비활성화?"; then
                adb shell pm disable-user --user 0 "$app" 2>/dev/null && \
                    ok "  ${SHORT_NAME} 비활성화됨" || \
                    err "  ${SHORT_NAME} 비활성화 실패"
                ((DISABLED++))
            fi
        fi
    done
    [ "$DISABLED" -eq 0 ] && ok "비활성화할 블로트웨어 없음"
else
    warn "ADB 없이는 블로트웨어 비활성화 불가"
    echo "  수동: 설정 → 앱 → [앱 선택] → 비활성화"
    echo ""
    echo "  비활성화 추천 앱:"
    for app in "${BLOAT_APPS[@]}"; do
        SHORT=$(echo "$app" | awk -F. '{print $NF}')
        echo "    - $SHORT"
    done
fi

# ─────────────────────────────────────────────
# 3. 성능 최적화 설정 안내
# ─────────────────────────────────────────────
echo ""
info "[3/5] Samsung 성능 최적화 설정 안내..."
echo ""
echo "  [개발자 옵션] (설정 → 휴대전화 정보 → 빌드번호 7회 탭)"
echo "  ─────────────────────────────────────"
echo "  • 창 애니메이션 배율     → 0.5x 또는 끄기"
echo "  • 전환 애니메이션 배율   → 0.5x 또는 끄기"
echo "  • Animator 길이 배율     → 0.5x 또는 끄기"
echo "  • GPU 렌더링 강제 적용   → ON"
echo "  • 백그라운드 프로세스 제한 → 최대 4개"

if [ "$HAS_ADB" = true ]; then
    echo ""
    if ask "애니메이션 속도를 0.5x로 줄일까요?"; then
        adb shell settings put global window_animation_scale 0.5
        adb shell settings put global transition_animation_scale 0.5
        adb shell settings put global animator_duration_scale 0.5
        ok "애니메이션 0.5x로 설정됨 (체감 속도 향상)"
    fi
fi

# ─────────────────────────────────────────────
# 4. 배터리 최적화 설정 안내
# ─────────────────────────────────────────────
echo ""
info "[4/5] 배터리 절약 최적화 안내..."
echo ""
echo "  [설정 → 배터리]"
echo "  ─────────────────────────────────────"
echo "  • 배터리 보호           → ON (최대 85%)"
echo "  • 적응형 배터리         → ON"
echo "  • 미사용 앱 절전        → ON"
echo ""
echo "  [설정 → 디스플레이]"
echo "  ─────────────────────────────────────"
echo "  • 적응형 밝기           → ON"
echo "  • 화면 자동 꺼짐        → 30초~1분"
echo "  • 다크 모드             → ON (AMOLED 배터리 절약)"
echo "  • 주사율               → 적응형 (필요시에만 120Hz)"
echo ""
echo "  [설정 → 연결]"
echo "  ─────────────────────────────────────"
echo "  • 블루투스 스캔         → OFF (미사용시)"
echo "  • Wi-Fi 스캔            → OFF (미사용시)"
echo "  • 근처 디바이스 스캔    → OFF"

# ─────────────────────────────────────────────
# 5. 저장공간 현황
# ─────────────────────────────────────────────
echo ""
info "[5/5] 저장공간 현황..."

STORAGE=$(df -h /data 2>/dev/null | tail -1)
if [ -n "$STORAGE" ]; then
    USED=$(echo "$STORAGE" | awk '{print $3}')
    TOTAL=$(echo "$STORAGE" | awk '{print $2}')
    USE_PCT=$(echo "$STORAGE" | awk '{print $5}')
    echo "  사용: ${USED} / 전체: ${TOTAL} (${USE_PCT})"

    # 사용률 80% 이상이면 경고
    PCT_NUM=$(echo "$USE_PCT" | tr -d '%')
    if [ "$PCT_NUM" -gt 80 ] 2>/dev/null; then
        warn "저장공간 ${USE_PCT} 사용 중 - cleanup.sh 실행 권장"
    fi
fi

echo ""
echo "═══════════════════════════════════════════"
echo -e "${G}  최적화 안내 완료${N}"
echo "═══════════════════════════════════════════"
echo ""
echo "  ※ ADB 셀프 연결 후 다시 실행하면 자동 최적화 가능"
echo "  ※ 배터리 보호(85%)와 다크모드는 즉시 적용 권장"
echo ""
