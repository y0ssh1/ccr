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
# 1. インストール（依存確認 → ccr/ccn 配置 → skill 配置 → ホスト登録 → doctor）
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh -s -- --host devbox

# 2. doctor の [fail] を fix: の指示どおりに直す（なくなるまで繰り返す）
ccr doctor

# 3. 使う
ccr          # 既存のセッションを再開
ccn          # 新しいセッションを開始
```

`devbox` の部分は、`~/.ssh/config` に定義した Host エイリアスに置き換えてください。ssh の設定方法は[リモートホストの追加](#リモートホストの追加)を参照してください。

---

## 必要なもの

| 場所 | 必要なもの | 確認方法 |
|---|---|---|
| ローカル | `python3` 3.8+、`fzf`、`ssh`、`claude` | `ccr doctor` |
| 各リモート | **パスワードを聞かれずに**ssh できること（鍵認証） | `ccr doctor <host>` |
| 各リモート | `python3` 3.6+、`claude` がログインシェルの PATH にあること | `ccr doctor <host>` |
| 各リモート（推奨） | `tmux`。ないと、ssh が切れたときに claude も終了する | `ccr doctor <host>` |

`ccr doctor` は問題を見つけると終了コード 1 を返し、項目ごとに `fix:` として直し方を表示します。

---

## インストール

```sh
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh
# ホスト登録も同時に行う場合
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/install.sh | sh -s -- --host devbox --host gpu1
# clone して使う場合（ccr と skill は clone 内のファイルへのシンボリックリンクになり、git pull で更新される）
git clone https://github.com/y0ssh1/ccr ~/src/ccr && ~/src/ccr/install.sh
```

`install.sh` は冪等で、次の処理を行います。

1. `python3` (3.8+) を確認します。`fzf` がなければ、`brew`、または sudo 不要な `apt-get` で導入を試みます。
2. `ccr` と `ccn` を `~/.local/bin` に配置します（`--bin <dir>` または `CCR_BIN` で変更可能）。
3. Claude Code 用の skill を `~/.claude/skills/ccr/SKILL.md` に配置します（`--no-skill` で省略）。
4. `--host` で指定したホストを `~/.config/ccr/hosts` に追記します。登録済みのホストは重複して追記しません。
5. `ccr doctor` を実行します。

パスワード入力や sudo が必要な操作は実行しません。実行すべきコマンドを表示します。

---

## リモートホストの追加

1. **ssh エイリアスを定義します。** `~/.ssh/config` に追記します。

   ```sshconfig
   Host devbox
     HostName devbox.example.ts.net   # Tailscale の MagicDNS 名や IP でもよい
     User me                          # リモートで `whoami` を実行した結果（ローカルと同じとは限らない）
     IdentityFile ~/.ssh/id_ed25519
   ```

2. **リモートで ssh ログインを受け付けるようにします。** macOS なら「システム設定 → 一般 → 共有 → リモートログイン」をオンにします。

3. **鍵を登録します。** **ローカル側で**実行します。初回は fingerprint の確認（yes）と、リモートのログインパスワードの入力を求められます。

   ```sh
   ssh-copy-id -i ~/.ssh/id_ed25519.pub devbox
   ```

   Tailscale を使っているなら、代わりにリモートで `tailscale set --ssh` を実行して Tailscale SSH を有効にする方法もあります。

4. **ホストを登録して検査します。**

   ```sh
   echo devbox >> ~/.config/ccr/hosts
   ccr doctor devbox
   ```

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
  - 新規開始時のセッション名: `ccn-<host>-<HHMMSS>`
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
4. **doctor**
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
| `python3 not found` | リモートに python3 がない | macOS なら `xcode-select --install`、Debian 系なら `sudo apt-get install -y python3` |
| `claude not found` | ログインシェルの PATH に claude がない | `ssh -t <host> 'curl -fsSL https://claude.ai/install.sh \| bash'` を実行する。導入済みなら PATH の設定を確認する |
| `ccr: tmux が無いため直接起動します` | リモートに tmux がない | `brew install tmux` または `sudo apt-get install -y tmux` |
| resume 時に `cd: no such file or directory` | ディレクトリが削除・移動されている | ディレクトリを元の場所に戻す |
| 一覧が開くまで遅い | ホストごとに毎回 ssh 接続している | `~/.ssh/config` に `ControlMaster auto` / `ControlPath ~/.ssh/cm-%r@%h:%p` / `ControlPersist 10m` を設定する |
| title が空になる | Claude Code のセッションファイル形式が変わった | 最初のプロンプトが代わりに表示されるので、一覧は使える。`parse()` の読み取り処理を修正する |

---

## 制約

- Claude Code のセッションファイル（`~/.claude/projects/**.jsonl`）の内部形式に依存しています。公開仕様ではありません。
- ssh は `BatchMode=yes` で接続します。パスワード認証や、ssh-agent に登録していないパスフレーズ付きの鍵には対応していません。
- ローカルで tmux を使っている場合、リモートの tmux が入れ子になります。prefix キーが衝突するときは、リモートで `Ctrl-b` を 2 回押して送るなどで対応してください。
- Windows には対応していません。
