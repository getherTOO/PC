#!/bin/bash
# setup-remote-control.sh
# Linux PC 원격 제어 환경 통합 설정 스크립트
# - SSH 서버 설정 (CLI 원격 접속)
# - Parsec 설치 및 설정 (그래픽 원격 데스크톱)
# - 방화벽 규칙 설정
# - 부팅 시 자동 시작 설정
#
# 실행 방법:
#   chmod +x setup-remote-control.sh && sudo ./setup-remote-control.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR]${NC}  $1"; }
log_info() { echo "       $1"; }
log_fix()  { echo -e "${BLUE}[FIX]${NC}  $1"; }
log_step() { echo -e "\n${CYAN}▶ $1${NC}"; }

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   PC 원격 제어 환경 설정 (Linux)         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# root 확인
if [[ $EUID -ne 0 ]]; then
    log_err "root 권한 필요: sudo ./setup-remote-control.sh"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
STEPS_OK=0
STEPS_WARN=0

# ─────────────────────────────────────────────
# 1. 패키지 업데이트
# ─────────────────────────────────────────────
log_step "[1/6] 패키지 목록 업데이트"
if command -v apt-get &>/dev/null; then
    apt-get update -qq && log_ok "apt 업데이트 완료" && ((STEPS_OK++))
elif command -v dnf &>/dev/null; then
    dnf check-update -q || true && log_ok "dnf 업데이트 완료" && ((STEPS_OK++))
elif command -v pacman &>/dev/null; then
    pacman -Sy --noconfirm &>/dev/null && log_ok "pacman 업데이트 완료" && ((STEPS_OK++))
else
    log_warn "지원되는 패키지 관리자 없음 — 수동 설치 필요"
    ((STEPS_WARN++))
fi

# ─────────────────────────────────────────────
# 2. SSH 서버 설치 및 설정
# ─────────────────────────────────────────────
log_step "[2/6] SSH 서버 설정"

install_pkg() {
    if command -v apt-get &>/dev/null; then
        apt-get install -y -qq "$1"
    elif command -v dnf &>/dev/null; then
        dnf install -y -q "$1"
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm "$1" &>/dev/null
    fi
}

if ! command -v sshd &>/dev/null; then
    log_fix "openssh-server 설치 중..."
    install_pkg openssh-server
fi

SSHD_CONF="/etc/ssh/sshd_config"
if [[ -f "$SSHD_CONF" ]]; then
    # 백업
    cp "$SSHD_CONF" "${SSHD_CONF}.bak.$(date +%Y%m%d)" 2>/dev/null || true

    # 보안: 루트 직접 로그인 금지, 비밀번호 인증 허용(키 설정 전까지)
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONF"
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONF"
    # Keep-alive: 연결 끊김 방지
    grep -q "^ClientAliveInterval" "$SSHD_CONF" || echo "ClientAliveInterval 60" >> "$SSHD_CONF"
    grep -q "^ClientAliveCountMax" "$SSHD_CONF" || echo "ClientAliveCountMax 3" >> "$SSHD_CONF"

    log_ok "sshd_config 설정 완료 (루트 로그인 금지, KeepAlive 활성화)"
fi

# SSH 서비스 활성화 및 시작
if command -v systemctl &>/dev/null; then
    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    log_ok "SSH 서비스 활성화 및 시작 완료"
    ((STEPS_OK++))
fi

# 현재 IP 출력
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
log_info "SSH 접속: ssh ${REAL_USER}@${LOCAL_IP}"

# ─────────────────────────────────────────────
# 3. 방화벽 설정
# ─────────────────────────────────────────────
log_step "[3/6] 방화벽 설정"

if command -v ufw &>/dev/null; then
    ufw allow 22/tcp comment "SSH"    &>/dev/null
    ufw allow 8000/tcp comment "Parsec" &>/dev/null
    ufw allow 8000/udp comment "Parsec" &>/dev/null
    ufw allow 5900/tcp comment "VNC (선택)"   &>/dev/null
    # 방화벽이 비활성화 상태면 활성화
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    if echo "$UFW_STATUS" | grep -qi "inactive"; then
        ufw --force enable &>/dev/null
        log_fix "UFW 방화벽 활성화 및 포트 개방 (22, 8000, 5900)"
    else
        log_ok "UFW 방화벽 포트 개방 완료 (22, 8000, 5900)"
    fi
    ((STEPS_OK++))
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-service=ssh &>/dev/null || true
    firewall-cmd --permanent --add-port=8000/tcp &>/dev/null || true
    firewall-cmd --permanent --add-port=8000/udp &>/dev/null || true
    firewall-cmd --reload &>/dev/null || true
    log_ok "firewalld 포트 개방 완료"
    ((STEPS_OK++))
else
    log_warn "방화벽 관리자 없음 (ufw/firewalld) — 포트 수동 개방 필요"
    log_info "필요 포트: 22(SSH), 8000(Parsec), 5900(VNC)"
    ((STEPS_WARN++))
fi

# ─────────────────────────────────────────────
# 4. Parsec 설치 확인
# ─────────────────────────────────────────────
log_step "[4/6] Parsec 원격 데스크톱 확인"

