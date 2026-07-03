#!/usr/bin/env bash
#
# ttyd-tmux / install.sh
# ======================
# 이 스크립트는 "서버의 작업 공간을 웹브라우저로 열 수 있게" 준비해 줍니다.
#
# 쉽게 말하면:
#   - tmux      = 서버 안에서 계속 켜져 있는 "작업 공간". 창을 닫아도 꺼지지 않습니다.
#   - ttyd      = 그 작업 공간을 "웹브라우저 화면"으로 보여주는 프로그램.
#   - Tailscale = 내 폰/PC 와 서버를 안전하게 잇는 "사설 네트워크"(앱).
#                 이게 있어서 인터넷에 포트를 열지 않고도(=방화벽을 안 건드리고도) 접속할 수 있습니다.
#   - ttyd-tmux = 위 셋을 엮어, 작업 공간을 웹으로 여는 걸 아주 쉽게 해주는 명령.
#
# 이 스크립트는 비밀번호나 접속 키를 파일에 저장하지 않습니다. 여러 번 실행해도 안전합니다.
# amd64 / arm64 어떤 Ubuntu 서버에서도 그대로 동작합니다(자동으로 맞춰 설치).
#
set -euo pipefail

# ttyd 가 귀 기울일 네트워크(=Tailscale 전용). 이 덕분에 인터넷 쪽으로는 절대 안 열립니다.
NET_NAME="${TTYD_TMUX_IFACE:-tailscale0}"
ME="$(id -un)"                                   # 지금 로그인한 사용자 이름
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }   # 안내
note() { printf '\033[1;33m! %s\033[0m\n' "$*"; }   # 주의
stop() { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }   # 중단

# ── 시작 전 확인 ────────────────────────────────────────────
[ -r /etc/os-release ] && . /etc/os-release || true
[ "${ID:-}" = "ubuntu" ] || note "Ubuntu가 아닌 것 같습니다(${ID:-알수없음}). 일단 계속 진행합니다."
command -v sudo >/dev/null || stop "이 스크립트는 sudo 가 필요합니다."
say "설치를 시작합니다 (사용자: ${ME}, 서버 종류: $(uname -m))."

# ── 1) 필요한 프로그램 설치 ─────────────────────────────────
# 이미 깔려 있으면 건너뜁니다. (컴퓨터 종류는 apt/설치스크립트가 알아서 맞춥니다.)
say "필요한 프로그램(tmux · ttyd · Tailscale)을 확인/설치합니다…"
APT_DONE=0
apt_get() { [ "$APT_DONE" -eq 0 ] && { sudo apt-get update -y; APT_DONE=1; }; sudo apt-get install -y "$@"; }

command -v curl >/dev/null || apt_get curl
command -v tmux >/dev/null || apt_get tmux
command -v ttyd >/dev/null || apt_get ttyd
if ! command -v tailscale >/dev/null; then
  say "Tailscale 을 설치합니다 (공식 설치 스크립트)…"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# ── 2) Tailscale 로그인 ─────────────────────────────────────
# 여기서 '본인 Tailscale 계정'으로 한 번 로그인합니다. (비밀 값은 저장하지 않습니다.)
if tailscale status >/dev/null 2>&1; then
  say "Tailscale 은 이미 로그인되어 있습니다. 건너뜁니다."
else
  say "Tailscale 로그인이 필요합니다. 본인 Tailscale 계정으로 한 번만 인증하면 됩니다."
  note "곧 웹 주소가 하나 뜹니다. 그 주소를 폰이나 PC 브라우저로 열어 '허용'을 누르세요."
  echo  "  (고급) 미리 발급한 인증키가 있으면 아래에 붙여넣고 Enter, 없으면 그냥 Enter 하세요."
  read -rsp "  인증키(없으면 Enter): " KEY; echo
  if [ -n "${KEY}" ]; then sudo tailscale up --authkey "${KEY}" --hostname "$(hostname)-ttyd"
  else sudo tailscale up --hostname "$(hostname)-ttyd"; fi
  unset KEY
fi

# ── 3) 옛 버전 흔적 정리 ────────────────────────────────────
# (예전에 claude 전용 이름으로 설치했던 경우를 자동으로 치웁니다. 없으면 그냥 넘어갑니다.)
for old in $(systemctl list-units --all --type=service 2>/dev/null \
              | grep -oE 'ttyd-claude@[^. ]+\.service' | sort -u); do
  sudo systemctl disable --now "$old" 2>/dev/null || true
