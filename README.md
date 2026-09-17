# ccr

Claude Code のセッションを、ローカルと ssh 先の複数マシンにまたがって扱う CLI です。

- **`ccr`**: 全マシンのセッションを fzf の一覧で選び、そのマシン・そのディレクトリで `claude -r <id>` を実行します。
- **`ccn`**（= `ccr new`）: ホストとディレクトリを選んで、新しいセッションを開始します。
- リモートでは既定で **tmux の中で起動**します。ssh が切れても claude は動き続け、同じセッションを選び直すと再接続します。

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
│ ── first prompt ──  ...                                                  │
└──────────────────────────────────────────────────────────────────────────┘
```

- 本体は Python 標準ライブラリだけで書いた 1 ファイル（`ccr`）です。`ccn` はそのシンボリックリンクです。
- リモート側へのインストールは不要です。一覧取得のたびに、ssh 経由でスクリプト自身を送り込んで実行します。

> **AI エージェント向け:** セットアップやトラブル対応は [`skills/ccr/SKILL.md`](skills/ccr/SKILL.md) の手順に従ってください。`install.sh` を実行すると、この skill が `~/.claude/skills/ccr/` に配置されます。

---

## クイックスタート

```sh
# このマシンを client 兼 host としてセットアップし、devbox も ssh 越しに host としてセットアップする
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh -s -- --host devbox

ccr doctor   # [fail] がなくなるまで、表示される fix: に従って直す
ccr          # 既存のセッションを再開する
ccn          # 新しいセッションを開始する
```

`devbox` の部分は、`~/.ssh/config` の Host エイリアスに置き換えてください（[リモートホストの追加](#リモートホストの追加)）。

---

## 構成: client と host

| role | 役割 | 必要なもの | セットアップ方法 |
|---|---|---|---|
| **client** | `ccr` / `ccn` を実行して、他のマシンに入る | python3 3.8+、fzf、ssh、ssh 鍵、`ccr` / `ccn`、skill、`~/.config/ccr/hosts` | `install.sh --role client` |
| **host** | ssh で入られて、claude を動かす | python3 3.6+、claude（ログイン済み・ログインシェルの PATH にある）、tmux、sshd、client の公開鍵 | そのホストで `install.sh --role host`、または client から `ccr setup <host>` |

- `install.sh` の既定は **`--role both`** で、そのマシンを client と host の両方として使える状態にします。
- `--host <alias>` を付けると、client のセットアップの後に、ssh 越しにそのホストの host セットアップも実行します。
- host 側に ccr を置く必要はありません。`ccr setup` は `install.sh` の中身を ssh で送って実行します。

---

## インストール

```sh
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh                       # both
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh -s -- --host devbox   # + devbox
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh -s -- --role host     # host のみ
git clone https://github.com/y0ssh1/ccr ~/src/ccr && ~/src/ccr/install.sh                           # clone して使う（git pull で更新）
```

| オプション | 説明 |
|---|---|
| `--role client\|host\|both` | セットアップする役割（既定は `both`） |
| `--host <alias>` | `~/.config/ccr/hosts` に登録し、ssh 越しに host セットアップを実行する（複数指定可） |
| `--no-remote` | `--host` のホストは登録だけ行い、ssh 越しのセットアップはしない |
| `--authorize-key "<pubkey>"` | 公開鍵を `~/.ssh/authorized_keys` に追加する（host 用） |
| `--no-skill` | Claude Code skill を配置しない |
| `--bin <dir>` | `ccr` の配置先（既定は `~/.local/bin`。`CCR_BIN` でも指定可） |

各ロールで行う処理（冪等なので、何度実行しても同じ結果になります）:

- **host**
  1. tmux を導入する（brew / apt / dnf）。
  2. claude を導入する（`curl -fsSL https://claude.ai/install.sh | bash`）。
  3. ssh で入ったときのログインシェルから claude が見えなければ、`.zshrc` / `.bashrc` に PATH を追記する。
  4. claude のログイン状態と sshd の起動状態を確認する。macOS では、`~/.claude/oauth-token` を `CLAUDE_CODE_OAUTH_TOKEN` として読み込む設定を `.zshrc` に追加する（ssh 越しではキーチェーンを読めないため）。
  5. `--authorize-key` で渡された鍵を `authorized_keys` に登録する。
  6. 直接実行した場合は、client 側に書くべき `~/.ssh/config` のブロックを表示する（Tailscale があれば MagicDNS 名を使う）。
- **client**
  1. fzf を導入する。
  2. `ccr` / `ccn` / skill を配置する。
  3. `~/.ssh/id_ed25519` がなければ作成する。
  4. `--host` のホストを登録する。
  5. 鍵認証で入れないホストがあり、端末から実行している場合は、`ssh-copy-id` を対話で実行する。
  6. `ccr setup <host>` を実行する。
  7. 最後に `ccr doctor` を実行する。

パスワード入力、sudo、ブラウザ認証、macOS の GUI 操作が必要なものは、端末があれば対話で実行します。端末がない場合（エージェントから実行した場合など）は `[todo]` として、実行すべきコマンドを表示します。

