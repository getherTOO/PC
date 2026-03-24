# PC 원격 제어 설정 가이드

이 리포지토리는 PC를 원격으로 제어하기 위한 설정 스크립트 모음입니다.

## 포함된 스크립트

| 파일 | 대상 OS | 설명 |
|------|---------|------|
| `setup-remote-control.sh` | Linux | 원격 제어 통합 초기 설정 |
| `setup-remote-control.ps1` | Windows | 원격 제어 통합 초기 설정 |
| `fix-parsec.sh` | Linux | Parsec 연결 문제 진단 및 수정 |
| `fix-parsec-wddm.ps1` | Windows | Parsec 에러 -14003 (WDDM 충돌) 수정 |

---

## 빠른 시작

### Linux

```bash
# 1. 초기 설정 (최초 1회)
chmod +x setup-remote-control.sh
sudo ./setup-remote-control.sh

# 2. Parsec 연결 안 될 때
chmod +x fix-parsec.sh
sudo ./fix-parsec.sh
```

### Windows (관리자 PowerShell)

```powershell
# 1. 초기 설정 (최초 1회)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-remote-control.ps1

# 2. Parsec 에러 -14003 발생 시
.\fix-parsec-wddm.ps1
```

---

## 원격 접속 방법

### 1. Parsec (그래픽 원격 데스크톱, 게이밍)
- **용도**: 고화질 화면 스트리밍, 게임 원격 플레이
- **설치**: https://parsec.app/downloads
- **사용법**: 호스트/클라이언트 모두 동일 Parsec 계정으로 로그인 → 호스트 PC 선택

### 2. SSH (CLI 원격 접속)
- **용도**: 터미널 작업, 파일 전송, 포트 포워딩
- **접속**: `ssh username@<PC-IP>`
- **파일 전송**: `scp localfile username@<PC-IP>:~/`

### 3. RDP (Windows 기본 원격 데스크톱)
- **용도**: Windows GUI 원격 제어
- **접속**: `mstsc` → PC IP 입력 (포트 3389)

---

## Parsec 에러 코드 해결

### 에러 -14003 (화면 캡처 실패)

| 원인 | 해결 방법 |
|------|-----------|
| 모니터 미연결 | GPU에 HDMI/DP 더미 플러그 연결 |
| WDDM 충돌 (RDP 동시 사용) | `fix-parsec-wddm.ps1` 실행 |
| GPU 렌더러 오설정 | Parsec 앱 → Host → Renderer → 외장 GPU 선택 |
| 화면 잠금 상태 | Parsec Host 설정 → "로그인 없이 연결 허용" 활성화 |
| GPU 드라이버 문제 | 드라이버 최신 버전 재설치 |

---

## 필요 포트

| 포트 | 프로토콜 | 용도 |
|------|----------|------|
| 22 | TCP | SSH |
| 3389 | TCP | RDP |
| 8000 | TCP/UDP | Parsec |

---

## 보안 권고사항

1. **SSH 키 인증** 설정 후 비밀번호 인증 비활성화
   ```bash
   # 클라이언트에서 실행
   ssh-copy-id username@<PC-IP>
   # 서버 /etc/ssh/sshd_config 에서:
   # PasswordAuthentication no
   ```

2. **RDP 포트 변경** (기본 3389 → 임의 포트)

3. **Parsec**: 계정 기반 암호화 연결 — 별도 포트 개방 없이도 동작 가능
