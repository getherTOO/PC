#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════
# Termux 초기 셋업 스크립트 (Samsung Galaxy용)
# ═══════════════════════════════════════════════
# 사용법: Termux 설치 후 이 스크립트 전체를 붙여넣기
#
# 설치 순서:
#   1. F-Droid에서 Termux 설치 (Play Store 버전은 업데이트 중단됨)
#      https://f-droid.org/en/packages/com.termux/
#   2. Termux 실행 후 아래 명령어 실행:
#      curl -sL https://raw.githubusercontent.com/getherTOO/PC/claude/mobile-environment-setup-cgcGi/mobile/termux-setup.sh | bash
#   또는 이 파일 내용을 Termux에 붙여넣기

set -euo pipefail

G='\033[0;32m'  # green
Y='\033[1;33m'  # yellow
C='\033[0;36m'  # cyan
N='\033[0m'     # reset

ok()   { echo -e "${G}[OK]${N} $1"; }
info() { echo -e "${C}[>>]${N} $1"; }
warn() { echo -e "${Y}[!!]${N} $1"; }

echo ""
echo "═══════════════════════════════════════════"
echo "  Termux 초기 환경 설정"
echo "  대상: Samsung Galaxy"
echo "═══════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────
# 1. 저장소 업데이트 및 기본 패키지
# ─────────────────────────────────────────────
info "[1/6] 패키지 저장소 업데이트..."
yes | pkg update -y 2>/dev/null
ok "저장소 업데이트 완료"

info "[2/6] 기본 패키지 설치..."
pkg install -y \
    git \
    curl \
    wget \
    openssh \
    nano \
    vim \
    htop \
    tree \
    zip \
    unzip \
    jq \
    python \
    nodejs \
    2>/dev/null
ok "기본 패키지 설치 완료"

# ─────────────────────────────────────────────
# 2. 저장소 접근 권한 설정
# ─────────────────────────────────────────────
info "[3/6] 내부 저장소 접근 권한 설정..."
if [ ! -d "$HOME/storage" ]; then
    termux-setup-storage
    echo "  → 저장소 접근 권한 팝업이 뜨면 '허용'을 눌러주세요"
    echo "  → 허용 후 Enter를 눌러 계속하세요"
    read -r
fi
ok "저장소 접근 설정 완료"
echo "  ~/storage/shared    → 내부저장소"
echo "  ~/storage/dcim      → 카메라 사진"
echo "  ~/storage/downloads → 다운로드"

# ─────────────────────────────────────────────
# 3. Termux:API 연동 (하드웨어 제어용)
# ─────────────────────────────────────────────
info "[4/6] Termux:API 패키지 설치..."
echo "  → 배터리, 알림, 센서, 클립보드 등 폰 기능 제어용"
pkg install -y termux-api 2>/dev/null
ok "Termux:API 설치 완료"
warn "F-Droid에서 'Termux:API' 앱도 별도 설치 필요!"
echo "  https://f-droid.org/en/packages/com.termux.api/"

# ─────────────────────────────────────────────
# 4. 유용한 alias 및 환경 설정
# ─────────────────────────────────────────────
info "[5/6] 환경 설정 (alias, 프롬프트)..."

BASHRC="$HOME/.bashrc"

# 기존 비서 설정 블록이 있으면 제거 후 재작성
sed -i '/# \[비서\] 시작/,/# \[비서\] 끝/d' "$BASHRC" 2>/dev/null || true

cat >> "$BASHRC" << 'ALIASES'
# [비서] 시작 ─────────────────────────────
# 프롬프트
PS1='\[\e[36m\]📱 \w \$\[\e[0m\] '

# 저장소 단축키
alias sd='cd ~/storage/shared'
alias dl='cd ~/storage/downloads'
alias dc='cd ~/storage/dcim'

# 시스템 정보
alias 배터리='termux-battery-status | jq "{percentage, status, temperature}"'
alias 밝기='termux-brightness'
alias 진동='termux-vibrate -d 200'
alias 알림='termux-notification --title'
alias 클립='termux-clipboard-get'
alias 클립설정='termux-clipboard-set'
alias 볼륨='termux-volume'
alias 위치='termux-location -p network'
alias 토스트='termux-toast'

# 파일 관리
alias ll='ls -alh --color=auto'
alias la='ls -A --color=auto'
alias lt='ls -alht --color=auto'  # 최근 수정 순

# 빠른 작업
alias 사진수='find ~/storage/dcim -name "*.jpg" -o -name "*.png" | wc -l'
alias 저장공간='df -h /data | tail -1 | awk "{print \"사용: \" \$3 \" / 전체: \" \$2 \" (\" \$5 \" 사용)\"}"'
alias 큰파일='find ~/storage/shared -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -h -r | head -20'
alias 앱목록='pm list packages -3 | sed "s/package://" | sort'

