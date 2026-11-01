# pushme

シェルや cron から、自分の Android 端末にプッシュ通知を送るコマンドです。

```sh
pushme ビルドが終わりました
pushme run -- make test      # 終わったら成否・所要時間を通知
```

通知の配信には [ntfy](https://ntfy.sh/) の公開サーバー ntfy.sh（無料枠）を使います。アカウントは要りません。推測されにくい「トピック名」がパスワードの代わりになります。

## 必要なもの

- bash 3.2 以降（macOS 標準の `/bin/bash` で動きます）
- curl
- jq（Claude Code から通知する場合だけ）
- Android 端末と ntfy アプリ（Google Play または F-Droid）

## インストール

```sh
git clone https://github.com/uskey512/pushme.git
cd pushme
make install   # ~/.local/bin/pushme に入る
pushme init
```

- インストール先は `make install PREFIX=/usr/local` のように変えられます
- インストール先が `PATH` に入っていない場合は案内を表示します。シェルの設定ファイルは書き換えません

### `pushme init`

設定ファイル `~/.config/pushme/config` を作ります。最初にトピック名を尋ねます。

- **すでにトピック名がある**: 貼り付けて Enter（入力した文字は画面に出ません）。`pbpaste | pushme init` のように標準入力から渡すこともできます
- **初めて使う**: 空のまま Enter を押すと、新しいトピック名（`ntfy-` と英数字 59 文字、合計 64 文字）を生成します。表示されるのはこの 1 回だけなので、パスワード管理ツールに保存してください

トピック名をコマンドライン引数で渡す方法はありません（シェルの履歴に残るため）。設定ファイルが既にあるときは何もしません。作り直すには `pushme init --force` を使います。

最後にテスト通知を送るか尋ねます（`--no-test` で尋ねません）。

### `pushme doctor`

依存コマンド、設定ファイル（有無・パーミッション・未知のキー）、トピック名の形式、ntfy サーバーへの疎通を確認します。疎通確認は `GET /v1/health` で行うので、通知は送りません。問題があれば終了コード 1 で終わります。

## Android 側の準備

1. ntfy アプリを入れる
2. アプリの「+」から購読を追加し、「トピック名」に自分のトピック名を貼り付ける
3. 「別のサーバーを使う」はオフのまま（ntfy.sh のまま）「購読」を押す
4. `pushme テスト` を実行して届くことを確かめる

## 使い方

```sh
pushme [send] [オプション] [メッセージ...]
```

サブコマンドを省略すると `send` として扱います。`run` については後述の「コマンドの終了を通知する（run）」を参照してください。

```sh
# 引数を空白でつないで本文にする
pushme バックアップが完了しました

# タイトル・優先度・タグを付ける
pushme -t デプロイ -p high -T rocket production に反映しました

# 標準入力を本文にする
make test 2>&1 | tail -n 20 | pushme -t テスト結果

# 送らずに、送る内容だけ確かめる
pushme --dry-run -t タイトル 本文
```

| オプション | 説明 |
|---|---|
| `-t, --title TEXT` | タイトル |
| `-p, --priority VALUE` | 優先度。`1`〜`5` または `min` / `low` / `default` / `high` / `urgent` |
| `-T, --tags a,b` | タグ（カンマ区切り。繰り返し指定できる） |
| `-c, --click URL` | 通知をタップしたときに開く URL |
| `-a, --attach FILE` | ファイルを添付する |
| `--filename NAME` | 添付ファイルの表示名（既定はファイル名） |
| `--attach-url URL` | 外部の URL を添付する |
| `--markdown` | 本文を Markdown として表示する |
| `--no-host` | ホスト名タグを付けない |
| `-q, --quiet` | 成功時に何も表示しない |
| `--dry-run` | 送信せず、送る内容を表示する（トピック名とトークンは伏せ字） |
| `--` | これ以降の引数をすべてメッセージとして扱う |

- オプションはメッセージより前に書きます。最初のメッセージの語より後ろは、`-` で始まっていても本文になります
- メッセージの引数がなく、標準入力が端末でなければ標準入力を読みます。`-` だけを指定したときも標準入力を読みます
- `pushme help` のようにサブコマンド名と同じ言葉を送りたいときは `pushme send help` か `pushme -- help` とします
- 本文が 4,000 バイトを超えると、文字の途中で切らないように切り詰めて末尾に `…` を付けます（ntfy は 4,096 バイトを超える本文を添付ファイル扱いにするため）
- タグの末尾には、送信したマシンのホスト名（`hostname -s`）が自動で付きます
- `warning`、`rocket`、`white_check_mark` のように ntfy の絵文字ショートコードと一致するタグは、絵文字としてタイトルの前に表示されます
- タイトルやタグに日本語・絵文字を使えます（HTTP ヘッダは RFC 2047 の形式でエンコードして送ります）
- ntfy の上限に合わせて、タイトルは 1,000 バイトに切り詰めます。タグは合計 512 バイトを超えると、指定したタグを後ろから順に外し（ホスト名タグは残す）、警告を出します

### ファイルを添付する

```sh
pushme -a build.log -t ビルド失敗 ログを添付します
pushme --attach-url https://example.com/report.pdf レポートができました
```

- `-a` で指定したファイルは PUT で送ります。本文はファイルと一緒に `X-Message` ヘッダで送るので、本文を省略してファイルだけ送ることもできます
- ファイルが無い、または読めないときは終了コード 2 で終わります
- ファイルが `PUSHME_NTFY_ATTACH_MAX`（既定 2 MiB。ntfy.sh 無料枠の上限）より大きいときは、添付せずに本文だけ送り、警告を出します
- ntfy.sh は添付ファイルを 3 時間で消します
- `-a` と `--attach-url` は同時に指定できません

### 終了コードと失敗時の動作

| 終了コード | 意味 |
|---|---|
| 0 | 送信できた |
| 1 | 送信に失敗した（ネットワーク・HTTP エラー） |
| 2 | 使い方の誤り、設定の不足 |

`run` の終了コードは、実行したコマンドの終了コードです（`run` 自体のオプションの誤りは 2）。

- 失敗したときは理由を標準エラー出力に 1 行で出し、`~/.local/state/pushme/error.log` に日時付きで追記します
- 待ち時間の上限は接続 3 秒、全体 `PUSHME_TIMEOUT` 秒（既定 10 秒）です。接続を拒否されたときだけ 1 回再試行します。レート制限（HTTP 429）では再試行しません
- 通知の失敗でスクリプト全体を止めたくない場合は `pushme -q 完了 || true` のように書きます

### cron で使う

cron は、ジョブが何か出力するとメールを送ります。成功時の「送信しました」でメールが届かないよう、`-q` を付けてください。例は [examples/crontab.example](examples/crontab.example) にあります。

```cron
0 3 * * * $HOME/.local/bin/pushme run -q --on-fail-only --tail 20 -- /usr/local/bin/backup.sh >/dev/null 2>&1
```

- cron の `PATH` は短いので、pushme はフルパスで書きます
- 失敗の理由は `~/.local/state/pushme/error.log` に残ります

## コマンドの終了を通知する（run）

```sh
pushme run [オプション] [--on-fail-only] [--tail N] -- コマンド [引数...]
```

`--` の後のコマンドを実行し、終わったら通知します。

```sh
# 成功・失敗のどちらでも通知する
pushme run -- make test

# 失敗したときだけ、出力の末尾 20 行を付けて通知する
pushme run --on-fail-only --tail 20 -- ./deploy.sh production

# コマンドが書き出したログを添付する
pushme run -a build.log -- sh -c 'make > build.log 2>&1'
```

- **pushme の終了コードは、コマンドの終了コードそのままです。** 通知に失敗しても、設定が足りなくても変わりません（そのときは理由を標準エラー出力とエラーログに出します）。コマンドが見つからないときは 127 です
- コマンドの標準入力・標準出力・標準エラー出力はそのまま使えます。pushme 自身のメッセージは標準エラー出力に出します
- 既定の通知内容は次のとおりです。`-t` / `-p` で変えられ、`-T` のタグは既定のタグに追加されます

  | | 成功（終了コード 0） | 失敗 |
  |---|---|---|
  | タイトル | `make 成功` | `make 失敗 (exit 2)` |
  | 優先度 | 4（high） | 4（high） |
  | タグ | `white_check_mark`（✅）とホスト名 | `x`（❌）とホスト名 |
  | 本文 | コマンドライン、終了コード、所要時間（`1h2m3s` の形式） | 同左 |

- `--on-fail-only`: 終了コードが 0 のときは通知しません
- `--tail N`: 出力の末尾 N 行を本文に含めます。このとき標準エラー出力は標準出力に合流します。本文が 4,000 バイトを超える場合は、出力の先頭側を削ります
- シグナルで終了した場合（終了コードが 128 より大きい）も失敗として通知します。Ctrl-C を押すとコマンドが止まり、失敗の通知を送ってから、終了コード 130 で終わります
- pushme のプロセスだけに `SIGTERM` を送った場合は、コマンドが終わるのを待ってから通知します。bash の制約で、コマンドには転送されません。止めたいときは、コマンドを含むプロセスグループ全体に送ってください

## Claude Code から通知する

Claude Code のプラグインとして入れると、次のときに通知が届きます。

| タイミング | タイトル | 本文 |
|---|---|---|
| 返答が終わったとき（`PUSHME_CLAUDE_MIN_SECONDS` 秒以上かかったときだけ） | `<プロジェクト名> 完了` ✅ | 所要時間、セッション ID の先頭 8 文字、返答の先頭 300 文字 |
| 操作の承認や入力を待っているとき | `<プロジェクト名> 承認待ち` ❓ | Claude Code の通知文 |
| API エラーで止まったとき | `<プロジェクト名> エラー` ❌ | エラーの種類と詳細 |

- 優先度はどれも 4（high）です。タグにはプロジェクト名とホスト名が付きます
- プロジェクト名はディレクトリ名だけで、フルパスは送りません
- サブエージェントの終了では通知しません

### インストール

前提として、`pushme init` で設定ファイルを作ってあることと、jq が入っていることが必要です（どちらも `pushme doctor` で確認できます）。

```sh
claude plugin install pushme --marketplace uskey512/pushme
```

Claude Code のセッションの中からは次のように入れます。

```
/plugin install pushme --marketplace uskey512/pushme
```

プラグインは同梱の `bin/pushme` を使うので、`make install` していなくても動きます。設定は `~/.config/pushme/config` を共有します。返答を通知に載せたくない、短い作業でも通知したい、といった調整は `PUSHME_CLAUDE_INCLUDE_MESSAGE` と `PUSHME_CLAUDE_MIN_SECONDS`（「設定」の表を参照）で行います。

### 更新

サードパーティのマーケットプレイスは、既定では自動で更新されません。次のコマンドで更新します。

```sh
claude plugin update pushme@pushme
```

### プラグインを使わない場合

[examples/claude-settings.snippet.json](examples/claude-settings.snippet.json) の `hooks` の中身を `~/.claude/settings.json` の `"hooks"` に追記し、`/path/to/pushme` を実際の場所に書き換えます。プラグインと両方を設定すると、同じ通知が 2 回届きます。

### 動作確認

`--dry-run` を付けると、送らずに内容を標準エラー出力に表示します。

```sh
pushme claude-hook --dry-run < test/fixtures/claude/stop-failure.json
```

`pushme claude-hook` は Claude Code を止めないよう、何があっても終了コード 0 で終わり、標準出力には何も出しません。うまく届かないときは `~/.local/state/pushme/error.log` を確認してください。

## 設定

設定は次の順に読み込み、後から読んだものが優先されます。

1. 設定ファイル `~/.config/pushme/config`（`$XDG_CONFIG_HOME/pushme/config`。`PUSHME_CONFIG` で別のファイルを指定できます）
2. 環境変数 `PUSHME_*`
3. コマンドラインオプション（例: `--no-host` は `PUSHME_HOSTNAME` より優先）

設定ファイルは `KEY=VALUE` 形式です。`#` で始まる行と空行は無視し、値の前後の空白と、値全体を囲む `"` / `'` は取り除きます。シェルスクリプトとしては実行しないので、`$(...)` などを書いても文字列のまま扱います。どの段階でも、空の値は未設定と同じ扱いです。

```sh
PUSHME_NTFY_TOPIC=ntfy-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

| キー | 既定値 | 説明 |
|---|---|---|
| `PUSHME_BACKEND` | `ntfy` | 送信先 |
| `PUSHME_NTFY_URL` | `https://ntfy.sh` | ntfy サーバーの URL（末尾の `/` は取り除く） |
| `PUSHME_NTFY_TOPIC` | なし（必須） | トピック名。英数字・`-`・`_` の 1〜64 文字 |
| `PUSHME_NTFY_TOKEN` | なし | アクセストークン。設定すると `Authorization: Bearer` ヘッダを付ける（自前の ntfy サーバー向け） |
| `PUSHME_HOSTNAME` | `hostname -s` の結果 | ホスト名タグ |
| `PUSHME_TIMEOUT` | `10` | curl の `--max-time`（秒） |
| `PUSHME_NTFY_ATTACH_MAX` | `2097152` | 添付できるファイルの上限（バイト） |
| `PUSHME_CLAUDE_MIN_SECONDS` | `30` | Claude Code の返答がこの秒数以上かかったときだけ「完了」を通知する |
| `PUSHME_CLAUDE_INCLUDE_MESSAGE` | `1` | `0` にすると「完了」の通知に返答の先頭を載せない |
| `PUSHME_CURL` | `curl` | 使う curl コマンド。**環境変数でだけ**指定できる（設定ファイルに書いても無視する） |

設定ファイルは `0600`、それを置くディレクトリは `0700` にしてください。これより緩いと、送信時に警告を出します（送信は続けます）。設定ファイルを置かない環境では、環境変数 `PUSHME_NTFY_TOPIC` だけでも動きます。

## セキュリティ上の注意

- **トピック名はパスワードと同じです。** 知っている人は誰でもあなたの端末に通知を送れますし、購読すれば通知の内容を読めます。リポジトリ、スクリプト、チャットに書かないでください。漏れたときは `pushme init --force` で作り直し、アプリの購読も新しいトピック名に切り替えてください
- **秘密情報を通知に入れないでください。** ntfy.sh にはメッセージが平文で 12 時間残ります。パスワード、トークン、個人情報などは送らないでください
- Claude Code の「完了」の通知には、返答の先頭 300 文字が入ります。これも ntfy.sh に平文で 12 時間残るので、返答に機密が含まれうる場合は `PUSHME_CLAUDE_INCLUDE_MESSAGE=0` にしてください
- **無料枠は 1 日 250 通です。** ループの中から大量に送らないでください。制限を超え続けると、IP アドレスが一時的に止められることがあります
- pushme は、エラーメッセージ・ログ・`--dry-run` の出力でトピック名とトークンを伏せ字にします。curl にはコマンドライン引数ではなく標準入力で渡すので、`ps` の表示にも出ません

## 開発

```sh
make test   # bats-core でテストを実行する（実際の ntfy.sh には送らない）
make lint   # shellcheck と shfmt
```

## ライセンス

[MIT](LICENSE)
