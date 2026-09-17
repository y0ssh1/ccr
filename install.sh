#!/bin/sh
# ccr installer — 冪等。何度実行してもよい。
#
#   curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --host devbox        # このマシン + devbox を ssh 越しにセットアップ
#   ./install.sh [--role client|host|both] [--host <ssh-alias>]... [options]
#
# role（既定 both = このマシンを client としても host としても使える状態にする）
#   client : ccr を使って他マシンに入る側。fzf / ccr / ccn / skill / ssh 鍵 / ホスト登録
#   host   : ssh で入られて claude を動かす側。python3 / tmux / claude / PATH / sshd / authorized_keys
#
# options
#   --host <alias>          ~/.config/ccr/hosts に登録し、ssh 越しに host セットアップを実行（client 用）
#   --no-remote             --host の ssh 越しセットアップをしない（登録だけ）
#   --authorize-key <pub>   公開鍵文字列を ~/.ssh/authorized_keys に追加（host 用）
#   --token                 claude setup-token を実行し、貼り付けたトークンを ~/.claude/oauth-token に保存（host 用。
#                           macOS は ssh 越しにキーチェーンを読めないため必要。端末があり未設定なら自動で提案する）
#   --no-skill              Claude Code skill を入れない
#   --bin <dir>             ccr の配置先（既定 ~/.local/bin, 環境変数 CCR_BIN）
#
# パスワード / sudo / GUI 操作が必要なものは、端末があれば対話で実行し、無ければ [todo] としてコマンドを表示する。
# 最後に `ccr doctor` を実行し、残りの問題と直し方を表示する（終了コードは doctor に従う）。
set -eu

RAW=${CCR_RAW:-https://raw.githubusercontent.com/y0ssh1/ccr/main}
BIN=${CCR_BIN:-$HOME/.local/bin}
HOSTS_FILE=$HOME/.config/ccr/hosts
SKILL_DIR=$HOME/.claude/skills/ccr
ROLE=both
HOSTS=""
REMOTE=1
SKILL=1
AUTH_KEY=""
TOKEN=auto

while [ $# -gt 0 ]; do
  case $1 in
    --role) ROLE=$2; shift 2 ;;
    --host) HOSTS="$HOSTS $2"; shift 2 ;;
    --no-remote) REMOTE=0; shift ;;
    --authorize-key) AUTH_KEY=$2; shift 2 ;;
    --token) TOKEN=1; shift ;;
    --no-token) TOKEN=0; shift ;;
    --no-skill) SKILL=0; shift ;;
    --bin) BIN=$2; shift 2 ;;
    -h|--help)
      echo "usage: install.sh [--role client|host|both] [--host <alias>]... [--no-remote] [--authorize-key <pub>] [--token|--no-token] [--no-skill] [--bin <dir>]"
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case $ROLE in client|host|both) ;; *) echo "--role は client|host|both" >&2; exit 2 ;; esac

# ssh の非対話セッションでは PATH が最小なので、よくある場所を足す
ORIG_PATH=$PATH
for d in /usr/local/bin /home/linuxbrew/.linuxbrew/bin /opt/homebrew/bin "$HOME/.local/bin"; do
  if [ -d "$d" ]; then case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac; fi
done
export PATH

