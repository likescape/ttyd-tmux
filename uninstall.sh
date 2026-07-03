#!/usr/bin/env bash
#
# ttyd-tmux / uninstall.sh
# ========================
# ttyd-tmux 를 깨끗이 지웁니다.
#   - 웹으로 열어둔 모든 작업 공간의 '웹 창'을 끕니다.
#   - ttyd-tmux 명령과 설정을 지웁니다.
# 그대로 두는 것: 설치했던 프로그램(ttyd·tmux·Tailscale), Tailscale 로그인, 작업 공간(하던 일).
#   → 나중에 다시 설치하기 쉽도록 남겨둡니다. 완전 삭제는 아래 안내 참고.
#
set -euo pipefail
say() { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }

# 1) 켜져 있는 모든 웹 창 끄기 (지금 이름 ttyd-tmux@, 예전 이름 ttyd-claude@ 모두)
mapfile -t OPEN < <(systemctl list-units --all --type=service 2>/dev/null \
  | grep -oE 'ttyd-(tmux|claude)@[^. ]+\.service' | sort -u || true)
for u in "${OPEN[@]:-}"; do
  [ -n "$u" ] || continue
  say "웹 창 끄기: $u"
  sudo systemctl disable --now "$u" 2>/dev/null || true
done

# 2) 명령·설정·틀 지우기 (지금/예전 이름 모두)
say "ttyd-tmux 명령과 설정을 지웁니다…"
sudo systemctl disable --now claude-web 2>/dev/null || true
sudo rm -f /etc/systemd/system/ttyd-tmux@.service \
           /etc/systemd/system/ttyd-claude@.service \
           /etc/systemd/system/claude-web.service \
           /usr/local/bin/ttyd-tmux \
           /usr/local/bin/ttyd-claude
sudo rm -rf /etc/ttyd-tmux.d /etc/ttyd-claude.d
sudo systemctl daemon-reload

say "완료했습니다. 작업 공간(하던 일)은 그대로 남아 있습니다."
echo "   작업 공간 목록 보기:   tmux ls"
echo "   특정 작업 공간 지우기:  tmux kill-session -t <이름>"
echo
echo "   # 프로그램까지 완전히 지우고 싶다면 (직접 실행):"
echo "   #   sudo apt-get remove --purge -y ttyd"
echo "   #   sudo tailscale logout && sudo apt-get remove --purge -y tailscale"
