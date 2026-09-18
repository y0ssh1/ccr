---
name: ccr
description: ccr / ccn（ローカルと ssh 先の複数マシンにまたがって Claude Code セッションを resume・新規開始する CLI）のセットアップ、ホスト追加、依存関係の解消、トラブル対応。「リモートのセッションを再開したい」「別マシンで claude を起動したい」「ccr にホストを追加」「ccr が動かない」「ccr doctor」などで使う。ssh 越しのセッションで gh が 401 / token is invalid になる、macOS のキーチェーンが読めない、docker などの認証が ssh でだけ落ちる、といった症状の切り分けと直し方（tmux サーバーを GUI ログイン側で常駐させる）もここ。
---

# ccr / ccn

- `ccr`: ローカルと ssh 先の全マシンにある Claude Code セッションを fzf の一覧で選び、そのマシン・そのディレクトリで `claude -r <id>` を実行する。
- `ccn`（= `ccr new`）: ホストとディレクトリを選んで、新しいセッションを開始する。
- リモートでは既定で tmux の中で起動する。ssh が切れても claude は動き続け、同じセッションを選ぶと再接続できる。
- リポジトリ: https://github.com/y0ssh1/ccr

## 構成: client と host

| role | 役割 | 必要なもの |
|---|---|---|
| client | `ccr` / `ccn` を実行して、他のマシンに入る側 | python3 3.8+、fzf、ssh、ssh 鍵、`ccr` / `ccn`、この skill、`~/.config/ccr/hosts` |
| host | ssh で入られて、claude を動かす側 | python3 3.6+、claude（ログイン済み・ログインシェルの PATH にある）、tmux、sshd、`authorized_keys` への client 鍵の登録 |

`install.sh` の既定は `--role both` で、1 台を client と host の両方として使える状態にする。`--host <alias>` を付けると、client のセットアップの後に、**ssh 越しにそのホストの host セットアップ**（`ccr setup <alias>`）も実行する。

## エージェントが守ること

1. **`ccr` / `ccn` を引数なし、または `-n` なしで実行しない。** fzf や ssh -t を使う対話 TUI なので、エージェントのシェルでは動かない。起動はユーザーのターミナルで行ってもらい、コピペできる 1 行のコマンドを渡す。
2. エージェントが実行してよい非対話コマンド:
   - `ccr doctor [host...] [--json]`: 依存関係を検査する。`[fail]` があると終了コード 1 を返し、項目ごとに `fix:` を表示する
   - `ccr setup <host...>`: ssh 越しに host のセットアップを実行する。冪等
   - `ccr ls [host...] [--json]`、`ccr --id <prefix> -n`、`ccn <target> -n`: 一覧の出力と dry-run
   - `curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh -s -- [--role client|host|both] [--host <alias>]...`: 冪等
3. **ユーザーにしかできない操作は、実行せずコマンドを渡す。** `install.sh` も、端末がなければこれらを `[todo]` として出力する。
   - パスワード入力: `ssh-copy-id`
   - fingerprint の確認: 初回の `ssh <host> true`
   - ブラウザでの認証: `claude auth login`
   - sudo のパスワード入力
   - macOS の GUI 操作: リモートログインの有効化、`xcode-select --install`
4. `~/.ssh/config` を編集する前に中身を読む。既存の `Host` ブロックは壊さず、追記する。

## セットアップ手順

`ccr doctor` の `[fail]` がなくなるまで、次を繰り返す。

1. **このマシン（client + host）をセットアップする:** `curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh`
2. **リモートホストを追加する（1 台ごと）。**
   1. 接続先を特定する。
      - Tailscale の場合: `tailscale status --json | jq -r '.Self.HostName, (.Peer[] | "\(.HostName) \(.DNSName) \(.OS) online=\(.Online)")'` を実行する。自分自身（`.Self`）と、PC ではない端末（OS が iOS / android）は除外する。
   2. リモートのユーザー名を確認する。ローカルと同じとは限らないので、ユーザーに「リモートで `whoami` を実行した結果」を聞く。リモートで `install.sh --role host` を実行すると、client 側に書くべき `~/.ssh/config` のブロックも表示される。
   3. `~/.ssh/config` にエイリアスを追記する。
      ```sshconfig
      Host <alias>
        HostName <DNS名 or IP>
        User <リモートの whoami>
        IdentityFile ~/.ssh/id_ed25519
      ```
   4. 鍵を登録する（ユーザーが実行）: `ssh-copy-id -i ~/.ssh/id_ed25519.pub <alias>`。リモートが macOS なら、先に「リモートログイン」をオンにしてもらう。
   5. ホストの登録と host セットアップをまとめて行う: `curl -fsSL .../install.sh | sh -s -- --role client --host <alias>`（登録済みなら `ccr setup <alias>` だけでよい）。
   6. `ccr doctor <alias>` を実行し、`fix:` に従って直す。

