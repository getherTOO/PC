#!/bin/bash
# Parsec Remote Connection Fix Script
# Diagnoses and fixes common Parsec remote connection issues on Linux
# Includes specific handling for error code -14003 (screen capture failure)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR]${NC} $1"; }
log_info() { echo "      $1"; }
log_fix()  { echo -e "${BLUE}[FIX]${NC} $1"; }

echo "=== Parsec Remote Connection Diagnostics ==="
echo ""

FIXES_APPLIED=0

# ─────────────────────────────────────────────
# 에러 코드 -14003 전용 진단 (최우선)
# ─────────────────────────────────────────────
echo "▶ [!] 에러 코드 -14003 진단 중..."
echo "      원인: 호스트 PC가 화면을 캡처/인코딩하지 못함"
echo ""

ERROR_14003_CAUSES=()

# 모니터 연결 여부 확인 (Linux: /sys/class/drm)
CONNECTED_DISPLAYS=0
if [[ -d /sys/class/drm ]]; then
    for connector in /sys/class/drm/*/status; do
        [[ -f "$connector" ]] && [[ "$(cat "$connector" 2>/dev/null)" == "connected" ]] && ((CONNECTED_DISPLAYS++))
    done
fi

if [[ $CONNECTED_DISPLAYS -eq 0 ]]; then
    log_warn "물리적 디스플레이 감지 안 됨 → -14003의 가장 흔한 원인"
    ERROR_14003_CAUSES+=("no_display")
    log_info "해결 방법 (택1):"
    log_info "  A) HDMI/DP 더미 플러그 구입 후 GPU에 연결 (권장)"
    log_info "  B) 아래 [4]번 가상 디스플레이 설정 참조"
else
    log_ok "물리적 디스플레이 $CONNECTED_DISPLAYS 개 연결됨"
fi

# GPU 인코더(NVENC/VCE/QSV) 확인
GPU_ENCODER_OK=false
if command -v nvidia-smi &>/dev/null; then
    NVENC_CHECK=$(nvidia-smi --query-gpu=encoder.stats.sessionCount --format=csv,noheader 2>/dev/null | head -1 || true)
    if nvidia-smi &>/dev/null; then
        log_ok "NVIDIA GPU 정상 — NVENC 인코더 사용 가능"
        GPU_ENCODER_OK=true
    else
        log_warn "nvidia-smi 실행 실패 → 드라이버 문제"
        ERROR_14003_CAUSES+=("nvidia_driver_broken")
    fi
elif lspci 2>/dev/null | grep -qi "amd\|radeon"; then
    if lsmod 2>/dev/null | grep -qi "amdgpu"; then
        log_ok "AMD GPU 드라이버(amdgpu) 로드됨"
        GPU_ENCODER_OK=true
    else
        log_warn "AMD GPU 감지됐으나 드라이버 미로드"
        ERROR_14003_CAUSES+=("amd_driver_missing")
    fi
elif lspci 2>/dev/null | grep -qi "intel"; then
    if lsmod 2>/dev/null | grep -qi "i915"; then
        log_ok "Intel GPU 드라이버(i915) 로드됨"
        GPU_ENCODER_OK=true
    else
        log_warn "Intel GPU 드라이버 미로드"
        ERROR_14003_CAUSES+=("intel_driver_missing")
    fi
else
    log_err "GPU를 감지하지 못함 — Parsec은 하드웨어 인코딩이 필요합니다"
    ERROR_14003_CAUSES+=("no_gpu")
fi

# Parsec 설정에서 렌더러(GPU) 설정 확인
CONFIG_FILE="${HOME}/.parsec/config.txt"
if [[ -f "$CONFIG_FILE" ]]; then
    RENDERER=$(grep -i "^encoder_h265_min_qp\|^decoder_h265\|^encoder_adapter" "$CONFIG_FILE" 2>/dev/null || true)
    if grep -qi "encoder_adapter" "$CONFIG_FILE" 2>/dev/null; then
        ADAPTER_VAL=$(grep -i "encoder_adapter" "$CONFIG_FILE" | head -1)
        log_info "현재 인코더 어댑터 설정: $ADAPTER_VAL"
        log_info "→ 외장 GPU가 아닌 iGPU로 설정됐다면 Parsec 앱 > Host > Renderer 변경"
    fi
fi

# -14003 요약 및 수동 체크리스트 출력
echo ""
if [[ ${#ERROR_14003_CAUSES[@]} -gt 0 ]]; then
    echo -e "${RED}[-14003] 다음 원인이 감지됐습니다: ${ERROR_14003_CAUSES[*]}${NC}"
else
    log_ok "-14003 관련 자동 감지 이상 없음 (아래 수동 체크리스트 확인)"
fi

echo ""
echo -e "${YELLOW}━━━ -14003 수동 해결 체크리스트 ━━━${NC}"
echo "  □ 1. 더미 플러그: GPU의 HDMI/DisplayPort에 더미 플러그 연결"
echo "  □ 2. Parsec 앱 → 설정(⚙) → Host → Renderer → 외장 GPU 선택 후 재시작"
echo "  □ 3. GPU 드라이버 최신 버전 재설치"
echo "       NVIDIA: https://www.nvidia.com/drivers"
echo "       AMD:    https://www.amd.com/support"
echo "  □ 4. Windows 잠금화면 상태라면:"
echo "       Parsec 설정 → Host → 'Allow connections when no one is logged in' 활성화"
echo "  □ 5. BIOS → iGPU 비활성화 (외장 GPU만 사용하도록)"
echo "  □ 6. Parsec 완전 재설치 후 재로그인"
echo ""

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
# 4. 가상 디스플레이 설정 (헤드리스 / 더미 플러그 대체용)
# ─────────────────────────────────────────────
echo ""
echo "▶ [4/6] 가상 디스플레이 확인 (-14003 해결책)..."

if ! xdpyinfo -display "${DISPLAY:-:0}" &>/dev/null 2>&1; then
    log_warn "활성 X 디스플레이 없음 → -14003 원인일 수 있음"
    if command -v Xvfb &>/dev/null; then
        log_fix "Xvfb 가상 디스플레이 시작 (1920x1080)..."
        Xvfb :99 -screen 0 1920x1080x24 &
        sleep 1
        export DISPLAY=:99
        log_ok "Xvfb :99 시작됨" && ((FIXES_APPLIED++))
        log_info "※ 재부팅 후에도 유지하려면 systemd 서비스로 등록 필요"
    else
        log_warn "Xvfb 없음 → 설치: sudo apt install xvfb"
        log_info "설치 후 재실행: Xvfb :99 -screen 0 1920x1080x24 &"
    fi

    # NVIDIA headless용 xorg.conf 생성 안내
    if command -v nvidia-smi &>/dev/null; then
        log_info ""
        log_info "NVIDIA 헤드리스 전용: nvidia-xconfig --allow-empty-initial-configuration 실행 권장"
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
    PERMS=$(stat -c "%a" "$CONFIG_FILE" 2>/dev/null)
    if [[ "$PERMS" != "600" && "$PERMS" != "644" ]]; then
        log_warn "설정 파일 권한이 $PERMS → 644로 수정"
        chmod 644 "$CONFIG_FILE" && ((FIXES_APPLIED++))
    fi
    # -14003 관련 설정값 출력
    echo ""
    log_info "현재 Host 관련 설정:"
    grep -iE "^(encoder|renderer|video|host)" "$CONFIG_FILE" 2>/dev/null | while read -r line; do
        log_info "  $line"
    done || log_info "  (관련 설정 없음 — 기본값 사용 중)"
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
echo "▶ -14003 빠른 해결 순서:"
echo "  1. [가장 효과적] GPU에 HDMI/DP 더미 플러그 연결"
echo "  2. Parsec 앱 → Host → Renderer에서 올바른 GPU 선택"
echo "  3. GPU 드라이버 최신 버전으로 재설치"
echo "  4. 잠금화면 문제: Parsec Host 설정에서 로그인 없이 연결 허용"
echo "  5. BIOS에서 iGPU 비활성화 (외장 GPU 단독 사용)"
echo ""