---

## リモートホストの追加

1. **host 側:** macOS なら「システム設定 → 一般 → 共有 → リモートログイン」をオンにします。直接操作できるなら、`install.sh --role host` を実行しておくと、client 側に書くべき `~/.ssh/config` のブロックが表示されます。
2. **client 側:** `~/.ssh/config` にエイリアスを定義します。

   ```sshconfig
   Host devbox
     HostName devbox.example.ts.net   # Tailscale の MagicDNS 名や IP でもよい
     User me                          # host で `whoami` を実行した結果（client と同じとは限らない）
     IdentityFile ~/.ssh/id_ed25519
   ```

3. **client 側:** ホストを登録し、鍵の登録と host セットアップを行います。端末から実行した場合は、`ssh-copy-id` が走ってパスワードを聞かれます。

   ```sh
   curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh -s -- --role client --host devbox
   # 鍵登録済み・ホスト登録済みなら、次の 1 行でよい
   ccr setup devbox
   ```

4. **client 側:** 検査します。claude が未ログインなら、`ssh -t devbox claude auth login` を実行します。

   ```sh
   ccr doctor devbox
   ```

Tailscale を使っているなら、`ssh-copy-id` の代わりに host 側で `tailscale set --ssh` を実行して Tailscale SSH を有効にする方法もあります。

---

## 使い方

### セッションを再開する（`ccr`）

```sh
ccr                                   # ローカル + 登録済みの全ホスト
ccr devbox gpu1                       # 指定ホスト + ローカル（hosts ファイルより優先）
ccr --no-local                        # リモートのみ
ccr --id 227ea544                     # ID の前方一致で直接 resume（fzf を使わない）
ccr -- --dangerously-skip-permissions # `--` 以降は claude にそのまま渡す
```

fzf の操作: 文字を入力して絞り込み（host / project / title が対象）、Enter で resume、Esc で終了します。

### 新しいセッションを開始する（`ccn` / `ccr new`）

```sh
ccn                      # ホスト×ディレクトリの一覧から選ぶ
ccn devbox               # devbox のディレクトリから選ぶ
ccn devbox:~/src/api     # 直接開始
ccn devbox:              # devbox の home で開始
ccn ~/work/foo           # ローカルで直接開始（ccn . ならカレントディレクトリ）
ccn devbox:~/src/api -- --model opus
```

一覧に出る候補は、各ホストの home と、過去のセッションで使ったディレクトリです。一覧にないディレクトリを使いたいときは、`devbox:/path/to/dir`（ローカルなら `/path` か `~/path`）と入力して Enter を押すと、そのまま使えます。

### 非対話コマンド（スクリプト・エージェント向け）

```sh
ccr ls [host...]            # TSV: host  age  id  cwd  title
ccr ls --json               # {"sessions": [...], "errors": [...]}
ccr doctor [host...]        # 依存関係を検査（問題があれば exit 1）
ccr doctor --json           # [{"host","status":"ok|warn|fail","item","detail","fix"}]
ccr setup <host>...         # ssh 越しに host セットアップ（install.sh --role host）
ccn devbox:~/x -n           # -n / --dry-run: 実行されるコマンドを表示するだけ
```

### オプション

| オプション | 説明 |
|---|---|
| `<host>...` | 対象ホスト。指定すると `$CCR_HOSTS` と hosts ファイルは無視される。`local` はこのマシン |
| `--no-local` | ローカルを対象から外す |
| `--no-tmux` | リモートで tmux を使わず、直接起動する |
| `--id <prefix>` | セッション ID の前方一致で、fzf を使わずに resume する |
| `-n`, `--dry-run` | 起動せず、実行するコマンドを表示する |
| `--json` | `ls` / `doctor` の出力を JSON にする |
| `-- <args>` | 以降の引数を `claude` に渡す |

### 設定

| 項目 | 既定値 | 説明 |
|---|---|---|
| `~/.config/ccr/hosts` | なし | 1 行 1 ホスト。`#` 以降はコメント |
| `CCR_HOSTS` | なし | 空白区切りのホスト一覧。hosts ファイルより優先される |
| `CCR_LIMIT` | `300` | 1 ホストあたりに読むセッション数（新しい順） |

ホスト指定の優先順位: コマンドライン引数 > `CCR_HOSTS` > `~/.config/ccr/hosts`

### tmux の挙動

- リモートでの起動コマンドは `tmux new-session -A -s <name>` です。`-A` により、同名のセッションがあれば新しく作らずにそこへ接続します。
  - resume 時のセッション名: `ccr-<セッションID先頭8文字>`
  - 新規開始時: `ccn` が `claude --session-id <uuid>` で ID を先に決めるので、名前は resume 時と同じ `ccr-<ID先頭8文字>` になります。`ccn` で始めて切断した後に `ccr` で選ぶと、同じ tmux に再接続します。
- ssh が切れても claude は動き続けます。`ccr` で同じセッションを選ぶと再接続します。
- tmux から抜けるときは、`Ctrl-b d` で detach します（claude は動いたまま）。
- リモートに tmux がない場合は、警告を出して直接起動します。この場合、ssh が切れると claude も終了します。
- ローカルでは tmux を使いません。

