#!/bin/sh
# ccr installer — 冪等。何度実行してもよい。
#
#   curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --host devbox --host gpu1
#   ./install.sh [--host <ssh-alias>]... [--no-skill] [--no-deps] [--bin <dir>]
#
# やること:
#   1. ローカル依存（python3 / fzf / claude）の確認。fzf は brew / apt で自動導入を試みる
#   2. ccr と ccn（ccr へのシンボリックリンク）を <bin>（既定 ~/.local/bin）に配置
#   3. Claude Code 用 skill を ~/.claude/skills/ccr/SKILL.md に配置
#   4. --host を ~/.config/ccr/hosts に追記（重複しない）
#   5. `ccr doctor` を実行して残りの問題と直し方を表示（終了コードは doctor に従う）
#
# 対話入力・sudo パスワードが必要な操作は実行せず、実行すべきコマンドを表示する。
set -eu

RAW=${CCR_RAW:-https://raw.githubusercontent.com/y0ssh1/ccr/main}
BIN=${CCR_BIN:-$HOME/.local/bin}
HOSTS_FILE=$HOME/.config/ccr/hosts
SKILL_DIR=$HOME/.claude/skills/ccr
HOSTS=""
SKILL=1
DEPS=1

while [ $# -gt 0 ]; do
  case $1 in
    --host) HOSTS="$HOSTS $2"; shift 2 ;;
    --no-skill) SKILL=0; shift ;;
    --no-deps) DEPS=0; shift ;;
    --bin) BIN=$2; shift 2 ;;
    -h|--help) echo "usage: install.sh [--host <ssh-alias>]... [--no-skill] [--no-deps] [--bin <dir>]"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '==> %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# clone 済みリポジトリから実行されたか（curl | sh の場合は $0 が sh になる）
SRC=""
case $0 in
  */install.sh|install.sh)
    d=$(cd "$(dirname "$0")" && pwd)
    [ -f "$d/ccr" ] && [ -f "$d/skills/ccr/SKILL.md" ] && SRC=$d ;;
esac

# --- 1. deps ---
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
  warn "python3 (3.8+) が使えません。macOS: xcode-select --install / Debian系: sudo apt-get install -y python3"
  exit 1
fi
if [ "$DEPS" = 1 ] && ! have fzf; then
  if have brew; then
    say "fzf を導入: brew install fzf"; brew install fzf
  elif have apt-get && sudo -n true 2>/dev/null; then
    say "fzf を導入: sudo apt-get install -y fzf"; sudo apt-get install -y fzf
  else
    warn "fzf がありません。手動で導入してください（brew install fzf / sudo apt-get install -y fzf）"
  fi
fi
have claude || warn "claude がありません: curl -fsSL https://claude.ai/install.sh | bash"

# --- 2. ccr / ccn ---
mkdir -p "$BIN"
if [ -n "$SRC" ]; then
  say "link $BIN/ccr -> $SRC/ccr"
  ln -sf "$SRC/ccr" "$BIN/ccr"
else
  say "download $RAW/ccr -> $BIN/ccr"
  tmp=$(mktemp)
  curl -fsSL "$RAW/ccr" -o "$tmp"
  [ -L "$BIN/ccr" ] && rm -f "$BIN/ccr"
  mv "$tmp" "$BIN/ccr"
fi
chmod 755 "$BIN/ccr" 2>/dev/null || true
ln -sf ccr "$BIN/ccn"

# --- 3. skill ---
if [ "$SKILL" = 1 ]; then
  mkdir -p "$SKILL_DIR"
  if [ -n "$SRC" ]; then
    say "link $SKILL_DIR/SKILL.md -> $SRC/skills/ccr/SKILL.md"
    ln -sf "$SRC/skills/ccr/SKILL.md" "$SKILL_DIR/SKILL.md"
  else
    say "download skill -> $SKILL_DIR/SKILL.md"
    [ -L "$SKILL_DIR/SKILL.md" ] && rm -f "$SKILL_DIR/SKILL.md"
    curl -fsSL "$RAW/skills/ccr/SKILL.md" -o "$SKILL_DIR/SKILL.md"
  fi
fi

# --- 4. hosts ---
if [ -n "$HOSTS" ]; then
  mkdir -p "$(dirname "$HOSTS_FILE")"
  touch "$HOSTS_FILE"
  for h in $HOSTS; do
    if grep -qxF "$h" "$HOSTS_FILE"; then
      say "host $h は登録済み"
    else
      say "host $h を $HOSTS_FILE に追加"; echo "$h" >> "$HOSTS_FILE"
    fi
  done
fi

# --- 5. doctor ---
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) warn "$BIN が PATH にありません。シェル設定に追加してください: export PATH=\"$BIN:\$PATH\"" ;;
esac
say "ccr doctor"
exec "$BIN/ccr" doctor