| doctor の表示 | 対処 | 誰が実行するか |
|---|---|---|
| `ssh  Host key verification failed.` | `ssh <alias> true` を実行し、fingerprint を確認して yes と答える | ユーザー |
| `ssh  Permission denied` | **ローカルで** `ssh-copy-id -i ~/.ssh/id_ed25519.pub <alias>` を実行する。失敗が続くなら `User` が間違っている | ユーザー |
| `ssh  Could not resolve / timed out / refused` | HostName と Tailscale の接続を確認する。リモートが macOS なら「システム設定 → 一般 → 共有 → リモートログイン」をオンにする | 確認はエージェント、設定変更はユーザー |
| `python3` / `claude` / `tmux` の不足 | `ccr setup <alias>` | エージェント（macOS の python3 だけは、リモートで `xcode-select --install` の GUI 承認が必要） |
| `claude login  未ログイン` | `ssh -t <alias> claude auth login` | ユーザー |
| `claude login  ssh からはキーチェーンがロックされていて…`（macOS の host） | host のターミナルで `curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh \| sh -s -- --role host --token` を実行する（ブラウザ認証 → トークンの貼り付け）。トークンがなくても、起動時にキーチェーン解除のパスワードを聞かれるだけで使える | ユーザー（host のターミナル。ssh 越しではブラウザが開かない） |
| local の `sshd` / `tmux` の warn | このマシンを host として使わないなら無視してよい | - |

3. 完了したら、ユーザーに次のコマンドを案内する。
   - `ccr`: 既存のセッションを選んで再開する
   - `ccn`: 新しいセッションを開始する。行き先が決まっているなら `ccn <alias>:~/path`

## macOS の host: ssh 越しでも gh / docker などにキーチェーンを使わせる

**症状**: ccr で入ったセッションで、`git push`（ssh 鍵）は通るのに `gh` が `HTTP 401` / `The token in default is invalid` になる。docker の credential helper など、キーチェーンに認証情報を置く CLI が同じ形で落ちる。**トークンの失効ではない。**

**原因**: ssh から起動した tmux サーバーは macOS の **Background セッション**に属し、その中のプロセスはログインキーチェーンを読めない（読めるのは GUI ログイン側＝**Aqua セッション**のプロセスだけ）。ccr は既定ソケットの tmux に `new-session -A` で入るので、**tmux サーバーが先に Aqua 側で立っていれば**、ssh 越しに開いたセッションも Aqua に属し、claude とその下の CLI が全部キーチェーンを使える。パスワードはどこにも保存しない。

claude 自身の認証は別の仕組み（`--token` の長期トークン / 起動時の `security unlock-keychain`）で動いているので、**claude が動いていてもこの問題は残る**。

### 切り分け（エージェントが実行してよい。読み取りだけ）

```sh
echo "${SSH_CONNECTION:-(ssh ではない)}"
launchctl managername                     # Aqua なら読める側 / Background なら読めない側
security show-keychain-info 2>&1 | head -1 # 「User interaction is not allowed」なら読めていない
launchctl print gui/$(id -u) >/dev/null 2>&1 && echo "GUI ログインあり" || echo "GUI ログインなし"
grep -c oauth_token ~/.config/gh/hosts.yml # 0 なら gh のトークンはキーチェーンにある
```

`managername` が `Background` で、GUI ログインがあるなら、下の手順で直る。

### 直し方: tmux サーバーを Aqua 側で常駐させる LaunchAgent

**エージェントは設置しない。** 常駐設定の追加は権限チェックで拒否される（拒否されなくても、ユーザーのマシンに常駐物を置く判断はユーザーのもの）。plist をユーザーに見せ、設置のコマンドを渡す。

