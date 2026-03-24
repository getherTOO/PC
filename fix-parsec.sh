#!/bin/bash
# Parsec Remote Connection Fix Script
# Diagnoses and fixes common Parsec remote connection issues on Linux

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR]${NC} $1"; }
log_info() { echo "      $1"; }

echo "=== Parsec Remote Connection Diagnostics ==="
echo ""

FIXES_APPLIED=0

# ─────────────────────────────────────────────
# 1. Parsec daemon 실행 확인 및 재시작
# ─────────────────────────────────────────────
echo "▶ [1/6] Parsec 데몬 확인..."

PARSEC_BIN=""
for p in /usr/bin/parsecd /opt/parsec/parsecd ~/.parsec/parsecd; do
    [[ -x "$p" ]] && PARSEC_BIN="$p" && break
done

if [[ -z "$PARSEC_BIN" ]]; then
    log_err "Parsec 바이너리를 찾을 수 없습니다."
    log_info "설치 확인: https://parsec.app/downloads"
else
    log_ok "Parsec 바이너리: $PARSEC_BIN"

    if pgrep -x parsecd > /dev/null 2>&1; then
        log_ok "parsecd 실행 중"
    else
        log_warn "parsecd 가 실행되지 않음 → 재시작 시도"
        if command -v systemctl &>/dev/null && systemctl is-active --quiet parsecd 2>/dev/null; then
            systemctl restart parsecd && log_ok "systemctl로 재시작 완료" && ((FIXES_APPLIED++))
        else
            "$PARSEC_BIN" &
            sleep 2
            pgrep -x parsecd > /dev/null && log_ok "parsecd 재시작 완료" && ((FIXES_APPLIED++)) \
                || log_err "parsecd 재시작 실패"
        fi
    fi
fi

# ─────────────────────────────────────────────
# 2. 디스플레이 서버 확인
# ─────────────────────────────────────────────
echo ""
echo "▶ [2/6] 디스플레이 서버 확인..."

if [[ -n "${DISPLAY:-}" ]]; then
    log_ok "X11 DISPLAY=$DISPLAY"
elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    log_warn "Wayland 감지됨 ($WAYLAND_DISPLAY) — Parsec은 X11을 권장"
    log_info "해결: XWayland 활성화 또는 X11 세션으로 전환"
else
    log_warn "디스플레이 환경 변수 없음"
    log_info "헤드리스 환경이라면 가상 디스플레이 설정 필요 (아래 [4] 참조)"
fi

# ─────────────────────────────────────────────
# 3. GPU 드라이버 확인
# ─────────────────────────────────────────────
echo ""
echo "▶ [3/6] GPU 드라이버 확인..."

if command -v nvidia-smi &>/dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1)
    log_ok "NVIDIA GPU: $GPU_INFO"
elif lspci 2>/dev/null | grep -qi "vga\|3d\|display"; then
    GPU_LINE=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | head -1)
    log_warn "GPU 감지됨: $GPU_LINE"
    log_info "NVIDIA라면: sudo apt install nvidia-driver-535 (또는 최신 버전)"
    log_info "AMD라면: sudo apt install firmware-amd-graphics"
else
    log_err "GPU를 감지하지 못함 — Parsec은 하드웨어 인코딩이 필요합니다"
fi

# ─────────────────────────────────────────────
# 4. 가상 디스플레이 설정 (헤드리스 서버용)
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/6] 가상 디스플레이 확인..."

XVFB_NEEDED=false
if ! xdpyinfo -display "${DISPLAY:-:0}" &>/dev/null 2>&1; then
    log_warn "활성 X 디스플레이 없음"
    if command -v Xvfb &>/dev/null; then
        log_info "Xvfb 설치 확인됨 — 가상 디스플레이 시작 시도"
        Xvfb :99 -screen 0 1920x1080x24 &
        sleep 1
        export DISPLAY=:99
        log_ok "Xvfb :99 시작됨 (1920x1080)" && ((FIXES_APPLIED++))
        XVFB_NEEDED=true
    else
        log_warn "Xvfb 없음 → 설치: sudo apt install xvfb"
    fi
else
    log_ok "X 디스플레이 정상"
fi

# ─────────────────────────────────────────────
# 5. 방화벽 / 포트 확인
# ─────────────────────────────────────────────
echo ""
echo "▶ [5/6] 네트워크 / 방화벽 확인..."

PARSEC_PORT=8000
if command -v ss &>/dev/null; then
    if ss -tulnp 2>/dev/null | grep -q ":$PARSEC_PORT"; then
        log_ok "포트 $PARSEC_PORT 열려있음"
    else
        log_warn "포트 $PARSEC_PORT 가 열려있지 않음 (parsecd가 실행 중이어야 합니다)"
    fi
fi

# ufw 확인
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    if echo "$UFW_STATUS" | grep -qi "active"; then
        log_warn "UFW 방화벽 활성화됨: $UFW_STATUS"
        log_info "Parsec 허용: sudo ufw allow 8000/tcp && sudo ufw allow 8000/udp"
    else
        log_ok "UFW 방화벽 비활성화 (문제없음)"
    fi
fi

# ─────────────────────────────────────────────
# 6. Parsec 설정 파일 확인
# ─────────────────────────────────────────────
echo ""
echo "▶ [6/6] Parsec 설정 파일 확인..."

CONFIG_DIR="${HOME}/.parsec"
CONFIG_FILE="$CONFIG_DIR/config.txt"

if [[ -f "$CONFIG_FILE" ]]; then
    log_ok "설정 파일: $CONFIG_FILE"
    # 설정 파일 권한 확인
    PERMS=$(stat -c "%a" "$CONFIG_FILE" 2>/dev/null)
    if [[ "$PERMS" != "600" && "$PERMS" != "644" ]]; then
        log_warn "설정 파일 권한이 $PERMS → 644로 수정"
        chmod 644 "$CONFIG_FILE" && ((FIXES_APPLIED++))
    fi
else
    log_warn "설정 파일 없음 ($CONFIG_FILE)"
    log_info "Parsec을 처음 실행하면 자동 생성됩니다"
fi

# ─────────────────────────────────────────────
# 요약
# ─────────────────────────────────────────────
echo ""
echo "================================================"
if [[ $FIXES_APPLIED -gt 0 ]]; then
    echo -e "${GREEN}자동 수정 $FIXES_APPLIED 건 적용됨${NC}"
else
    echo "자동 수정 없음 (수동 조치 필요)"
fi
echo ""
echo "▶ 그래도 연결 안 될 때 체크리스트:"
echo "  1. Parsec 앱에서 로그아웃 후 재로그인"
echo "  2. sudo systemctl restart parsecd  (또는 프로세스 재시작)"
echo "  3. GPU 드라이버 재설치 (NVIDIA: sudo apt install --reinstall nvidia-driver-XXX)"
echo "  4. Parsec 설정 초기화: rm -rf ~/.parsec && Parsec 재실행"
echo "  5. 라우터 포트포워딩: 8000 TCP/UDP → PC 내부 IP"
echo "  6. BIOS에서 iGPU/dGPU 설정 확인"
echo ""