say()  { printf '==> %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*" >&2; }
todo() { printf '[todo] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
OS=$(uname -s)
# 対話できる端末があるか（curl | sh でも /dev/tty があれば可）
TTY=0; if [ -t 1 ] && (: </dev/tty) 2>/dev/null; then TTY=1; fi

# sudo: root / パスワード不要ならそのまま、端末があれば対話、無ければ使わない
SUDO=sudo; [ "$(id -u)" = 0 ] && SUDO=""
can_sudo() {
  [ -z "$SUDO" ] && return 0
  have sudo || return 1
  sudo -n true 2>/dev/null && return 0
  [ "$TTY" = 1 ] && sudo -v </dev/tty
}

# パッケージ導入。$1=コマンド名 $2=パッケージ名
pkg_install() {
  if have brew; then
    say "brew install $2"; brew install "$2"
  elif have apt-get && can_sudo; then
    say "apt-get install $2"
    $SUDO apt-get install -y "$2" || { $SUDO apt-get update && $SUDO apt-get install -y "$2"; }
  elif have dnf && can_sudo; then
    say "dnf install $2"; $SUDO dnf install -y "$2"
  else
    todo "$1 を導入してください（例: brew install $2 / sudo apt-get install -y $2）"
    return 1
  fi
}

# clone 済みリポジトリから実行されたか（curl | sh の場合は $0 が sh になる）
SRC=""
case $0 in
  */install.sh)
    d=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
    if [ -n "$d" ] && [ -f "$d/ccr" ] && [ -f "$d/skills/ccr/SKILL.md" ]; then SRC=$d; fi ;;
esac

# 取得: $1=repo 内パス $2=配置先（clone ならシンボリックリンク）
fetch() {
  mkdir -p "$(dirname "$2")"
  if [ -L "$2" ]; then rm -f "$2"; fi
  if [ -n "$SRC" ]; then
    say "link $2 -> $SRC/$1"; ln -sf "$SRC/$1" "$2"
  else
    say "download $1 -> $2"
    tmp=$(mktemp); curl -fsSL "$RAW/$1" -o "$tmp"; mv "$tmp" "$2"; chmod 644 "$2"
  fi
}

python_ok() { python3 -c "import sys; sys.exit(sys.version_info < ($1))" 2>/dev/null; }

# ================= 共通: python3 =================
if ! python_ok "3, 6"; then
  if [ "$OS" = Darwin ]; then
    todo "python3 が使えません。このマシンで実行: xcode-select --install （GUI で承認が必要）"
    if [ "$TTY" = 1 ]; then xcode-select --install 2>/dev/null || true; fi
  else
    pkg_install python3 python3 || true
  fi
fi

# ================= host =================
setup_host() {
  say "--- host setup ($(hostname)) ---"

  have tmux || pkg_install tmux tmux || warn "tmux なし: ssh が切れると claude も終了します"

  if ! have claude; then
    say "claude を導入: curl -fsSL https://claude.ai/install.sh | bash"
    curl -fsSL https://claude.ai/install.sh | bash \
      || todo "claude の導入に失敗。手動で: curl -fsSL https://claude.ai/install.sh | bash"
  fi

  # ccr はログインシェル経由で claude を起動するので、そこから見えるように PATH を通す
  shell=${SHELL:-/bin/sh}
  # 判定はこのスクリプトが足す前の PATH で行う（ssh で入った時と同じ条件）
  if ! PATH=$ORIG_PATH "$shell" -lic 'command -v claude' </dev/null >/dev/null 2>&1; then
    dir=$(dirname "$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")")
    case $(basename "$shell") in
      zsh) rc=$HOME/.zshrc ;;
      bash) rc=$HOME/.bashrc ;;
      *) rc=$HOME/.profile ;;
    esac
    if ! grep -q '# ccr: claude PATH' "$rc" 2>/dev/null; then
      say "$rc に PATH を追加: $dir"
      printf '\nexport PATH="%s:$PATH"  # ccr: claude PATH\n' "$dir" >> "$rc"
    fi
  fi

  # macOS は認証情報をキーチェーンに置くが、ssh セッションからはキーチェーンがロックされていて読めない。
  # ~/.claude/oauth-token（claude setup-token で発行）があればそれを環境変数で渡す。
  # 渡すのはキーチェーンが読めないときだけ: 長期トークンは推論専用で、キーチェーンが読める端末にまで
  # 効かせると claude auth login 済みでも Remote Control などが使えなくなる。
  # $SSH_CONNECTION では判定しない（ssh から既存の tmux ペインに入ると引き継がれない）。ccr の UNLOCK と同じ判定
  if [ "$OS" = Darwin ]; then
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
      [ "$rc" = "$HOME/.bashrc" ] && [ ! -f "$rc" ] && continue
      # 旧版が追加した読み込み行（無条件 / SSH_CONNECTION 判定）は取り除いて入れ直す
      if grep '# ccr: claude token' "$rc" 2>/dev/null | grep -qv 'show-keychain-info'; then
        say "$rc の ~/.claude/oauth-token 読み込みを「キーチェーンが読めないときだけ」に更新"
        grep -v '# ccr: claude token' "$rc" > "$rc.ccr-tmp" && cat "$rc.ccr-tmp" > "$rc"
        rm -f "$rc.ccr-tmp"
      fi
      if ! grep -q '# ccr: claude token' "$rc" 2>/dev/null; then
        say "$rc に ~/.claude/oauth-token の読み込みを追加（キーチェーンが読めないときだけ）"
        printf '\n[ -r "$HOME/.claude/oauth-token" ] && ! security show-keychain-info >/dev/null 2>&1 && export CLAUDE_CODE_OAUTH_TOKEN="$(cat "$HOME/.claude/oauth-token")"  # ccr: claude token\n' >> "$rc"
      fi
    done
  fi

  token_file=$HOME/.claude/oauth-token
  if [ "$TOKEN" = auto ] && [ "$OS" = Darwin ] && [ ! -s "$token_file" ] && [ "$TTY" = 1 ] && have claude; then
    printf '%s' "ssh 越しに claude を使うための長期トークンを今設定しますか？（ブラウザ認証）[Y/n] " >/dev/tty
    read -r ans </dev/tty || ans=n
    case $ans in [nN]*) ;; *) TOKEN=1 ;; esac
  fi
  if [ "$TOKEN" = 1 ]; then
    if [ "$TTY" != 1 ]; then
      todo "--token は端末が必要です。このホストのターミナルで実行してください"
    elif ! have claude; then
      todo "claude が無いためトークンを設定できません"
    else
      say "claude setup-token を実行します。完了後に表示されるトークン（sk-ant-...）をコピーしてください"
      # macOS では /dev/tty を kqueue で監視できず claude(Bun) が EINVAL で落ちるため、
      # 端末に直結している fd（curl | sh なら stdout/stderr）を stdin に回して実行する
      if [ -t 0 ]; then
        claude setup-token || st=$?
      elif [ -t 2 ]; then
        claude setup-token 0<&2 || st=$?
      elif [ -t 1 ]; then
        claude setup-token 0<&1 || st=$?
      else
        st=1
      fi
      if [ "${st:-0}" != 0 ]; then
        warn "claude setup-token をここで実行できませんでした。別のターミナルタブで 'claude setup-token' を実行し、表示されたトークンをコピーしてください"
      fi
      printf '%s' "コピーしたトークンを貼り付けて Enter（入力は表示されません）: " >/dev/tty
      stty -echo </dev/tty 2>/dev/null || true
      read -r tok </dev/tty || tok=""
      stty echo </dev/tty 2>/dev/null || true
      printf '\n' >/dev/tty
      tok=$(printf '%s' "$tok" | tr -d '[:space:]')
      case $tok in
        sk-ant-*)
          mkdir -p "$HOME/.claude"
          (umask 077; printf '%s\n' "$tok" > "$token_file")
          say "トークンを保存: $token_file (600)" ;;
        *) todo "トークンの形式が違います（sk-ant- で始まる文字列）。再実行: install.sh --role host --token" ;;
      esac
    fi
  fi
  if [ -s "$token_file" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && ! security show-keychain-info >/dev/null 2>&1; then
    CLAUDE_CODE_OAUTH_TOKEN=$(cat "$token_file"); export CLAUDE_CODE_OAUTH_TOKEN
  fi

  if have claude && ! claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
    if [ "$OS" = Darwin ] && [ -n "${SSH_CONNECTION:-}" ] && ! security show-keychain-info >/dev/null 2>&1; then
      todo "ssh からはキーチェーンがロックされていて claude の認証情報を読めません。このホストのターミナルで: curl -fsSL $RAW/install.sh | sh -s -- --role host --token"
    else
      todo "claude が未ログインです。このホスト上で実行: claude auth login（client からなら ssh -t <host> claude auth login）"
    fi
  fi

  # sshd
  if [ -n "${SSH_CONNECTION:-}" ]; then
    :  # ssh で入ってきている = sshd は動いている
  elif have nc && nc -z 127.0.0.1 22 2>/dev/null; then
    say "sshd: 起動済み"
  elif [ "$OS" = Darwin ]; then
    todo "sshd が停止しています: システム設定 → 一般 → 共有 → リモートログイン をオン"
  elif have systemctl && can_sudo; then
    say "sshd を有効化"
    $SUDO systemctl enable --now ssh 2>/dev/null || $SUDO systemctl enable --now sshd || true
  else
    todo "sshd を有効化してください: sudo systemctl enable --now ssh"
  fi

  if [ -n "$AUTH_KEY" ]; then
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
    if grep -qxF "$AUTH_KEY" "$HOME/.ssh/authorized_keys"; then
      say "公開鍵は登録済み"
    else
      say "公開鍵を authorized_keys に追加"; echo "$AUTH_KEY" >> "$HOME/.ssh/authorized_keys"
    fi
  fi

  if [ -z "${SSH_CONNECTION:-}" ]; then
    # Tailscale があれば MagicDNS 名を使う
    ts=$(tailscale status --json 2>/dev/null \
      | python3 -c 'import json,sys; s=json.load(sys.stdin)["Self"]; print(s["HostName"], s["DNSName"].rstrip("."))' 2>/dev/null \
      || echo "$(hostname -s) $(hostname)")
    say "このマシンに入る client 側の ~/.ssh/config には次を追記:"
    printf '    Host %s\n      HostName %s\n      User %s\n' ${ts% *} ${ts#* } "$(id -un)"
  fi
}

# ================= client =================
setup_client() {
  say "--- client setup ---"
  python_ok "3, 8" || todo "ccr には python3 3.8+ が必要です"
  have fzf || pkg_install fzf fzf || true
  have ssh || pkg_install ssh openssh-client || true

  fetch ccr "$BIN/ccr"; chmod 755 "$BIN/ccr" 2>/dev/null || true
  ln -sf ccr "$BIN/ccn"
  if [ "$SKILL" = 1 ]; then fetch skills/ccr/SKILL.md "$SKILL_DIR/SKILL.md"; fi

  if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    say "ssh 鍵を作成: ~/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
  fi

  for h in $HOSTS; do
    mkdir -p "$(dirname "$HOSTS_FILE")"; touch "$HOSTS_FILE"
    if grep -qxF "$h" "$HOSTS_FILE"; then say "host $h は登録済み"; else say "host $h を登録"; echo "$h" >> "$HOSTS_FILE"; fi
    [ "$REMOTE" = 1 ] || continue

    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" true 2>/dev/null; then
      if [ "$TTY" = 1 ]; then
        say "$h に鍵を登録します（初回は fingerprint の確認 yes と、$h のログインパスワードを入力）"
        ssh-copy-id -i "$HOME/.ssh/id_ed25519.pub" "$h" </dev/tty || true
      fi
      if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" true 2>/dev/null; then
        todo "$h に鍵認証で入れません。このマシンで: ssh-copy-id -i ~/.ssh/id_ed25519.pub $h  → その後 ccr setup $h"
        continue
      fi
    fi
    "$BIN/ccr" setup "$h" || todo "$h の host セットアップに失敗。ccr setup $h を再実行"
  done
}

case $ROLE in
  host) setup_host ;;
  client) setup_client ;;
  both) setup_host; setup_client ;;
esac

if [ "$ROLE" = host ]; then
  say "host setup 完了"
  exit 0
fi
case ":$ORIG_PATH:" in
  *":$BIN:"*) ;;
  *) todo "$BIN を PATH に追加してください: export PATH=\"$BIN:\$PATH\"" ;;
esac
say "ccr doctor"
exec "$BIN/ccr" doctor
