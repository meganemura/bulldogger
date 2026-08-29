# bulldogger

このファイルは `README.md` の翻訳であり、内容が一致しない場合は `README.md` を正とします。

bulldogger は Ruby のテスト失敗を、コーディングエージェント向けの構造化された証拠として書き出します。
各 JSON ファイルには、例外、バックトレース、取得したフレームの値が含まれます。
失敗出力には、そのファイルの絶対パスが示されます。

開発と計測には Ruby 4.0.6 と debug 1.11.1 を使用しました。
bulldogger 0.2.0 では独立したインスタンスを追加し、ドッグフーディングをユニットテストスイートまで拡張しました。

## インストール

テストグループに両方の gem を追加します。

```ruby
gem "bulldogger", group: :test
gem "debug", group: :test
```

`debug` gem は `DEBUGGER__.capture_frames` を提供し、bulldogger は各フレームのローカル変数を取得できます。
Ruby は `debug` を bundled gem として配布しています。
Bundler はアプリケーションの Gemfile に `debug` が含まれる場合に限って、この gem を利用可能にします。

`debug` がない場合、bulldogger は例外が発生したフレームのローカル変数を記録します。
残りのフレームについては、ファイル、行、ラベルのデータを記録します。

デフォルトブランチからエージェントホストへ skill をインストールします。

```sh
gh skill install meganemura/bulldogger
```

バージョンをそろえる必要がある場合は、インストール済みの gem と一致するコピーを使います。

```sh
bulldogger skill path
```

最初のコマンドはエージェントホストに skill をインストールし、2 番目のコマンドは一致する gem 内のコピーを表示します。

CLI には次のサブコマンドがあります。

```text
bulldogger skill path
bulldogger version
bulldogger --version
```

フレームワーク用のエントリーポイントを 1 つ追加します。

Minitest では、次の行を `test_helper.rb` に追加します。

```ruby
require "bulldogger/minitest"
```

RSpec では、次の行を `spec_helper.rb` に追加します。

```ruby
require "bulldogger/rspec"
```

各エントリーポイントは取得を開始し、失敗した各テストを記録します。
テストスイートが終了すると、実行インデックスを完成させます。

## 独立したインスタンスの使用

`Bulldogger` モジュールは API を `Bulldogger.default` に委譲します。
`Bulldogger.start` や `Bulldogger.probe` などの既存の呼び出しは、このデフォルトインスタンスを使います。

2 つの取得ライフサイクルを同時に動かす必要がある場合は、別のインスタンスを作成します。

```ruby
observer = Bulldogger::Instance.new
observer.start
```

各インスタンスは、設定、取得の購読、実行、証拠の状態を所有します。
モジュールのファサードが提供する失敗、probe、record、SQLite 変換の各メソッドも利用できます。

インテグレーションには、デフォルトの代わりに指定したインスタンスを使えます。

```ruby
Bulldogger::Minitest.instance = observer
Bulldogger::RSpec.instance = observer
```

テストスイートが始まる前にインスタンスを指定します。
この分離により、テストのセットアップがデフォルトインスタンスを置き換えても、外側のオブザーバーは動作を続けられます。

## 3 つの方法

bulldogger は、実行時の証拠を収集する 3 つの方法を提供します。

- 失敗スナップショットがデフォルトです。例外が発生しない green テストではデータを取得しません。伝播した例外については、フレームとローカル変数から答えを得られます。アサーションではアプリケーションの呼び出しがすでに戻っているため、bulldogger は完全な記録のもとでテストを 1 回リプレイします。
- `probe` は、明示的な 1 回の実行中に指定したメソッドを監視します。
- `record` は、明示的な 1 回の実行中にすべての Ruby メソッド呼び出しをトレースします。

失敗したテストが証拠のパスをすでに示している場合は、失敗スナップショットを使います。
1 つのメソッドを調べる場合や、変更の前後で動作を比較する場合は `probe` を使います。
呼び出しシーケンス全体を追う必要がある場合は `record` を使います。

## 失敗出力

次のコマンドから、この出力を得ました。

```sh
bundle exec ruby -Ilib test/fixtures/minitest_red/red_test.rb
```

```text
  1) Error:
RedTest#test_deep_raise:
ArgumentError: expected 3 to equal the sum of [1, 2, 3]
    test/fixtures/minitest_red/app.rb:9:in 'Order.total'
    test/fixtures/minitest_red/red_test.rb:20:in 'RedTest#test_deep_raise'
bulldogger evidence: /home/you/project/tmp/bulldogger/run-20260829-100406-58231/001-RedTest-test_deep_raise.json (raising method is in these frames)
```

