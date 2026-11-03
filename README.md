# pushme

シェルや cron から、自分のスマートフォンやブラウザにプッシュ通知を送るコマンドです。

```sh
pushme ビルドが終わりました
pushme run -- make test      # 終わったら成否・所要時間を通知
```

通知の配信には [ntfy](https://ntfy.sh/) の公開サーバー ntfy.sh（無料枠）を使います。アカウントは要りません。推測されにくい「トピック名」がパスワードの代わりになります。[Pushover](#pushover-で受け取る) で受け取ることもできます。

## 必要なもの

- bash 3.2 以降（macOS 標準の `/bin/bash` で動きます）
- curl
- jq（Claude Code・Codex から通知する場合だけ）
- 受け取る側の ntfy アプリ（Android は Google Play または F-Droid、iOS は App Store）か、ブラウザ（[ntfy.sh/app](https://ntfy.sh/app)）

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
- **初めて使う**: 空のまま Enter を押すと、新しいトピック名（英数字 64 文字）を生成します。表示されるのはこの 1 回だけなので、パスワード管理ツールに保存してください

トピック名をコマンドライン引数で渡す方法はありません（シェルの履歴に残るため）。設定ファイルが既にあるときは何もしません。作り直すには `pushme init --force` を使います。

最後にテスト通知を送るか尋ねます（`--no-test` を付けたときと、トピック名を標準入力から渡したときは尋ねません）。

### `pushme doctor`

依存コマンド、設定ファイル（有無・パーミッション・未知のキー）、トピック名の形式、ntfy サーバーへの疎通を確認します。疎通確認は `GET /v1/health` で行うので、通知は送りません。問題があれば終了コード 1 で終わります。

## 受け取る側の準備

1. ntfy アプリ（Android / iOS）を入れる。ブラウザで受け取る場合は [ntfy.sh/app](https://ntfy.sh/app) を開く
2. 購読を追加し、「トピック名」に自分のトピック名を貼り付ける
3. 「別のサーバーを使う」はオフのまま（ntfy.sh のまま）「購読」を押す
4. `pushme テスト` を実行して届くことを確かめる

- ブラウザでは、ntfy のタブを開いているあいだ通知が届きます。タブを閉じても受け取りたいときは、Web アプリの設定でバックグラウンド通知をオンにします（ブラウザによっては、ブラウザ自体は起動しておく必要があります）
- `PUSHME_NTFY_URL` で自前の ntfy サーバーを使い iOS で受け取る場合は、サーバーに `upstream-base-url: "https://ntfy.sh"` の設定が必要です。無いと届くまで数時間かかることがあります

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
| `--markdown` | 本文を Markdown として表示する（ntfy の iOS アプリは非対応） |
| `--no-host` | ホスト名タグを付けない |
| `-q, --quiet` | 成功時に何も表示しない |
| `--ignore-dnd` | おやすみ時間（`PUSHME_DND`）でも送る |
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

## おやすみ時間

決めた時間帯には通知を送らない、音を鳴らさずに送る、または時間帯が明けてから届ける、のどれかにできます。`send`・`run`・Claude Code・Codex・GitHub Actions のどこから送る場合にも、Pushover で受け取る場合にも効きます。

```sh
# 設定ファイルに書く
PUSHME_DND=23:00-07:00,12:00-13:00
PUSHME_DND_MODE=quiet
```

- `PUSHME_DND` には `HH:MM-HH:MM` をカンマ区切りで書きます。終わりが始まりより前なら日をまたぎます。始まりの時刻は含み、終わりの時刻は含みません（`23:00-07:00` なら 23:00 から 6:59 まで）
- `PUSHME_DND_MODE=skip`（既定）は送りません。`quiet` は優先度を 1（音もバイブも鳴らない）に下げて送ります。`defer` は、おやすみ時間が終わる時刻に届くよう配信を予約します（[おやすみ時間が明けてから届ける](#おやすみ時間が明けてから届ける)）
- **優先度 5（`-p urgent`）の通知は、おやすみ時間でも送ります。** 緊急の通知を取りこぼさないためです
- その場かぎりで無視したいときは、`send` や `run` に `--ignore-dnd` を付けます
- 時刻はマシンのローカル時刻で判定します。別のタイムゾーンで判定したいときは `PUSHME_DND_TZ`（例 `Asia/Tokyo`）を指定します
- 送らなかったときも終了コードは 0 です（`run` はコマンドの終了コード）。理由は標準エラー出力に出します（`-q` なら出しません）。今がおやすみ時間かどうかは `pushme doctor` で、何が起きるかは `--dry-run` で確かめられます
- スマートフォン側のおやすみモード（Android の「サイレント モード」、iOS の「集中モード」など）とは別の仕組みです。`skip` なら pushme の側で送らないので、ntfy.sh の 1 日 250 通の枠も使いません

GitHub Actions のランナーの時刻は UTC なので、`PUSHME_DND_TZ` が必要です。ステップの `env:` に書きます。

```yaml
      - uses: uskey512/pushme@main
        env:
          PUSHME_DND: "23:00-07:00"
          PUSHME_DND_TZ: Asia/Tokyo
        with:
          topic: ${{ secrets.NTFY_TOPIC }}
          message: nightly build finished
```

### おやすみ時間が明けてから届ける

```sh
PUSHME_DND=23:00-07:00
PUSHME_DND_MODE=defer
```

夜のうちに終わったジョブの通知が、朝 7:00 にふだんの優先度で届きます。ntfy の予約配信（`X-Delay`）を使います。

- 通知はその場で ntfy のサーバーに送り、届くのはおやすみ時間が終わる時刻です。ntfy.sh の 1 日 250 通の枠は、送った日の分を使います
- 予約した通知は取り消せません。たとえば Claude Code の承認待ちに夜のうちに答えても、朝に届きます
- `22:00-00:00,00:00-07:00` のように続けて書いたおやすみ時間は、最後に終わる時刻（この例では 7:00）まで遅らせます。一日中がおやすみ時間になる設定では、`skip` と同じく送りません
- 届くまでに 3 時間より長くかかる通知には、ファイルを添付しません。ntfy.sh は添付ファイルを 3 時間で消し、それより後に届く通知への添付を受け付けないためです。添付しなかったことは本文に書き足します（`--attach-url` の URL はそのまま送ります）
- Pushover には予約配信がないため、`quiet` と同じく優先度 1 で送ります。`pushme doctor` でも警告します
- 夏時間の切り替えをまたぐと、届く時刻がその差だけずれます

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
| 操作の承認や入力を待っているとき | `<プロジェクト名> 承認待ち` ❓ | Claude Code の通知文。コマンドの実行の承認なら、そのコマンドの先頭 300 文字も |
| API エラーで止まったとき | `<プロジェクト名> エラー` ❌ | エラーの種類と詳細 |

- 優先度はどれも 4（high）です。タグにはプロジェクト名とホスト名が付きます
- プロジェクト名はディレクトリ名だけで、フルパスは送りません
- サブエージェントの終了では通知しません
- 「完了」と「承認待ち」は、しばらく応答がないときだけ送るようにもできます（[席を外しているときだけ通知する](#席を外しているときだけ通知する)）

### インストール

前提として、`pushme init` で設定ファイルを作ってあることと、jq が入っていることが必要です（どちらも `pushme doctor` で確認できます）。

```sh
claude plugin install pushme --marketplace uskey512/pushme
```

`--marketplace` が使えない古い Claude Code では、`claude plugin marketplace add uskey512/pushme` のあと `claude plugin install pushme@pushme` とします。

Claude Code のセッションの中からは次のように入れます（`/plugin` の画面が開くので、そこでインストールを確定します）。

```
/plugin install pushme --marketplace uskey512/pushme
```

プラグインは同梱の `bin/pushme` を使うので、`make install` していなくても動きます。設定は `~/.config/pushme/config` を共有します。返答やコマンドを通知に載せたくない、短い作業でも通知したい、といった調整は `PUSHME_CLAUDE_INCLUDE_MESSAGE`・`PUSHME_CLAUDE_INCLUDE_COMMAND`・`PUSHME_CLAUDE_MIN_SECONDS`（「設定」の表を参照）で行います。

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

## Codex から通知する

Codex CLI の hooks からも、次のときに通知が届きます。

| タイミング | タイトル | 本文 |
|---|---|---|
| 返答が終わったとき（`PUSHME_CODEX_MIN_SECONDS` 秒以上かかったときだけ） | `<プロジェクト名> 完了` ✅ | 所要時間、セッション ID の先頭 8 文字、返答の先頭 300 文字 |
| コマンドの実行などの承認を求められたとき | `<プロジェクト名> 承認待ち` ❓ | ツール名と、実行しようとしているコマンドの先頭 300 文字 |

- 優先度はどれも 4（high）です。タグにはプロジェクト名とホスト名が付きます
- プロジェクト名は作業ディレクトリの名前だけで、フルパスは送りません
- Ctrl-C で中断したターンと、サブエージェントの終了では通知しません

Claude Code 版との違いは次のとおりです。

- エラーの通知はありません。Codex には、API エラーで止まったときのイベントがないためです
- 承認待ちは、承認を求められた瞬間に届きます。Claude Code のような猶予がないので、画面の前にいても鳴ります。`PUSHME_CODEX_DELAY_SECONDS` で遅らせるか（[席を外しているときだけ通知する](#席を外しているときだけ通知する)）、不要なら `PUSHME_CODEX_NOTIFY_PERMISSION=0` にしてください
- サブエージェントの承認要求も通知します（承認するのは利用者のため）

### 設定方法

前提として、`make install` で `~/.local/bin/pushme` に入れてあること、`pushme init` で設定ファイルを作ってあること、jq が入っていることが必要です。

1. [examples/codex-hooks.snippet.json](examples/codex-hooks.snippet.json) の各イベントの要素を、`~/.codex/hooks.json` の同じイベントの配列に追記します（ファイルが無ければ、そのまま置けます）。hooks を `~/.codex/config.toml` に書いている場合は、代わりに [examples/codex-config.snippet.toml](examples/codex-config.snippet.toml) を追記します。同じ場所に `hooks.json` と `config.toml` の `[hooks]` が両方あると Codex が警告を出すので、どちらか一方に書いてください
2. Codex で `/hooks` を開き、pushme の hook を信頼（trust）します。信頼するまで、hook は実行されません
3. 送られる内容は `--dry-run` で確かめられます（標準エラー出力に表示し、送信はしません）

   ```sh
   pushme codex-hook --dry-run < test/fixtures/codex/permission-request.json
   ```

Codex の `config.toml` の `notify`（古い仕組み。ターンの完了しか通知できず、コマンドを 1 つしか登録できない）は使いません。

## 席を外しているときだけ通知する

`PUSHME_CLAUDE_DELAY_SECONDS`（Codex は `PUSHME_CODEX_DELAY_SECONDS`）を設定すると、「完了」と「承認待ち」の通知をその秒数だけ遅らせ、そのあいだに応答があれば送りません。画面の前にいるあいだは鳴らさず、離れているときだけ知らせたい場合に使います。既定は `0`（すぐ送る）です。

```sh
# 5 分たっても応答がなければ通知する
PUSHME_CLAUDE_DELAY_SECONDS=300
PUSHME_CODEX_DELAY_SECONDS=300
```

遅らせている通知は、次のときに取り消します。

| 通知 | 取り消すとき |
|---|---|
| 完了 | 次のプロンプトを送ったとき、セッションを終えたとき |
| 承認待ち | 承認を求めたエージェントのツールの実行が終わったとき、メインの会話のターンが終わったとき、次のプロンプトを送ったとき、セッションを終えたとき。Codex では Esc や Ctrl-C で中断したときも |

- **承認したことは、ツールの実行が終わるまで分かりません。** 承認したコマンドが遅延の秒数より長く動くと、承認済みでも「承認待ち」が届きます
- **Claude Code で承認を Esc や「No」（コメントなし）で断ると、それを知らせるイベントがありません。** そのまま離れると、遅延のあとに「承認待ち」が届きます。次のプロンプトを送れば取り消せます
- Claude Code の承認待ちは、承認の画面が出て約 6 秒たってから数え始めます。Codex は承認を求められた時点からです
- 遅らせているあいだに同じ種類の通知がまた来たら、新しいほうだけを送ります
- サブエージェントの承認待ちは、ほかのエージェントがツールを使っても取り消しません
- Claude Code のエラーの通知は遅らせません
- おやすみ時間は、実際に送る時点の時刻で判定します
- `--dry-run` では、遅らせずにすぐ表示します（何秒後に送るかも表示します）

取り消しのために、Claude Code では `PermissionRequest`・`PostToolUse`・`PostToolUseFailure`・`SessionEnd`、Codex では `PostToolUse`・`SessionEnd` の hook も使います。プラグインは[更新](#更新)すれば入ります。プラグインを使わない場合と Codex では、examples の同じイベントの hook を追記してください（Codex は `/hooks` で信頼し直します）。`PostToolUse` はツールを使うたびに pushme を起動しますが、遅らせている通知がなければ、イベント名を読むだけで終わります。

## GitHub Actions から通知する

このリポジトリは composite action としても使えます。ランナーへのインストールや checkout は要りません（ubuntu と macOS のランナーで動きます）。

### Secrets の登録

トピック名はリポジトリの Secrets に入れます。次のコマンドは値を対話で尋ねるので、シェルの履歴に残りません。

```sh
gh secret set NTFY_TOPIC --repo owner/repo
```

### 使い方

成功と失敗で、優先度とタグを変える例です。

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: make test

      - name: 成功を通知
        if: success()
        uses: uskey512/pushme@main
        with:
          topic: ${{ secrets.NTFY_TOPIC }}
          title: ${{ github.workflow }} 成功
          message: ${{ github.repository }} の ${{ github.ref_name }} でテストが通りました
          priority: default
          tags: white_check_mark

      - name: 失敗を通知
        if: failure()
        uses: uskey512/pushme@main
        with:
          topic: ${{ secrets.NTFY_TOPIC }}
          title: ${{ github.workflow }} 失敗
          message: ${{ github.repository }} の ${{ github.ref_name }} でテストが失敗しました
          priority: urgent
          tags: x
```

- composite action は secrets を直接読めないので、`topic: ${{ secrets.NTFY_TOPIC }}` のように渡します。topic と token はログでマスクされます
- `@main` の代わりにコミット SHA を書くと、意図しない変更を取り込まずに済みます
- 通知をタップすると、そのワークフロー実行のページが開きます。タグの末尾にはリポジトリ名（`owner/repo`）が付きます
- 入力の値はシェルに展開せず環境変数で渡すので、`with:` にブランチ名や PR のタイトルのような外から来る値を書いても、コマンドとして実行されることはありません
- 既定では、通知に失敗してもジョブは失敗させず、警告を出すだけです。失敗させたいときは `fail-on-error: true` を指定します

| 入力 | 既定値 | 説明 |
|---|---|---|
| `message` | （必須） | 本文 |
| `topic` | | トピック名。空のときはジョブの環境変数 `PUSHME_NTFY_TOPIC` を使う |
| `title` | | タイトル |
| `priority` | `high` | 優先度。`1`〜`5` または `min` / `low` / `default` / `high` / `urgent` |
| `tags` | | タグ（カンマ区切り） |
| `click` | この実行のページ | 通知をタップしたときに開く URL |
| `server` | `https://ntfy.sh` | ntfy サーバーの URL |
| `token` | | アクセストークン（自前の ntfy サーバー向け） |
| `markdown` | `false` | 本文を Markdown として表示する |
| `attach` | | 添付するファイルのパス |
| `dry-run` | `false` | 送信せず、送る内容をログに出す |
| `fail-on-error` | `false` | 通知に失敗したらステップを失敗させる |
| `backend` | `ntfy` | 送信先。`ntfy` または `pushover` |
| `pushover-token` | | Pushover の API Token |
| `pushover-user` | | Pushover の User Key |

| 出力 | 説明 |
|---|---|
| `status` | `sent` / `deferred`（おやすみ時間が明けてから届くよう予約した）/ `skipped`（おやすみ時間で送らなかった）/ `dry-run` / `failed` のどれか |
| `dry-run-output` | `dry-run` のときに表示した送信内容（トピック名とトークンは伏せ字） |

## Pushover で受け取る

ntfy の代わりに [Pushover](https://pushover.net/)（iOS・Android・デスクトップのブラウザ向けの有料アプリ。30 日間は無料で試せます）でも受け取れます。

1. Pushover のアカウントを作り、ダッシュボードに表示される User Key を控える
2. https://pushover.net/apps/build でアプリケーションを作り、API Token を控える
3. 設定ファイルに次の行を書く（`pushme init` は ntfy 用なので、Pushover だけを使う場合は `~/.config/pushme/config` を手で作り、`chmod 600` にする）

   ```sh
   PUSHME_BACKEND=pushover
   PUSHME_PUSHOVER_TOKEN=<API Token>
   PUSHME_PUSHOVER_USER=<User Key>
   ```

4. `pushme doctor` でキーを確認する（Pushover の `users/validate.json` を使うので、通知は送りません）

ntfy との違いは次のとおりです。

- 優先度は 1→-2、2→-1、3→0、4 と 5→1 に置き換えます。緊急（2）は確認するまで鳴り続けるため、自動では使いません
- Pushover にはタグがありません。`white_check_mark` ✅、`x` ❌、`question` ❓、`warning` ⚠️ などの主な絵文字のタグは、タイトルの先頭に絵文字として付けます。それ以外のタグは送らず、タイトルの末尾に ` @ホスト名` を付けます
- タイトルは 250 バイト、本文は 1,024 バイトに切り詰めます
- `--markdown` と `--filename` は使いません。`--attach` は画像にだけ対応しています（Pushover の仕様）。5 MiB より大きいと本文だけ送り、警告を出します。`--attach-url` は本文の末尾に URL を足します
- トークンとユーザーキーは、トピック名と同じく伏せ字にし、`ps` にも出しません

GitHub Actions では `backend: pushover` と、`pushover-token: ${{ secrets.PUSHOVER_TOKEN }}`・`pushover-user: ${{ secrets.PUSHOVER_USER }}` を指定します。

## 設定

設定は次の順に読み込み、後から読んだものが優先されます。

1. 設定ファイル `~/.config/pushme/config`（`$XDG_CONFIG_HOME/pushme/config`。`PUSHME_CONFIG` で別のファイルを指定できます）
2. 環境変数 `PUSHME_*`
3. コマンドラインオプション（例: `--no-host` は `PUSHME_HOSTNAME` より優先）

設定ファイルは `KEY=VALUE` 形式です。`#` で始まる行と空行は無視し、値の前後の空白と、値全体を囲む `"` / `'` は取り除きます。シェルスクリプトとしては実行しないので、`$(...)` などを書いても文字列のまま扱います。どの段階でも、空の値は未設定と同じ扱いです。

```sh
PUSHME_NTFY_TOPIC=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

| キー | 既定値 | 説明 |
|---|---|---|
| `PUSHME_BACKEND` | `ntfy` | 送信先。`ntfy` または `pushover` |
| `PUSHME_NTFY_URL` | `https://ntfy.sh` | ntfy サーバーの URL（末尾の `/` は取り除く） |
| `PUSHME_NTFY_TOPIC` | なし（必須） | トピック名。英数字・`-`・`_` の 1〜64 文字 |
| `PUSHME_NTFY_TOKEN` | なし | アクセストークン。設定すると `Authorization: Bearer` ヘッダを付ける（自前の ntfy サーバー向け） |
| `PUSHME_HOSTNAME` | `hostname -s` の結果 | ホスト名タグ |
| `PUSHME_TIMEOUT` | `10` | curl の `--max-time`（秒） |
| `PUSHME_NTFY_ATTACH_MAX` | `2097152` | 添付できるファイルの上限（バイト） |
| `PUSHME_CLAUDE_MIN_SECONDS` | `30` | Claude Code の返答がこの秒数以上かかったときだけ「完了」を通知する |
| `PUSHME_CLAUDE_INCLUDE_MESSAGE` | `1` | `0` にすると「完了」の通知に返答の先頭を載せない |
| `PUSHME_CLAUDE_INCLUDE_COMMAND` | `1` | `0` にすると「承認待ち」の通知に実行しようとしているコマンドを載せない |
| `PUSHME_CLAUDE_DELAY_SECONDS` | `0` | Claude Code の「完了」と「承認待ち」をこの秒数だけ遅らせ、そのあいだに応答があれば送らない（「席を外しているときだけ通知する」を参照） |
| `PUSHME_CODEX_MIN_SECONDS` | `30` | Codex の返答がこの秒数以上かかったときだけ「完了」を通知する |
| `PUSHME_CODEX_INCLUDE_MESSAGE` | `1` | `0` にすると Codex の「完了」の通知に返答の先頭を載せない |
| `PUSHME_CODEX_NOTIFY_PERMISSION` | `1` | `0` にすると Codex の承認待ちを通知しない |
| `PUSHME_CODEX_DELAY_SECONDS` | `0` | Codex の「完了」と「承認待ち」をこの秒数だけ遅らせ、そのあいだに応答があれば送らない |
| `PUSHME_PUSHOVER_TOKEN` | なし | Pushover の API Token（`PUSHME_BACKEND=pushover` のとき必須） |
| `PUSHME_PUSHOVER_USER` | なし | Pushover の User Key（`PUSHME_BACKEND=pushover` のとき必須） |
| `PUSHME_PUSHOVER_DEVICE` | なし | 送る端末の名前（カンマ区切りで複数）。なければすべての端末 |
| `PUSHME_DND` | なし | おやすみ時間。`HH:MM-HH:MM` をカンマ区切り（「おやすみ時間」の節を参照） |
| `PUSHME_DND_MODE` | `skip` | おやすみ時間の動作。`skip`（送らない）、`quiet`（優先度 1 で送る）、`defer`（明けてから届くよう予約する） |
| `PUSHME_DND_TZ` | マシンのローカル時刻 | おやすみ時間の判定に使うタイムゾーン（例 `Asia/Tokyo`） |
| `PUSHME_CURL` | `curl` | 使う curl コマンド。**環境変数でだけ**指定できる（設定ファイルに書いても無視する） |

設定ファイルは `0600`、それを置くディレクトリは `0700` にしてください。これより緩いと、送信時に警告を出します（送信は続けます）。設定ファイルを置かない環境では、環境変数 `PUSHME_NTFY_TOPIC` だけでも動きます。

## セキュリティ上の注意

- **トピック名はパスワードと同じです。** 知っている人は誰でもあなたの端末に通知を送れますし、購読すれば通知の内容を読めます。リポジトリ、スクリプト、チャットに書かないでください。漏れたときは `pushme init --force` で作り直し、アプリの購読も新しいトピック名に切り替えてください
- **秘密情報を通知に入れないでください。** ntfy.sh にはメッセージが平文で 12 時間残ります。パスワード、トークン、個人情報などは送らないでください
- Claude Code と Codex の「完了」の通知には返答の先頭 300 文字が、「承認待ち」の通知には実行しようとしているコマンドが入ります。これらも ntfy.sh に平文で 12 時間残るので、機密が含まれうる場合は `PUSHME_CLAUDE_INCLUDE_MESSAGE=0`・`PUSHME_CLAUDE_INCLUDE_COMMAND=0`・`PUSHME_CODEX_INCLUDE_MESSAGE=0`・`PUSHME_CODEX_NOTIFY_PERMISSION=0` にしてください
- **無料枠は 1 日 250 通です。** ループの中から大量に送らないでください。制限を超え続けると、IP アドレスが一時的に止められることがあります
- pushme は、エラーメッセージ・ログ・`--dry-run` の出力でトピック名とトークンを伏せ字にします。curl にはコマンドライン引数ではなく標準入力で渡すので、`ps` の表示にも出ません

## 開発

```sh
make test   # bats-core でテストを実行する（実際の ntfy.sh には送らない。ファイルごとに並列、JOBS=1 で 1 つずつ）
make lint   # shellcheck と shfmt
```

## ライセンス

[MIT](LICENSE)