---

## 仕組み

1. **一覧の取得（scan）**
   - ローカル: `~/.claude/projects/*/*.jsonl` を新しい順に最大 `CCR_LIMIT` 件読みます。
   - リモート: `ssh -o BatchMode=yes -o ConnectTimeout=5 <host> python3 - --scan <N>` を実行し、標準入力に `ccr` 自身を流し込んで同じ処理を実行させます。複数ホストは並列に処理します。
   - 各セッションから取り出す値:
     - ファイル名: `id`
     - 先頭付近の行: `cwd` / `gitBranch` / 最初のユーザープロンプト
     - 末尾 512KB: `custom-title` / `ai-title` / `last-prompt`
2. **表示**
   - 全ホスト分を新しい順に並べて fzf に渡します。
   - プレビューは、一覧取得時に書き出した一時ファイルを表示するので、ssh し直すことはありません。一時ファイルは終了時に削除します。
3. **起動**
   - ローカル: `cd <cwd>` してから `exec claude ...` を実行します。
   - リモート: `ssh -t <host> 'exec "$SHELL" -lic "…tmux new-session -A -s <name> … cd <cwd> && exec claude …"'` を実行します。ログインシェルかつ対話シェルで起動するのは、`.zshrc` などで追加される PATH（`~/.local/bin` など）を読ませるためです。
4. **setup**
   - `ssh <host> sh -c '<install.sh の中身>' install.sh --role host` を実行します。
   - install.sh は、ローカルの clone にあればそれを使い、なければ GitHub から取得します。
5. **doctor**
   - リモートのログインシェルで `command -v python3 claude tmux` と `python3` の動作確認を行い、`~/.claude/projects` のファイル数を数えます。
   - ssh が失敗した場合は、エラー文から原因を分類して直し方を表示します。

内部サブコマンド（ユーザーが直接使うことは想定していません）:

- `ccr --scan [N]`: 実行したマシンのセッション一覧を JSON で出力します。形式は `{"home": str, "sessions": [{"id","cwd","branch","mtime","title","first","last"}]}` です。
- `ccr --preview <file>`: fzf のプレビュー表示に使います。

---

## トラブルシューティング

まず `ccr doctor` を実行してください。多くの場合、`fix:` に直し方が表示されます。

| 症状 / 表示 | 原因 | 対処 |
|---|---|---|
| `Host key verification failed.` | ホスト鍵がまだ `known_hosts` にない | `ssh <host> true` を実行して yes と答える |
| `Permission denied (publickey,...)` | 鍵認証が設定されていない | **ローカルで** `ssh-copy-id -i ~/.ssh/id_ed25519.pub <host>` を実行する |
| `Password:` を何度も聞かれて失敗する | ユーザー名が違う | リモートで `whoami` を実行し、その値を `~/.ssh/config` の `User` に書く |
| `Could not resolve` / `timed out` / `refused` | ホストに到達できない、または sshd が停止している | HostName と Tailscale の接続を確認する。macOS ならリモートログインをオンにする |
| `python3` / `claude` / `tmux` が not found | host のセットアップが済んでいない | `ccr setup <host>`（macOS で python3 がない場合は、host で `xcode-select --install` の GUI 承認が必要） |
| `claude login 未ログイン` | host の claude が未認証 | `ssh -t <host> claude auth login` |
| `claude login ssh からはキーチェーンがロックされていて…` | macOS の host では、認証情報がキーチェーンにある。ssh セッションからはキーチェーンがロックされていて読めない | host で一度だけ `claude setup-token` を実行し、表示されたトークンをコピーして `(umask 077; pbpaste > ~/.claude/oauth-token)` で保存する。`ccr setup` が `.zshrc` に読み込み設定を追加済み。トークンがなくても、起動時に `security unlock-keychain` を実行してパスワードで解除する |
| `ccr: tmux が無いため直接起動します` | host に tmux がない | `ccr setup <host>` |
| resume 時に `cd: no such file or directory` | ディレクトリが削除・移動されている | ディレクトリを元の場所に戻す |
| 一覧が開くまで遅い | ホストごとに毎回 ssh 接続している | `~/.ssh/config` に `ControlMaster auto` / `ControlPath ~/.ssh/cm-%r@%h:%p` / `ControlPersist 10m` を設定する |
| title が空になる | Claude Code のセッションファイル形式が変わった | 最初のプロンプトが代わりに表示されるので、一覧は使える。`parse()` の読み取り処理を修正する |

---

## 制約

- Claude Code のセッションファイル（`~/.claude/projects/**.jsonl`）の内部形式に依存しています。公開仕様ではありません。
- ssh は `BatchMode=yes` で接続します。パスワード認証や、ssh-agent に登録していないパスフレーズ付きの鍵には対応していません。
- ローカルで tmux を使っている場合、リモートの tmux が入れ子になります。prefix キーが衝突するときは、リモートで `Ctrl-b` を 2 回押して送るなどで対応してください。
- Windows には対応していません。