done
if [ -e /usr/local/bin/ttyd-claude ] || [ -e /etc/systemd/system/ttyd-claude@.service ] \
   || [ -e /etc/systemd/system/claude-web.service ]; then
  note "예전 버전 흔적을 정리합니다."
  sudo systemctl disable --now claude-web 2>/dev/null || true
  sudo rm -f /usr/local/bin/ttyd-claude \
             /etc/systemd/system/ttyd-claude@.service \
             /etc/systemd/system/claude-web.service
  sudo rm -rf /etc/ttyd-claude.d
fi

# ── 4) ttyd-tmux 명령 설치 ──────────────────────────────────
say "'ttyd-tmux' 명령을 설치합니다 (어디서든 입력하면 실행되도록)."
sudo install -m 0755 "${REPO_DIR}/bin/ttyd-tmux" /usr/local/bin/ttyd-tmux

# ── 5) '자동으로 계속 켜두는' 설정 틀 설치 ──────────────────
# ttyd-tmux 가 웹 창을 백그라운드에서 항상 켜둘 수 있도록 하는 밑작업입니다.
# (이 틀 자체는 아무 창도 켜지 않습니다. 실제로 켜는 건 나중에 'ttyd-tmux up' 명령입니다.)
TTYD="$(command -v ttyd)"; TMUX="$(command -v tmux)"
say "백그라운드 실행용 설정 틀을 등록합니다…"
sudo mkdir -p /etc/ttyd-tmux.d
sudo tee /etc/systemd/system/ttyd-tmux@.service >/dev/null <<UNIT
[Unit]
Description=ttyd-tmux: 작업 공간 %i 을(를) 웹으로 여는 창 (연결망: ${NET_NAME})
After=tailscaled.service network-online.target
Wants=tailscaled.service network-online.target

[Service]
User=${ME}
# 작업 공간마다의 설정(포트 등)을 여기서 읽습니다.
EnvironmentFile=/etc/ttyd-tmux.d/%i.env
# 작업 공간이 아직 없으면 새로 만들어 둡니다. (CMD 를 지정했으면 그걸 실행, 아니면 그냥 셸)
ExecStartPre=/bin/sh -c '${TMUX} has-session -t %i 2>/dev/null || { if [ -n "\${CMD:-}" ]; then ${TMUX} new-session -d -s %i "\$CMD"; else ${TMUX} new-session -d -s %i; fi; }'
# 웹 창은 '이미 있는 작업 공간에 들어가기'만 합니다. (창을 닫아도 작업 공간은 안 꺼짐)
ExecStart=${TTYD} -i ${NET_NAME} -p \${PORT} -W ${TMUX} attach -t %i
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload

# ── 다 됐습니다! 사용법 안내 ────────────────────────────────
IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
echo
say "설치 완료! 이제 아래처럼 쓰면 됩니다."
echo
echo "  ▷ 작업 공간을 웹으로 열기 (백그라운드로 항상 켜둠, 재부팅해도 유지)"
echo "      ttyd-tmux up 일감1 9090        # '일감1' 이라는 작업 공간을 9090 번으로 열기"
echo "      ttyd-tmux up 일감2 9091        # 다른 작업 공간은 번호만 다르게"
echo
echo "  ▷ 상태 보기 / 주소 확인 / 닫기"
echo "      ttyd-tmux ls                  # 지금 열려 있는 목록"
echo "      ttyd-tmux url 일감1           # 접속 주소 보기"
echo "      ttyd-tmux down 일감1          # 웹 창과 작업 공간을 함께 정리"
echo
echo "  ▷ 서버에서 (SSH로) 같은 작업 공간에 들어가기"
echo "      tmux attach -t 일감1"
echo
if [ -n "${IP}" ]; then
  echo "  ▷ 접속 방법: 폰/PC 에서 Tailscale 을 켠 뒤 브라우저 주소창에"
  echo "        http://${IP}:9090   (위 9090 은 예시 번호)"
else
  note "아직 Tailscale 주소를 못 받았습니다. 'tailscale status' 로 상태를 확인하세요."
fi
