# ccr

`claude -r` をローカルと ssh 先のマシンに広げたコマンド。全マシンの Claude Code セッションを fzf の一覧にまとめ、選ぶとそのマシン・そのディレクトリで `claude -r <id>` を実行する（リモートなら ssh で入ってから実行する）。

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/y0ssh1/ccr/main/ccr -o ~/.local/bin/ccr && chmod +x ~/.local/bin/ccr
```

必要なもの: `python3` と `fzf`（ローカル）、`python3` と `claude`（リモート）、パスワードなしで通る ssh（鍵認証）。

## Usage

```sh
echo "devbox" >> ~/.config/ccr/hosts   # ssh config の Host エイリアスでよい
ccr                       # ローカル + 登録ホスト
ccr devbox                # ホスト指定
ccr --no-local            # リモートのみ
ccr --tmux                # リモートを tmux 内で resume（切断しても生きる）
ccr -- --dangerously-skip-permissions   # claude -r に引数を追加
```

ホストは `$CCR_HOSTS`（空白区切り）か `~/.config/ccr/hosts`（1行1ホスト）で指定する。

## How it works

- 自分自身を `ssh host python3 - --scan` で送り込んで実行し、`~/.claude/projects/*/*.jsonl` からセッション情報を集める。リモート側へのインストールは不要。
- セッションファイルの内部形式に依存しているため、Claude Code の更新でタイトルが取れなくなることがある（その場合は最初のプロンプトを表示する）。
