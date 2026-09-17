---
name: ccr
description: ccr / ccn（ローカルと ssh 先の複数マシンにまたがって Claude Code セッションを resume・新規開始する CLI）のセットアップ、ホスト追加、依存関係の解消、トラブル対応。「リモートのセッションを再開したい」「別マシンで claude を起動したい」「ccr にホストを追加」「ccr が動かない」「ccr doctor」などで使う。
---

# ccr / ccn

- `ccr`: ローカルと ssh 先の全マシンにある Claude Code セッションを fzf の一覧で選び、そのマシン・そのディレクトリで `claude -r <id>` を実行する。
- `ccn`（= `ccr new`）: ホストとディレクトリを選んで、新しいセッションを開始する。
- リモートでは既定で tmux の中で起動する。ssh が切れても claude は動き続け、同じセッションを選ぶと再接続できる。
- リポジトリ: https://github.com/y0ssh1/ccr

## エージェントが守ること

1. **`ccr` / `ccn` を引数なし、または `-n` なしで実行しない。** fzf や ssh -t を使う対話 TUI なので、エージェントのシェルでは動かない。起動はユーザーのターミナルで行ってもらい、コピペできる 1 行のコマンドを渡す。
2. エージェントが実行してよい非対話コマンド:
   - `ccr doctor [host...] [--json]`: 依存関係を検査する。問題があると終了コード 1 を返し、項目ごとに `fix:` として直し方を表示する
   - `ccr ls [host...] [--json]`: セッション一覧を出力する
   - `ccr --id <prefix> -n` / `ccn <target> -n`: 実際には起動せず、実行されるコマンドだけを表示する
   - `curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh [-s -- --host <alias>]`: インストールする。冪等なので何度実行してもよい
3. **ユーザーにしかできない操作は、実行せずコマンドを渡す。**
   - パスワード入力: `ssh-copy-id`
   - fingerprint の確認: 初回の `ssh <host> true`
   - sudo
   - macOS のシステム設定（リモートログインの有効化）
4. `~/.ssh/config` を編集する前に中身を読む。既存の `Host` ブロックは壊さず、追記する。

## セットアップ手順

`ccr doctor` の `[fail]` がなくなるまで、次を繰り返す。

1. インストールする: `curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh`
   - ローカルの依存（python3 3.8+ / fzf / claude）の確認、`~/.local/bin/{ccr,ccn}` の配置、この skill の配置、`ccr doctor` の実行まで行う。
   - fzf は brew、または sudo 不要な apt で自動導入する。自動で入らなければ、表示された導入コマンドをユーザーに渡す。
2. リモートホストを追加する（1 台ごと）。
   1. 接続先を特定する。
      - Tailscale の場合: `tailscale status --json | jq -r '.Self.HostName, (.Peer[] | "\(.HostName) \(.DNSName) \(.OS) online=\(.Online)")'` を実行する。自分自身（`.Self`）と、スマホなど PC ではない端末（OS が iOS / android）は除外する。
   2. リモートのユーザー名を確認する。ローカルと同じとは限らないので、ユーザーに「リモートで `whoami` を実行した結果」を聞く。
   3. `~/.ssh/config` にエイリアスを追記する。
      ```sshconfig
      Host <alias>
        HostName <DNS名 or IP>
        User <リモートの whoami>
        IdentityFile ~/.ssh/id_ed25519
      ```
      `~/.ssh/id_ed25519` がなければ、`ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519` で作成する。
   4. ホストを登録する: `curl -fsSL .../install.sh | sh -s -- --host <alias>`（または `echo <alias> >> ~/.config/ccr/hosts`）。
   5. `ccr doctor <alias>` を実行し、`fix:` に従って直す。主な項目:

| doctor の表示 | 対処 | 誰が実行するか |
|---|---|---|
| `ssh  Host key verification failed.` | `ssh <alias> true` を実行し、fingerprint を確認して yes と答える | ユーザー |
| `ssh  Permission denied` | **ローカルで** `ssh-copy-id -i ~/.ssh/id_ed25519.pub <alias>` を実行し、リモートのログインパスワードを入力する。失敗が続くなら `User` が間違っている | ユーザー |
| `ssh  Could not resolve / timed out / refused` | HostName と Tailscale の接続を確認する。リモートが macOS なら「システム設定 → 一般 → 共有 → リモートログイン」をオンにする | エージェントが確認し、設定変更はユーザー |
| `python3  not found` | リモートで、macOS なら `xcode-select --install`、Debian 系なら `sudo apt-get install -y python3` | ユーザー |
| `claude  not found` | `ssh -t <alias> 'curl -fsSL https://claude.ai/install.sh \| bash'`。導入済みなら、リモートの `.zshrc` / `.bashrc` の PATH を確認する | エージェント（ssh が通っていれば） |
| `tmux  not found`（warn） | リモートで `brew install tmux` または `sudo apt-get install -y tmux`。なくても動くが、ssh が切れると claude も終了する | 状況による |
| `sessions  0 files`（warn） | 問題ない。`ccn <alias>:` でリモートにセッションを作れる | - |

3. 完了したら、ユーザーに次のコマンドを案内する。
   - `ccr`: 既存のセッションを選んで再開する
   - `ccn`: 新しいセッションを開始する。ホストを決めてあるなら `ccn <alias>:~/path`

## コマンド早見表

```
ccr [host...]                 # セッションを選んで resume（ローカル + ホスト）
ccr --id <prefix>             # ID の前方一致で直接 resume
ccn                           # ホスト/ディレクトリを選んで新規開始
ccn <host>                    # そのホストのディレクトリから選ぶ
ccn <host>:<path>             # 直接開始（<host>: だけなら home）
ccn ~/path | ccn .            # ローカルで直接開始
ccr ls [--json]               # 一覧を出力（非対話）
ccr doctor [host...] [--json] # 依存関係を検査
共通: --no-local  --no-tmux  -n/--dry-run  -- <claude に渡す引数>
```

- 対象ホストの決まり方: 引数 > `$CCR_HOSTS` > `~/.config/ccr/hosts`。
- ホスト名 `local` はこのマシンを指す。
- fzf の `ccn` 画面では、一覧に一致しない文字列を入力して Enter を押すと、それを `host:path` として扱う。

## 仕組み（デバッグ用）

- 一覧取得: `ssh -o BatchMode=yes <host> python3 - --scan N < ccr` を実行する。ccr 自身を標準入力で送り込み、`~/.claude/projects/*/*.jsonl` を読ませる。リモートへのインストールは不要。
- 起動: `ssh -t <host> 'exec "$SHELL" -lic "tmux new-session -A -s <name> ... cd <path> && exec claude ..."'` を実行する。ログインシェルかつ対話シェルで起動し、PATH を読ませる。
- ssh はパスワードなしで接続する前提（`BatchMode=yes`）。パスワード認証や、ssh-agent に登録していないパスフレーズ付きの鍵では動かない。
- セッションファイルの形式は Claude Code の非公開仕様。タイトルが空になったら、`ccr` の `parse()` の読み取り処理を見直す。
