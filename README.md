# ccr

`claude -r` をローカルと ssh 先の複数マシンに広げた CLI です。

全マシンにある Claude Code のセッションを fzf の一覧にまとめて表示します。1つ選ぶと、そのセッションがあるマシンの、そのセッションを作ったディレクトリで `claude -r <session-id>` を実行します。リモートのセッションなら、ssh で自動的にログインしてから実行します。

```
resume>
  host     age  project                                   title
> local     2m  ~/work/point                              課金バッチの二重実行調査
  devbox    1h  ~/src/api                                 Rails 8 アップグレード
  local     3d  ~/work                                    JPYC バリデーター
┌──────────────────────────────────────────────────────────────────────────┐
│ host   : devbox                                                          │
│ cwd    : /home/me/src/api                                                │
│ branch : feature/rails8                                                  │
│ id     : 227ea544-f19f-4d09-b9cf-fe80b70fb315                            │
│ ── first prompt ──                                                       │
│ ...                                                                      │
└──────────────────────────────────────────────────────────────────────────┘
```

- 実体は Python 標準ライブラリだけで書いた 1 ファイル（`ccr`）です。pip で入れるパッケージは不要です。
- リモート側へのインストールは不要です。一覧を取るたびに、ssh 経由でスクリプト自身を送り込んで実行します。

---

## 必要なもの

| 場所 | 必要なもの | 確認コマンド |
|---|---|---|
| ローカル | `python3` (3.8+), `fzf`, `ssh`, `claude` | `which python3 fzf ssh claude` |
| 各リモート | `python3` (3.8+), `claude` がログインシェルの PATH にあること | `ssh <host> '$SHELL -lic "which python3 claude"'` |
| 各リモート | **パスワードを聞かれずに** ssh できること（鍵認証） | `ssh -o BatchMode=yes <host> true && echo ok` |
| 各リモート（任意） | `tmux`（`--tmux` を使う場合） | `ssh <host> 'which tmux'` |

macOS の注意点: 標準の `/usr/bin/python3` は、Command Line Tools（`xcode-select --install`）を入れるまで使えません。

---

## セットアップ手順

AI エージェントに実行させる場合も、この順番で進めてください。各ステップの「確認」が通ってから次へ進みます。

### 1. インストール

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/ccr -o ~/.local/bin/ccr
chmod +x ~/.local/bin/ccr
```

確認: `ccr --help` の出力が表示されること。`~/.local/bin` が PATH に入っていない場合は、シェルの設定ファイルに追加します。

### 2. ssh の接続設定（リモート 1 台ごと）

`~/.ssh/config` にホストのエイリアスを定義します。ccr はこのエイリアス名でホストを参照します。

```sshconfig
Host devbox
  HostName devbox.example.ts.net   # Tailscale の MagicDNS 名や IP でもよい
  User me                          # リモート側のユーザー名（リモートで `whoami` した結果）
  IdentityFile ~/.ssh/id_ed25519
```

鍵がまだリモートに登録されていなければ、**ローカル側で**次を実行します。リモートのログインパスワードを 1 回だけ聞かれます。

```sh
ssh-copy-id -i ~/.ssh/id_ed25519.pub devbox
```

- リモートが macOS の場合は、先に「システム設定 → 一般 → 共有 → リモートログイン」をオンにします。
- Tailscale を使っているなら、`ssh-copy-id` の代わりにリモート側で `tailscale set --ssh` を実行して Tailscale SSH を有効にする方法もあります。

確認: `ssh -o BatchMode=yes devbox 'hostname; $SHELL -lic "which python3 claude"'` が、パスワードなしで python3 と claude のパスを表示すること。

### 3. ホストを登録

```sh
mkdir -p ~/.config/ccr
cat >> ~/.config/ccr/hosts <<'EOF'
# 1 行 1 ホスト。~/.ssh/config の Host エイリアスを書く。# 以降はコメント
devbox
EOF
```

確認: `ssh -o BatchMode=yes devbox python3 - --scan 5 < ~/.local/bin/ccr` が、`{"home": ..., "sessions": [...]}` という形の JSON を返すこと。

### 4. 実行

```sh
ccr
```

一覧取得に失敗したホストがあると、fzf のヘッダーに `! <host>: <エラー>` と表示されます。

---

## 使い方

```sh
ccr                                      # ローカル + 登録済みの全ホスト
ccr devbox gpu1                          # 指定したホストのみ（hosts ファイルより優先）。ローカルも含む
ccr --no-local                           # リモートのみ
ccr --tmux                               # リモートでは tmux セッション内で resume する
ccr -- --dangerously-skip-permissions    # `--` より後ろはそのまま `claude -r <id>` に渡す
```

fzf 上の操作は通常の fzf と同じです。文字を入力して絞り込み、Enter で resume、Esc で終了します。検索対象は host / project / title の列です。

### オプション

| オプション | 説明 |
|---|---|
| `<host>...` | 対象ホストを指定する。指定すると `$CCR_HOSTS` と hosts ファイルは無視される |
| `--no-local` | ローカルのセッションを一覧に出さない |
| `--tmux` | リモートで `tmux new-session -A -s ccr-<id先頭8文字>` の中で起動する。回線が切れてもセッションが残り、同じセッションを選ぶと再接続する |
| `-- <args>` | 以降の引数を `claude -r <id>` に追加する |
| `-h`, `--help` | ヘルプを表示する |

### 設定

| 項目 | 既定値 | 説明 |
|---|---|---|
| `~/.config/ccr/hosts` | なし | 対象ホストの一覧。1 行 1 ホスト、`#` 以降はコメント |
| `CCR_HOSTS` | なし | 空白区切りのホスト一覧。設定すると hosts ファイルより優先される |
| `CCR_LIMIT` | `300` | 1 ホストあたりに読むセッション数（更新日時の新しい順） |