括弧内の案内がある行のパスを開きます。
このファイルには、1 件の失敗と取得した実行時の値が含まれます。
この伝播した例外の証拠ファイルには `replay_skipped_reason: "application_frame_available"` があり、`Order.total` フレームにアプリケーションのローカル変数が含まれるため、リプレイは実行されませんでした。

失敗に対してリプレイを実行すると、`bulldogger replay:` 行が表示されます。
括弧内の説明は、再現した失敗または成功したリプレイを示します。
規則、設定、副作用については、[失敗したテストのリプレイ](#失敗したテストのリプレイ)を参照してください。

各実行では次の配置を使います。

```text
tmp/bulldogger/
  latest -> run-20260829-100406-58231
  run-20260829-100406-58231/
    001-RedTest-test_deep_raise.json
    002-RedTest-test_assertion_failure.json
    trace-001.jsonl
    index.json
```

[`bulldogger` skill](skills/bulldogger/SKILL.md) は、エージェントがこれらのファイルを調べる方法を説明します。
[証拠スキーマ](docs/evidence-schema.md)は、すべてのフィールドと取得モードを定義します。

## 失敗したテストのリプレイ

アサーションが例外を発生させる時点では、テスト対象のコードはすでに戻っています。
この場合、失敗スナップショットにはテストフレームワークとテスト本体が含まれ、アプリケーションのフレームは含まれません。
フレーム数を増やしても役に立たず、誤った値を生成した呼び出しはすでにスタックから外れています。

bulldogger は完全な記録のもとで失敗したテスト 1 件を再実行し、その値に到達します。
例外の形は異なり、例外の伝播中はアプリケーションコードがスタックに残ります。
スナップショットにコードとローカル変数がすでに含まれるため、bulldogger はリプレイを省略します。

デフォルトの規則は、テストファイル外にあるアプリケーションフレームを数えます。
そのフレームが 0 件ならリプレイし、1 件以上なら `replay_skipped_reason: "application_frame_available"` を付けて省略します。
この理由があり `replay` キーがない場合、フレームから答えを得られます。

リプレイは子プロセスで動くため、親テストスイートの結果は変わりません。
green の実行ではリプレイを行わないため、green のときにコストがないという特性も保たれます。
追加コストはアサーション型の失敗後に限って発生し、デフォルトでは分離されたプロセスで 1 回だけ実行します。

証拠には、トレースの絶対パスを持つ `replay` キーが追加されます。
さらに `replay_reproduced` キーも追加されます。
子プロセスが失敗終了するとこのキーは `true` になり、成功すると `false` になります。
`false` は、その失敗が単独では再現しなかったことを示します。
通常は、実行順序や別のテストとの共有状態に依存するテストを示唆します。

失敗出力は、有用な実行時データを含むファイルを示します。

```text
bulldogger evidence: /abs/path/evidence.json
bulldogger replay: /abs/path/trace.jsonl (value was produced before the assertion raised)
```

成功したリプレイでは `(test passed alone; this trace shows the passing run)` を使います。
リプレイを実行できない場合、証拠の行は値の生成元がフレームにないことを示します。
リプレイが無効な場合、証拠の括弧内には `BULLDOGGER_REPLAY=1` も示されます。
取得に失敗した場合、スナップショットにフレームがないことを示します。

リプレイの設定は次のとおりです。

| 属性 | デフォルト | 効果 |
|---|---|---|
| `replay_on_failure` | `true` | テストファイル外のアプリケーションコードをフレームが含まない場合にリプレイします。`:always` はすべての失敗をリプレイします。`false` はリプレイしません。 |
| `max_replays` | `1` | 1 回の実行に対するリプレイ数を制限します。 |
| `replay_timeout` | `60` | bulldogger がリプレイの子プロセスを中止するまでの秒数です。中止したリプレイは `replay` キーも `replay_reproduced` キーも書きません。 |

デフォルトの規則は、リプレイするテストを絞ります。
リプレイしたテストは、ファイル書き込み、外部リクエスト、サンドボックスアカウントの変更などの各副作用を再度実行します。
1 つのプロセスでリプレイを無効にするには `BULLDOGGER_REPLAY=0` を設定します。
すべての失敗をリプレイするには `BULLDOGGER_REPLAY=always` を設定します。
アプリケーションで同じ方針を設定するには、`config.replay_on_failure` に `false` または `:always` を指定します。
`BULLDOGGER_MAX_REPLAYS` は上限を上書きします。
`BULLDOGGER_DISABLE=1` は、ほかのすべての取得とともにリプレイも無効にします。

[リプレイのリファレンス](skills/bulldogger/references/replay.md)は、エージェントがトレースを値の生成元まで絞り込む方法を説明します。
[トレーススキーマ](docs/trace-schema.md)は、リプレイトレースが持つイベントフィールドを定義します。

## probe によるメソッドの指定

対象名を指定し、関連するテストまたは処理を囲みます。

```ruby
before_path = Bulldogger.probe("Billing::Invoice#amount") do
  run_related_test
end
```

証拠は、引数と戻り値のクラス、`nil` 値、例外による終了、呼び出し元を要約します。
デフォルトでは最初の 10 サンプルをシリアライズし、すべての呼び出しを数えます。

変更の前後で probe を実行し、2 つのファイルを比較します。

```ruby
result = Bulldogger.probe_compare(before_path, after_path)
result.fetch("identical")
```

`identical` の値が `true` なら、比較した動作は同じです。
比較の対象は、呼び出し回数、クラス、`nil` の数、例外による終了、パラメーター、呼び出し元、正規化したサンプルです。

次の抜粋は、生成した probe ファイルから得ました。

```json
{
  "kind": "probe",
  "targets": ["ProseSample#amount"],
  "methods": {
    "ProseSample#amount": {
      "calls": 3,
      "raised_exits": 1,
      "returns": {
        "classes": {"Integer": 1, "NilClass": 1},
        "nil_count": 1,
        "samples": [{"value": "21"}, {"value": "nil"}]
      },
      "raised": {"ArgumentError": 1},
      "callers": {"-e:1:in 'block in <main>'": 3}
    }
  },
  "limits": {"max_samples": 10, "max_value_length": 200}
}
```

## 呼び出しシーケンスの記録

完全な呼び出しシーケンスが必要な場合は、対象を絞った 1 つの処理を囲みます。

```ruby
trace_path = Bulldogger.record do
  run_related_test
end
```

結果は JSONL ファイルであり、ヘッダーと call、return、raise の各イベントに対応するオブジェクトを含みます。
次の抜粋は、生成したトレースから得ました。

```jsonl
{"schema_version":1,"kind":"record","events":["call","return","raise"],"limits":{"max_value_length":200}}
{"event":"call","seq":1,"depth":1,"path":"-e","line":1,"method":"ProseTrace#outer","args":{"value":{"value":"3"}}}
{"event":"return","seq":4,"depth":1,"path":"-e","line":1,"method":"ProseTrace#outer","return":{"value":"6"}}
{"event":"raise","seq":7,"depth":2,"path":"-e","line":1,"method":"ProseTrace#inner","exception":{"class":"ArgumentError","message":"negative"}}
{"event":"return","seq":8,"depth":2,"path":"-e","line":1,"method":"ProseTrace#inner","raised":true}
```

[トレーススキーマ](docs/trace-schema.md)は、イベントフィールドと検証済みの `jq` クエリーを定義します。

JSONL が主要な記録形式です。
`sqlite3` gem が利用できる場合、`Bulldogger.trace_to_sqlite(trace_path, db_path)` は既存のトレースを変換します。
変換処理は soft require を使うため、bulldogger の実行時依存関係は 0 件のままです。

## コスト

`TracePoint(:raise)` は、アプリケーションコードが rescue する例外を含む、発生したすべての例外を監視します。
この計測には Ruby 4.0.6 を使用しました。
各条件を 3 回実行し、表には各中央値を示します。

| 条件 | bulldogger なし | bulldogger あり | 比率 |
|---|---:|---:|---:|
| 例外が発生しない 2,000,000 回の no-op 反復 | 0.0423s | 0.0424s | 1.00x |
| 10,000 回の raise と rescue | 0.0055s | 0.4468s | 81.14x |
| ファイル出力を伴う 200 件の失敗記録 | 0.0001s | 0.0277s | 413.58x |

この計測では、2 番目の条件で例外 1 件あたり 44.126 microseconds かかりました。

取得コストの内訳を次に示します。

| 段階 | 例外 1 件あたりの追加コスト |
|---|---:|
| `TracePoint(:raise)` を購読 | 0.136 microseconds |
| `DEBUGGER__.capture_frames` を呼び出し | 1.288 microseconds |
| シリアライズ、秘匿、リングへの挿入 | 23.220 microseconds |

この計測ではフレーム取得のコストは小さく、その後の処理が計測コストの大部分を占めます。

このテストでは、例外が発生しない green のテストスイートに計測可能なオーバーヘッドはありませんでした。
green のテストスイートでも例外を発生させて rescue する場合があり、その各例外には取得コストがかかります。

### 明示的な動詞のコスト

比例関係の計測ハーネスでは、両方の動詞に 1 つのアプリケーションフィクスチャを使いました。
`probe` では対象メソッドの呼び出し 1 回あたり 1461.5 ns を計測しました。
`record` ではトレース対象の呼び出し 1 回あたり 4249.5 ns を計測しました。

`probe` のコストは対象メソッドの呼び出し数に比例し、計測ハーネスではその数を M と呼びます。
`record` のコストはトレース対象の全呼び出し数に比例し、計測ハーネスではその数を N と呼びます。
M/N が 0.25 のとき、このフィクスチャでは `probe` が 8.70x、`record` が 104.93x でした。
これらの比率はこのアプリケーションフィクスチャに対する値であり、別のアプリケーションでは M/N の値が異なります。

record 専用の計測ハーネスでは、値の取得が 36.19x でした。
JSONL への書き込みを含む完全な処理は 54.72x でした。
同じ機械で繰り返し計測すると、値の取得は 34x から 37x、完全な処理は 48x から 55x の範囲に収まりました。
これらの数値は定数ではなく範囲として読んでください。

`probe` と `record` は、変更の前後に対象を絞って 1 回実行する明示的な動詞です。
テストスイート全体へ継続的に適用しないでください。

## bulldogger の無効化

1 つのテストプロセスで取得と出力を無効にするには、`BULLDOGGER_DISABLE=1` を設定します。
`BULLDOGGER_DISABLED=1` は同じ動作をする別名です。

どちらかのスイッチを使うと、起動処理は `TracePoint(:raise)` の購読前に戻ります。
証拠を書かず、実行ディレクトリを作らず、失敗に証拠の行を追加しません。
リプレイは、このスイッチが省略する証拠処理から始まるため、実行されません。
テストの終了コードと失敗数は変わりません。
受け入れテストは、Minitest と RSpec についてこの動作を確認しています。

rescue を多用する green のテストスイートでは、bulldogger を無効にした状態で 1.00x を計測しました。

## 環境変数

次の環境変数は、子テストプロセスを設定します。

| 変数 | 受け付ける値 | デフォルトと効果 |
|---|---|---|
| `BULLDOGGER_DISABLE` | `1` | デフォルトでは取得が有効です。`1` は取得と出力を無効にします。 |
| `BULLDOGGER_DISABLED` | `1` | `BULLDOGGER_DISABLE` の別名です。 |
| `BULLDOGGER_OUTPUT_DIR` | 空でないパス | デフォルトは作業ディレクトリからの相対パス `tmp/bulldogger` です。 |
| `BULLDOGGER_FRAME_SOURCE` | `capture_frames` または `degraded` | デフォルトでは自動選択します。 |
| `BULLDOGGER_REPLAY` | `0`、`1`、または `always` | デフォルトは `1` です。フレームから答えを得られない場合にリプレイします。`0` はリプレイを無効にします。`always` はすべての失敗をリプレイします。 |
| `BULLDOGGER_MAX_REPLAYS` | 整数 | 1 回の実行に対するリプレイ数 `max_replays` を上書きします。デフォルトは `1` です。 |

## シークレットと上限

取得した値にはシークレットが含まれる可能性があります。
bulldogger は値に対して `inspect` を呼ぶ前に、各ローカル変数名を検査します。
一致するローカル変数は `{"redacted": true, "reason": "name"}` となり、`value` フィールドを持ちません。

デフォルトのパターンは、大文字と小文字を区別せずに次の名前と一致します。

- `password`、`passwd`、`pass`
- `secret`、`token`
- `api_key`、`api-key`
- 単語としての `key`
- `credential`、`auth`、`session`、`cookie`

名前が曖昧な場合、パターンは秘匿する側へ寄せます。
たとえば `/auth/i` は `author` と `authorized` にも一致します。
アプリケーションは `Bulldogger.config.redact_patterns` を独自の正規表現で置き換えられます。
Bulldogger は redactor を構築するときに、これらのパターンを 1 つの union にコンパイルします。
元の配列をその場で変更しても、既存の redactor は変わりません。
そのパターンを使う取得またはトレースのセッションを Bulldogger が構築する前に、新しいパターン配列を割り当てます。

bulldogger は Hash をレンダリングするときにキーも検査します。
一致するキーのレンダリング値は文字列 `"[REDACTED]"` になります。

デフォルトでは 20 フレームと、各フレームの 50 ローカル変数を保持します。
レンダリングした各値は 200 文字を保持し、各 Array または Hash は 10 要素を保持します。
証拠ファイルは、省略または切り詰めたデータを示します。

## バージョン 0.2 の範囲

Version 0.2 は、失敗スナップショット、失敗時の自動リプレイ、対象を指定した probe、明示的な完全記録、独立したインスタンスを提供します。
JSON の証拠と JSONL のトレースを書き出します。
Version 0.2 の境界は、ファイル成果物とオフラインの SQLite 変換機能を公開します。

[設計判断](docs/design-decisions.md)は、3 つの方法と計測コストを説明します。

## ライセンス

MIT です。
`LICENSE` を参照してください。
