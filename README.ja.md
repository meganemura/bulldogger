# bulldogger

このファイルは `README.md` の翻訳であり、内容が一致しない場合は `README.md` を正とします。

bulldogger は Ruby のテスト失敗を、コーディングエージェント向けの構造化された証拠として書き出します。
各 JSON ファイルには、例外、バックトレース、取得したフレームの値が含まれます。
失敗出力には、そのファイルの絶対パスが示されます。

開発とスナップショットの計測には Ruby 4.0.6 と debug 1.11.1 を使用しました。

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
bulldogger frames -- command...
bulldogger preflight -- command...
bulldogger flt path:method#k [--index path] -- command...
bulldogger exec path:method#k --line N [--visit K] --statement text [--index path] -- command...
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
モジュールのファサードが提供する失敗と probe の各メソッドも利用できます。

インテグレーションには、デフォルトの代わりに指定したインスタンスを使えます。

```ruby
Bulldogger::Minitest.instance = observer
Bulldogger::RSpec.instance = observer
```

テストスイートが始まる前にインスタンスを指定します。
この分離により、テストのセットアップがデフォルトインスタンスを置き換えても、外側のオブザーバーは動作を続けられます。

## コストモデル

常時有効な処理は、失敗スナップショットを取得します。
例外が発生しない green テストでは処理を行いません。
監視した例外 1 件には microseconds 単位のコストがかかります。

スナップショットのベンチマークには Ruby 4.0.6 を使いました。
raise と rescue の 1 サイクルあたり 44.126 microseconds を計測しました。
そのうちフレーム取得には 1.288 microseconds がかかりました。

再実行は明示的です。
`frames`、`preflight`、`flt`、`exec` は、ユーザーが実行したときだけ新しいプロセスを開始します。
`probe` も、ユーザーが選んだブロックの周囲でだけ動作します。

## 失敗スナップショットから開始

次のコマンドから、この出力を得ました。

```sh
bundle exec ruby -Ilib test/fixtures/minitest_red/red_test.rb --seed 12345
```

```text
  1) Error:
RedTest#test_deep_raise:
ArgumentError: expected 3 to equal the sum of [1, 2, 3]
    test/fixtures/minitest_red/app.rb:9:in 'Order.total'
    test/fixtures/minitest_red/red_test.rb:20:in 'RedTest#test_deep_raise'
bulldogger evidence: /home/you/project/tmp/bulldogger/run-20260831-192835-69510/001-RedTest-test_deep_raise.json (raising method is in these frames)
bulldogger rerun: bundle exec ruby -Itest test/fixtures/minitest_red/red_test.rb -n /\\Atest_deep_raise\\z/ --seed 12345
```

括弧内の案内がある行のパスを開きます。
このファイルには、1 件の失敗と取得した実行時の値が含まれます。
rerun 行には、そのテストと seed に対する完全なコマンドが含まれます。
bulldogger は、このコマンドを自動では実行しません。

各実行では次の配置を使います。

```text
tmp/bulldogger/
  latest -> run-20260829-100406-58231
  run-20260829-100406-58231/
    001-RedTest-test_deep_raise.json
    002-RedTest-test_assertion_failure.json
    index.json
```

[`bulldogger` skill](skills/bulldogger/SKILL.md) は、エージェントがこれらのファイルを調べる方法を説明します。
[証拠スキーマ](docs/evidence-schema.md)は、すべてのフィールドと取得モードを定義します。

## frames による分離実行のインデックス作成

rerun コマンドを `frames` の下で実行します。

```sh
bulldogger frames -- bundle exec ruby -Itest test/fixtures/frames/minitest_frames_test.rb --seed 12345
```

コマンドはインデックスのパスと子プロセスの結果を表示します。

```text
bulldogger frames: /home/you/project/tmp/bulldogger/frames-69833.jsonl
bulldogger result: pass (exit 0)
```

インデックスは各呼び出しにフレーム識別子 `fid` を付けます。
形式は `path:method#k` です。
数値は、テスト区間内にある同じメソッドの呼び出しを数えます。
インデックスには、アプリケーション、フレームワーク、gem のフレームが含まれます。

## preflight による分離再実行の検証

`flt` または `exec` の前に `preflight` を実行します。

```sh
bulldogger preflight -- bundle exec ruby -Itest test/fixtures/frames/minitest_frames_test.rb --seed 12345
```