1. `tmux` の絶対パスを確認する（`command -v tmux`。Apple Silicon の brew は `/opt/homebrew/bin/tmux`、Intel は `/usr/local/bin/tmux`）。**launchd は PATH を読まないので絶対パスで書く。**
2. 次の内容を `~/Library/LaunchAgents/io.github.y0ssh1.ccr.tmux-aqua.plist` に置いてもらう（`<tmux>` を 1 の値に置き換える）。

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key><string>io.github.y0ssh1.ccr.tmux-aqua</string>
     <key>LimitLoadToSessionType</key><string>Aqua</string>
     <key>ProgramArguments</key>
     <array>
       <string>/bin/sh</string><string>-c</string>
       <string><tmux> list-sessions >/dev/null 2>&amp;1 || <tmux> new-session -d -s keychain-host</string>
     </array>
     <key>RunAtLoad</key><true/>
     <key>StartInterval</key><integer>30</integer>
     <key>AbandonProcessGroup</key><true/>
   </dict>
   </plist>
   ```

   - tmux サーバーが 1 つも無いときだけ、番人セッション `keychain-host` を作る（＝サーバーを Aqua 側で起こす）。既にサーバーがあれば何もしない
   - `AbandonProcessGroup` が無いと、tmux がデーモン化した後に launchd がサーバーごと片付ける
   - `LimitLoadToSessionType=Aqua` なので、GUI ログインしていないと動かない
3. 読み込んでもらう（ユーザーが実行）: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.github.y0ssh1.ccr.tmux-aqua.plist`
   - エラーが出なければ成功。`Bootstrap failed: 5` は多くの場合「既に読み込み済み」か「GUI ログインが無い」

### ⚠ 効き始めるのは、今の tmux サーバーが終わってから

既に ssh 起動（Background）の tmux サーバーが動いていると、LaunchAgent は「サーバーあり」で何もしない。**切り替えには今のサーバーを終わらせる必要があり、そのサーバーの中の claude セッションは全部落ちる**（会話は `ccr` で resume できる）。

- **エージェントは `tmux kill-server` を実行しない。** 自分が動いているセッションごと落ちる。ユーザーに「いつ切り替えるか」を選んでもらう
  - 急がない: 開いている ccr セッションを全部閉じ終えたら、30 秒以内に Aqua 側で立つ
  - すぐ: ユーザーが `tmux kill-server` → 30 秒待って ccr で入り直す
- 確認: 入り直したセッションで `launchctl managername` が `Aqua`、`gh auth status` が通る

### それでも読めないとき

| 状況 | 対処 | 誰が |
|---|---|---|
| Mac に GUI ログインしていない（再起動直後など） | Aqua セッションが無いので効かない。画面でログインする（自動ログインの設定はユーザーの判断） | ユーザー |
| 初めてその項目に触るバイナリ / アップデートで署名が変わった CLI | Mac の**画面に**許可ダイアログが出て止まる。画面（または画面共有）で「常に許可」を 1 回押す | ユーザー |
| Aqua 側に切り替えられない事情がある（常駐物を置けない・GUI ログインできない） | CLI ごとにキーチェーンを使わない設定へ。gh なら `gh auth login -h github.com -p ssh --web --insecure-storage`（トークンを `~/.config/gh/hosts.yml` に平文 600 で保存）か、fine-grained PAT を `GH_TOKEN` に | ユーザー（トークンを平文で置く判断を含む） |
| そのセッションだけ今すぐ通したい | `security unlock-keychain`（ログインパスワードを聞かれる。そのセッション限り）。`-p` でパスワードを渡さない（履歴に残る） | ユーザー |

外すとき（ユーザーが実行）: `launchctl bootout gui/$(id -u)/io.github.y0ssh1.ccr.tmux-aqua && rm ~/Library/LaunchAgents/io.github.y0ssh1.ccr.tmux-aqua.plist`

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
ccr setup <host...>           # ssh 越しに host セットアップ
共通: --no-local  --no-tmux  -n/--dry-run  -- <claude に渡す引数>
```

- 対象ホストの決まり方: 引数 > `$CCR_HOSTS` > `~/.config/ccr/hosts`。
- ホスト名 `local` はこのマシンを指す。
- fzf の `ccn` 画面では、一覧に一致しない文字列を入力して Enter を押すと、それを `host:path` として扱う。

## 仕組み（デバッグ用）

- 一覧取得: `ssh -o BatchMode=yes <host> python3 - --scan N < ccr` を実行する。ccr 自身を標準入力で送り込み、`~/.claude/projects/*/*.jsonl` を読ませる。リモートへのインストールは不要。
- host セットアップ: `ssh <host> sh -c '<install.sh の中身>' install.sh --role host` を実行する。リモートに ccr を置く必要はない。
- 起動: `ssh -t <host> 'exec "$SHELL" -lic "tmux new-session -A -s <name> ... cd <path> && exec claude ..."'` を実行する。ログインシェルかつ対話シェルで起動し、PATH を読ませる。
- ssh はパスワードなしで接続する前提（`BatchMode=yes`）。パスワード認証や、ssh-agent に登録していないパスフレーズ付きの鍵では動かない。
- セッションファイルの形式は Claude Code の非公開仕様。タイトルが空になったら、`ccr` の `parse()` の読み取り処理を見直す。