ホスト指定の優先順位: コマンドライン引数 > `CCR_HOSTS` > `~/.config/ccr/hosts`

---

## 仕組み

1. **一覧の取得（scan）**
   - ローカル: `~/.claude/projects/*/*.jsonl` を更新日時の新しい順に最大 `CCR_LIMIT` 件読みます。
   - リモート: `ssh -o BatchMode=yes -o ConnectTimeout=5 <host> python3 - --scan <N>` を実行し、標準入力に `ccr` 自身を流し込んで、同じ scan 処理を実行させます。複数ホストは並列に処理します。
   - 各セッションから取り出す値:
     - `id`: ファイル名
     - `cwd`, `gitBranch`: 先頭付近の行から
     - 最初のユーザープロンプト
     - 末尾 512KB から `custom-title` / `ai-title` / `last-prompt`
2. **表示**
   - 全ホスト分を更新日時の新しい順に並べて fzf に渡します。
   - プレビューは `ccr --preview <tmpfile>` です。一覧取得時にセッション情報を一時ファイルに書いておき、それを表示します。そのため、プレビューのために ssh し直すことはありません。一時ファイルは終了時に削除します。
3. **resume**
   - ローカル: `cd <cwd>` してから `exec claude -r <id>` を実行します。
   - リモート: `ssh -t <host> 'exec "$SHELL" -lic "cd <cwd> && exec claude -r <id>"'` を実行します。ログインシェルかつ対話シェルで起動するのは、`~/.local/bin` など `.zshrc` / `.bash_profile` で追加される PATH を読ませるためです。

### 内部サブコマンド

ユーザーが直接使うことは想定していません。

| コマンド | 出力 |
|---|---|
| `ccr --scan [N]` | 実行したマシンのセッション一覧を JSON で出力する: `{"home": str, "sessions": [{"id","cwd","branch","mtime","title","first","last"}]}` |
| `ccr --preview <file>` | 一時ファイルに書いたセッション情報を人間向けに整形して出力する |

---

## トラブルシューティング

| 症状 / fzf ヘッダーの表示 | 原因 | 対処 |
|---|---|---|
| `Host key verification failed.` | リモートのホスト鍵がまだ `known_hosts` にない | `ssh <host> true` を一度手動で実行し、`yes` と答える |
| `Permission denied (publickey,...)` | 鍵認証が設定されていない | ローカル側で `ssh-copy-id -i ~/.ssh/id_ed25519.pub <host>` を実行する |
| `Password:` を何度も聞かれて失敗する | ユーザー名が違う | リモートで `whoami` を実行し、その値を `~/.ssh/config` の `User` に書く |
| `python3: command not found` や `xcode-select` 関連 | リモートに python3 がない | macOS なら `xcode-select --install`、Linux ならパッケージマネージャで python3 を入れる |
| エラーは出ないのにリモートのセッションが出ない | リモートの `~/.claude/projects` にセッションがない | リモートで `ls ~/.claude/projects` を実行して確認する |
| resume 時に `claude: command not found` | ログインシェルの PATH に claude がない | リモートの `.zshrc` / `.bashrc` で claude のあるディレクトリを PATH に追加する |
| resume 時に `cd: no such file or directory` | セッションを作ったディレクトリが削除・移動されている | 元のパスにディレクトリを戻す |
| 一覧が開くまで遅い | ホストごとに毎回 ssh 接続している | `~/.ssh/config` に `ControlMaster auto` / `ControlPath ~/.ssh/cm-%r@%h:%p` / `ControlPersist 10m` を設定する |
| title が空になる | Claude Code のセッションファイル形式が変わった | 最初のプロンプトが代わりに表示されるので、一覧自体は使える。`parse()` の読み取り処理を修正する |

---

## 制約

- Claude Code のセッションファイル（`~/.claude/projects/**.jsonl`）の内部形式に依存しています。公開仕様ではないため、Claude Code の更新で動かなくなる可能性があります。
- ssh は `BatchMode=yes` で接続するので、パスワード認証やパスフレーズ付きの鍵（ssh-agent 未登録）には対応していません。
- Windows には対応していません。