PARSEC_BIN=""
for p in /usr/bin/parsecd /opt/parsec/parsecd "$HOME/.parsec/parsecd"; do
    [[ -x "$p" ]] && PARSEC_BIN="$p" && break
done

if [[ -n "$PARSEC_BIN" ]]; then
    log_ok "Parsec 설치됨: $PARSEC_BIN"
    ((STEPS_OK++))
else
    log_warn "Parsec이 설치되지 않음"
    log_info "설치 방법 (Ubuntu/Debian):"
    log_info "  wget -q https://builds.parsec.app/package/parsec-linux.deb -O /tmp/parsec.deb"
    log_info "  sudo dpkg -i /tmp/parsec.deb"
    log_info "다운로드: https://parsec.app/downloads"
    ((STEPS_WARN++))
fi

# Parsec 자동 시작 서비스 생성
PARSEC_SERVICE="/etc/systemd/system/parsec.service"
if [[ -n "$PARSEC_BIN" ]] && command -v systemctl &>/dev/null && [[ ! -f "$PARSEC_SERVICE" ]]; then
    cat > "$PARSEC_SERVICE" << EOF
[Unit]
Description=Parsec Remote Desktop
After=network.target display-manager.service
Wants=network.target

[Service]
Type=simple
User=${REAL_USER}
ExecStart=${PARSEC_BIN}
Restart=on-failure
RestartSec=10
Environment=DISPLAY=:0

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable parsec 2>/dev/null || true
    log_fix "Parsec 자동 시작 서비스 등록 완료"
fi

# ─────────────────────────────────────────────
# 5. 가상 디스플레이 (헤드리스 환경 대비)
# ─────────────────────────────────────────────
log_step "[5/6] 헤드리스 디스플레이 설정 확인"

CONNECTED_DISPLAYS=0
if [[ -d /sys/class/drm ]]; then
    for connector in /sys/class/drm/*/status; do
        [[ -f "$connector" ]] && [[ "$(cat "$connector" 2>/dev/null)" == "connected" ]] && ((CONNECTED_DISPLAYS++))
    done
fi

if [[ $CONNECTED_DISPLAYS -gt 0 ]]; then
    log_ok "물리적 디스플레이 ${CONNECTED_DISPLAYS}개 연결됨 — 가상 디스플레이 불필요"
    ((STEPS_OK++))
else
    log_warn "물리적 디스플레이 없음 — 헤드리스 환경"
    if ! command -v Xvfb &>/dev/null; then
        log_fix "Xvfb 설치 중..."
        install_pkg xvfb 2>/dev/null || log_warn "Xvfb 설치 실패 — 수동 설치 필요: sudo apt install xvfb"
    fi

    if command -v Xvfb &>/dev/null; then
        # Xvfb 자동 시작 서비스
        XVFB_SERVICE="/etc/systemd/system/xvfb.service"
        if [[ ! -f "$XVFB_SERVICE" ]]; then
            cat > "$XVFB_SERVICE" << 'EOF'
[Unit]
Description=Xvfb Virtual Framebuffer
After=network.target

[Service]
ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24
Restart=always

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable xvfb
            systemctl start xvfb
            log_fix "Xvfb 가상 디스플레이 서비스 시작 (DISPLAY=:99, 1920x1080)"
            log_info "환경 변수 설정: export DISPLAY=:99"
            ((STEPS_OK++))
        else
            log_ok "Xvfb 서비스 이미 설정됨"
            ((STEPS_OK++))
        fi
    fi
fi

# ─────────────────────────────────────────────
# 6. 자동 깨우기 / 절전 방지 설정
# ─────────────────────────────────────────────
log_step "[6/6] 절전 모드 비활성화 (원격 접속 유지용)"

if command -v systemctl &>/dev/null; then
    # sleep/hibernate 비활성화
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target &>/dev/null || true
    log_ok "절전/최대절전 모드 비활성화 완료"
    ((STEPS_OK++))
fi

# 화면 잠금 타임아웃 비활성화 (콘솔)
if command -v setterm &>/dev/null; then
    setterm -blank 0 -powersave off 2>/dev/null || true
fi

# ─────────────────────────────────────────────
# 요약
# ─────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║             설정 완료 요약               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo -e "  ${GREEN}성공: ${STEPS_OK}건${NC}  |  ${YELLOW}경고: ${STEPS_WARN}건${NC}"
echo ""
echo "▶ 원격 접속 정보:"
echo "  • SSH  : ssh ${REAL_USER}@${LOCAL_IP:-<이-PC-IP>}  (포트 22)"
echo "  • Parsec: https://parsec.app 에서 동일 계정으로 접속"
echo ""
echo "▶ 다음 단계:"
echo "  1. 이 PC에서 Parsec 앱 로그인 후 Host 모드 활성화"
echo "  2. 연결 불가 시: sudo ./fix-parsec.sh 실행"
echo "  3. Windows RDP 충돌 문제: fix-parsec-wddm.ps1 참조"
echo ""
echo "▶ SSH 키 인증 설정 (권장):"
echo "  클라이언트 PC에서: ssh-copy-id ${REAL_USER}@${LOCAL_IP:-<이-PC-IP>}"
echo "  설정 후 비밀번호 인증 비활성화: sshd_config → PasswordAuthentication no"
echo ""