# Git 단축키
alias gs='git status'
alias gl='git log --oneline -10'
alias gp='git push'

# 네트워크
alias 내ip='curl -s ifconfig.me && echo ""'
alias 와이파이='termux-wifi-connectioninfo | jq "{ssid, link_speed_mbps, rssi, ip}"'
# [비서] 끝 ───────────────────────────────
ALIASES

ok "alias 설정 완료"

# ─────────────────────────────────────────────
# 5. 유틸리티 스크립트 디렉토리
# ─────────────────────────────────────────────
info "[6/6] 유틸리티 스크립트 디렉토리 생성..."
mkdir -p "$HOME/scripts"

# 폰 상태 요약 스크립트
cat > "$HOME/scripts/status.sh" << 'STATUS'
#!/data/data/com.termux/files/usr/bin/bash
# 폰 상태 한눈에 보기
echo "═══════════════════════════════"
echo "  📱 폰 상태 요약"
echo "═══════════════════════════════"

# 배터리
BAT=$(termux-battery-status 2>/dev/null)
if [ -n "$BAT" ]; then
    PCT=$(echo "$BAT" | jq -r '.percentage')
    STAT=$(echo "$BAT" | jq -r '.status')
    TEMP=$(echo "$BAT" | jq -r '.temperature')
    echo "  🔋 배터리: ${PCT}% (${STAT}, ${TEMP}°C)"
fi

# 저장공간
STORAGE=$(df -h /data 2>/dev/null | tail -1)
if [ -n "$STORAGE" ]; then
    USED=$(echo "$STORAGE" | awk '{print $3}')
    TOTAL=$(echo "$STORAGE" | awk '{print $2}')
    USE_PCT=$(echo "$STORAGE" | awk '{print $5}')
    echo "  💾 저장공간: ${USED} / ${TOTAL} (${USE_PCT})"
fi

# Wi-Fi
WIFI=$(termux-wifi-connectioninfo 2>/dev/null)
if [ -n "$WIFI" ]; then
    SSID=$(echo "$WIFI" | jq -r '.ssid')
    SPEED=$(echo "$WIFI" | jq -r '.link_speed_mbps')
    echo "  📶 Wi-Fi: ${SSID} (${SPEED}Mbps)"
fi

echo "═══════════════════════════════"
STATUS
chmod +x "$HOME/scripts/status.sh"

# 대용량 파일 정리 스크립트
cat > "$HOME/scripts/cleanup.sh" << 'CLEANUP'
#!/data/data/com.termux/files/usr/bin/bash
# 저장공간 정리 도우미
echo "═══════════════════════════════"
echo "  🧹 저장공간 정리"
echo "═══════════════════════════════"

echo ""
echo "▶ 100MB 이상 대용량 파일:"
find ~/storage/shared -size +100M -exec ls -lh {} \; 2>/dev/null | \
    awk '{print $5, $9}' | sort -h -r | head -15

echo ""
echo "▶ 폴더별 용량 (상위 10개):"
du -sh ~/storage/shared/*/ 2>/dev/null | sort -h -r | head -10

echo ""
echo "▶ 캐시 정리 가능 항목:"
CACHE_SIZE=$(du -sh ~/storage/shared/Android/data 2>/dev/null | awk '{print $1}')
echo "  앱 데이터: ${CACHE_SIZE:-확인불가}"

echo ""
echo "※ 파일 삭제는 직접 확인 후 rm 명령어로 진행하세요"
echo "═══════════════════════════════"
CLEANUP
chmod +x "$HOME/scripts/cleanup.sh"

# PATH에 scripts 추가
grep -q 'HOME/scripts' "$BASHRC" 2>/dev/null || \
    echo 'export PATH="$HOME/scripts:$PATH"' >> "$BASHRC"

ok "유틸리티 스크립트 생성 완료"

# ─────────────────────────────────────────────
# 완료 요약
# ─────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo -e "${G}  ✅ Termux 초기 설정 완료!${N}"
echo "═══════════════════════════════════════════"
echo ""
echo "  사용 가능한 명령어:"
echo "  ─────────────────"
echo "  배터리      → 배터리 상태 확인"
echo "  와이파이    → Wi-Fi 연결 정보"
echo "  클립        → 클립보드 내용 보기"
echo "  클립설정    → 클립보드에 텍스트 설정"
echo "  저장공간    → 저장소 사용량"
echo "  큰파일      → 100MB+ 파일 찾기"
echo "  앱목록      → 설치된 앱 목록"
echo "  status.sh   → 폰 상태 요약"
echo "  cleanup.sh  → 저장공간 정리"
echo ""
echo "  ※ 추가 필요: F-Droid에서 'Termux:API' 앱 설치"
echo ""
echo "  새 설정 적용: source ~/.bashrc"
echo "═══════════════════════════════════════════"

source "$BASHRC" 2>/dev/null || true