同じコマンドを別々のプロセスで 2 回実行します。
2 つのアプリケーションフレーム列を比較します。

```text
bulldogger preflight: deterministic (app frames: 3)
bulldogger preflight indexes: /home/you/project/tmp/bulldogger/frames-70427.jsonl /home/you/project/tmp/bulldogger/frames-70432.jsonl
```

preflight が `deterministic` を表示した場合に限って、`flt` または `exec` を使います。
どちらの動詞もアプリケーションのフレーム識別子だけを受け付けます。

## flt による 1 フレームのトレース

アプリケーションの `fid` と同じ分離コマンドを渡します。

```sh
bulldogger flt test/fixtures/flt/minitest_flt_test.rb:branchy#1 -- bundle exec ruby -Itest test/fixtures/flt/minitest_flt_test.rb --seed 12345
```

```text
bulldogger flt: /home/you/project/tmp/bulldogger/flt-77206.jsonl
bulldogger result: pass (exit 0)
```

トレースには、フレーム開始、行ごとの変更、raise、return が含まれます。
新しいローカル変数は `new` に、更新は `changed` に記録します。
スコープを外れたローカル変数は `out_of_scope` に列挙します。
ループ中間の反復は `skipped_iterations` レコードにまとめます。

`--index path` は、インデックスと再実行に同じコード状態マーカーを要求します。

## exec による 1 文の評価

アプリケーションフレーム内の 1 回の行訪問を指定します。

```sh
bulldogger exec test/fixtures/exec/minitest_exec_test.rb:threshold#1 --line 9 --statement 'binding.local_variable_set(:result, 10)' -- bundle exec ruby -Itest test/fixtures/exec/minitest_exec_test.rb --seed 12345 -n test_injection_can_change_the_outcome
```

```text
bulldogger exec: /home/you/project/tmp/bulldogger/exec-77267.jsonl
bulldogger value: 10
bulldogger result: pass (exit 0)
```

`exec` は選択したフレームの binding で文を評価します。
デフォルトでは、その行の最初の訪問を選びます。
後の訪問には `--visit K` を使います。
launcher は必要な `BULLDOGGER_EXEC=1` token を子プロセスへ渡します。
`--index path` は、同じコード状態マーカーを要求します。

文はテストの動作を変え、副作用を発生させる可能性があります。
変更後の結果を証拠に使う前に、結果ファイルを読みます。

## RSpec の乱数 seed

RSpec は seed を例の順序に使います。
RSpec は `Kernel.srand` を呼びません。
例が `rand` を呼ぶ場合は、`RSpec.configure` 内に次の行を追加します。

```ruby
config.before(:suite) { Kernel.srand config.seed }
```

この行により、表示された rerun seed で乱数値を再現できます。
bulldogger はアプリケーションに代わって `Kernel.srand` を呼びません。

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

`probe` では対象メソッドの呼び出し 1 回あたり 1461.5 ns を計測しました。
フレームの gate では、対象外の呼び出し 1 件あたり約 105 ns を計測しました。

`flt` の line event には約 0.5 microseconds の固定コストがあります。
各ローカル変数の読み取りには、line event 1 件あたり約 0.1 microseconds が加わります。
20 個のローカル変数と 10,000 件の line event を持つフレームには約 27 ms かかりました。

これらの計測には Ruby 4.0.6 と rubygems.org のテストスイートを使いました。
スイートには 4,925 件のテストがあり、seed 12345 と 1 worker を使いました。
計測日は 2026-08-31 です。

## bulldogger の無効化

1 つのテストプロセスで取得と出力を無効にするには、`BULLDOGGER_DISABLE=1` を設定します。
`BULLDOGGER_DISABLED=1` は同じ動作をする別名です。

どちらかのスイッチを使うと、起動処理は `TracePoint(:raise)` の購読前に戻ります。
証拠を書かず、実行ディレクトリを作らず、失敗に証拠の行を追加しません。
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

Version 0.2 は、失敗スナップショット、probe、フレームインデックス、決定性検査、フレーム生存期間トレース、文の評価、独立したインスタンスを提供します。
JSON の証拠と JSONL の成果物を書き出します。
重い取得は、明示的な動詞からだけ開始します。

[設計判断](docs/design-decisions.md)は、証拠モデルと計測コストを説明します。

## ライセンス

MIT です。
`LICENSE` を参照してください。
