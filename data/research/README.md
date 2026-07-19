# data/research/README.md

このディレクトリは、半自走調査のための情報源台帳 watch_sources.csv と、
その監視実行履歴を記録する watch_runs.csv、
正式登録前の調査候補・続報候補・修正候補を管理する research_queue.csv を格納する。

入力時に守るべき全般ルールは [CLAUDE.md](../../CLAUDE.md) を、
正式案件データの入力ルールは [data/validation/README.md](../validation/README.md) を参照すること。

## 5つのファイルの役割

- **watch_sources.csv**：定期監視する情報源（自治体公式サイト・官公庁・入札情報等）の台帳。
- **watch_runs.csv**：watch_sources.csv の各情報源を確認するたびに追加する監視実行履歴。
  同じ source_id について複数の run を保持できる。
- **research_queue.csv**：定期監視や手動調査で発見した未検証の候補を管理する台帳。
- **cases.csv**：検証済み案件の現在の状態を管理する（[data/validation/](../validation/)）。
- **events.csv**：検証済み案件の時系列イベントを管理する（[data/validation/](../validation/)）。

watch_runs.csv は content_hash と previous_content_hash を比較して前回からの変更有無を判定する。
ハッシュはページ本文そのものを保存するものではなく、内容の同一性を確認するための値である。
change_summary には確認できた変更内容だけを簡潔に記録し、推測を書かない。
変更を検出したことだけを理由に cases.csv・events.csv へ直接登録してはならない。
新規案件や続報の可能性がある場合は research_queue.csv へ送り、人間確認を経てから
cases.csv・events.csv へ反映する。
ページ取得に失敗した場合も watch_runs.csv の行は削除せず、履歴として残す。
human_reviewed=false は未確認情報であることを示す。

watch_sources.csv から cases.csv・events.csv へ自動登録は行わない。
監視や調査で発見した情報は、まず research_queue.csv へ登録し、
人間による確認を経てから cases.csv・events.csv へ反映する。

is_active が false の情報源は、監視処理の対象外とする。
next_check_date は、将来の定期監視処理が次回確認日を判断するために利用する。
情報源の優先順位は自治体公式・官公庁など一次情報を優先し、
報道・PR TIMES等は一次情報の裏付け確認に利用する。

## watch_sources.csv の列定義（15列）

| 列名 | 内容 | 入力ルール |
|---|---|---|
| source_id | 情報源を一意に識別するID | `MWS-0001` 形式（正規表現 `^MWS-[0-9]{4}$`）。重複禁止。 |
| organization | 監視対象の自治体・官公庁・協議会等 | データ行では必須。空欄不可。 |
| prefecture | 都道府県名 | データ行では必須。特定できない場合は `unknown`。 |
| municipality_type | 組織区分 | `都道府県` / `市` / `特別区` / `町` / `村` / `広域連合` / `協議会` / `官公庁` / `その他` のいずれか。 |
| source_name | 監視ページの名称 | データ行では必須。空欄不可。 |
| source_url | 監視対象のURL | `https://` で始まることを必須とする。 |
| source_type | 情報源の種類 | `自治体公式` / `官公庁` / `予算・入札` / `議会資料` / `企業公式` / `PR TIMES` / `報道` / `その他` のいずれか。 |
| watch_scope | 監視する情報の種類 | `新着情報` / `報道発表` / `入札・プロポーザル` / `契約結果` / `DX・AI施策` / `個別案件` / `その他` のいずれか。 |
| keywords | 検出対象キーワード | 空欄可。複数値は半角セミコロン `;` 区切り。 |
| check_frequency | 確認頻度 | `毎日` / `週2回` / `毎週` / `隔週` / `毎月` / `手動` のいずれか。 |
| last_checked | 最終確認日 | `YYYY-MM-DD` 形式または `unknown`。 |
| next_check_date | 次回確認予定日 | `YYYY-MM-DD` 形式または `unknown`。 |
| is_active | 監視を有効にするか | `true` または `false` のみ。 |
| priority | 監視優先度 | `高` / `中` / `低` のいずれか。 |
| notes | 補足事項 | 空欄可。 |

## watch_runs.csv の列定義（18列）

| 列名 | 内容 | 入力ルール |
|---|---|---|
| run_id | 監視実行ログを一意に識別するID | `MWR-000001` 形式（正規表現 `^MWR-[0-9]{6}$`）。重複禁止。 |
| source_id | 対象の情報源ID | watch_sources.csv に実在する `MWS-0001` 形式のID。 |
| checked_at | 確認日時 | タイムゾーン付きRFC3339形式。 |
| check_result | 取得処理の結果 | `成功` / `一部取得` / `失敗` のいずれか。 |
| http_status | HTTPステータスコード | 100〜599の整数、または `unknown`。 |
| final_url | リダイレクト後の最終URL | `https://` で始まるURL、または `unknown`。 |
| page_title | 確認したページのタイトル | 空欄不可。取得できない場合は `unknown`。 |
| content_hash | 取得内容のSHA-256ハッシュ | 64文字の小文字16進数、または `unknown`。 |
| previous_content_hash | 直前のSHA-256ハッシュ | content_hash と同じ入力ルール。 |
| change_detected | 前回からの変更検出結果 | `true` / `false` / `unknown` のいずれか。 |
| change_type | 検出結果の分類 | `初回確認` / `変更なし` / `内容変更` / `URL変更` / `取得失敗` / `判定不能` のいずれか。 |
| change_summary | 変更内容の短い要約 | 空欄可。確認できた変更だけを記録する。 |
| matched_keywords | 検出された監視キーワード | 空欄可。複数値は半角セミコロン `;` 区切り。 |
| queue_candidate_status | research_queueへの登録判断状況 | `未判定` / `不要` / `候補` / `登録済み` / `保留` のいずれか。 |
| queue_id | 登録されたresearch_queueのID | `MRQ-0001` 形式、または `unknown`。`登録済み` の場合は `unknown` 禁止。 |
| checked_by | 確認の実施者 | `human` / `claude` / `automation` のいずれか。 |
| human_reviewed | 人間確認が完了したか | `true` または `false` のみ。 |
| notes | 取得エラーや判断上の補足 | 空欄可。 |

## research_queue.csv の目的

未検証・未確認の情報を、いきなり cases.csv へ正式登録しない。
research_queue.csv は、次の3種類の候補を一時的に管理するための台帳である。

- 新規案件の調査候補
- 既存案件（cases.csv）の続報候補
- 既存案件（cases.csv）のデータ修正候補

## cases.csv・events.csv との違い

- **research_queue.csv**：未検証の調査候補・続報候補・修正候補を管理する。
  正式案件として確定していない情報はすべてここに置く。
- **cases.csv**：確認済みの正式案件と、その現在の状態（current_status）を1行1案件で管理する。
- **events.csv**：正式案件について確認済みの時系列イベント（構想発表・契約・実証終了など）を管理する。

research_queue.csv の候補は、調査・確認が完了して初めて cases.csv / events.csv へ反映する。
確認前の情報を cases.csv / events.csv に書き込まない。

## get-due-watch-sources.ps1（確認対象ソースの抽出）

scripts/get-due-watch-sources.ps1 は、watch_sources.csv から
確認予定日（next_check_date）が本日以前（超過・本日を含む）の
有効な監視ソースを抽出し、コンソール表示・CSV出力するスクリプトである。

このスクリプトはWebページへアクセスしない。
監視先の内容確認・差分検出・research_queue.csvへの登録は行わない。

### 使用例

通常実行：

```
powershell -ExecutionPolicy Bypass -File scripts/get-due-watch-sources.ps1
```

日付指定：

```
powershell -ExecutionPolicy Bypass -File scripts/get-due-watch-sources.ps1 -TargetDate 2026-07-19
```

高優先度だけ：

```
powershell -ExecutionPolicy Bypass -File scripts/get-due-watch-sources.ps1 -Priority 高
```

CSV出力：

```
powershell -ExecutionPolicy Bypass -File scripts/get-due-watch-sources.ps1 -OutputPath reports/monitoring/due-sources.csv
```

日付とCSV出力：

```
powershell -ExecutionPolicy Bypass -File scripts/get-due-watch-sources.ps1 -TargetDate 2026-07-19 -OutputPath reports/monitoring/due-sources-2026-07-19.csv
```

### 運用ルール

- 通常は is_active=true だけを対象にする（-IncludeInactive を指定した場合のみ false も集計対象に含める）。
- next_check_date=unknown は確認対象に自動選出されない。
- 確認後は watch_sources.csv の last_checked と next_check_date を更新する。
- このスクリプトはWebページへアクセスしない。
- このスクリプトは research_queue.csv を変更しない。
- 監視で発見した情報は人間確認後に research_queue.csv へ登録する。

## 列定義（14列）

| 列名 | 内容 | 入力ルール |
|---|---|---|
| queue_id | 調査候補を一意に識別するID | `MRQ-0001`, `MRQ-0002`... の形式に統一する（正規表現 `^MRQ-[0-9]{4}$`）。一度発行したIDは変更・再利用しない。重複禁止。 |
| research_type | 候補の種別 | `新規案件` / `既存案件の続報` / `データ修正候補` のいずれか。 |
| discovered_date | 候補を発見した日付 | `YYYY-MM-DD` 形式。不明な場合は `unknown`。 |
| municipality | 自治体名 | 市区町村・一部事務組合名。未確認の場合は `unknown`。 |
| prefecture | 都道府県名 | 未確認の場合は `unknown`。 |
| case_title | 調査候補の案件名 | 未確認の場合は `unknown`。 |
| discovery_url | 発見元のURL | `https://` で始まるURLを必須で入力する。 |
| discovery_source | 発見元の情報源種別 | `自治体公式` / `企業公式` / `官公庁` / `予算・入札` / `議会資料` / `PR TIMES` / `報道` / `その他` のいずれか。 |
| research_status | 調査の進捗状況 | `未調査` / `調査中` / `登録候補` / `登録済み` / `保留` / `対象外` / `続報確認待ち` のいずれか。 |
| target_case_id | 関係する既存案件のID | `MGR-0001` 形式（正規表現 `^MGR-[0-9]{4}$`）。未割り当ての場合は `unknown`。ただし research_type が `既存案件の続報` または `データ修正候補` の場合は `unknown` 禁止。research_status が `登録済み` の場合も `unknown` 禁止。指定する場合は cases.csv に実在する case_id を入力する。 |
| priority | 調査の優先度 | `高` / `中` / `低` のいずれか。 |
| next_check_date | 次回確認予定日 | `YYYY-MM-DD` 形式。日程未定の場合は `unknown`。 |
| last_updated | このレコードを最後に更新した日付 | `YYYY-MM-DD` 形式。必須。 |
| research_notes | 補足事項 | 自由記述。複数の値を並べる場合は半角セミコロン `;` で区切る。空欄可。 |

## record-watch-run.ps1（監視実行結果の記録）

scripts/record-watch-run.ps1 は、与えられた確認結果1件を watch_runs.csv へ追加し、
同時に watch_sources.csv の該当 source_id の last_checked と next_check_date を更新する
スクリプトである。前回ハッシュとの比較による change_detected / change_type の判定、
run_id の採番、書き込み前後の検証、失敗時の両CSV復元も行う。

このスクリプトはWebページへアクセスしない。与えられた確認結果を記録するだけであり、
ページ取得処理は別の処理が担当する。

### 使用例

DryRunによる判定確認：

```
powershell -ExecutionPolicy Bypass -File scripts/record-watch-run.ps1 `
  -SourceId MWS-0002 `
  -CheckedAt 2026-07-26T10:00:00+09:00 `
  -CheckResult 成功 `
  -HttpStatus 200 `
  -FinalUrl https://example.com/monitoring-page `
  -PageTitle "監視ページ" `
  -ContentHash aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa `
  -QueueCandidateStatus 未判定 `
  -CheckedBy human `
  -DryRun
```

取得失敗の記録例：

```
powershell -ExecutionPolicy Bypass -File scripts/record-watch-run.ps1 `
  -SourceId MWS-0002 `
  -CheckResult 失敗 `
  -HttpStatus 503 `
  -FinalUrl https://example.com/monitoring-page `
  -PageTitle unknown `
  -ContentHash unknown `
  -Notes "一時的な取得失敗" `
  -CheckedBy automation
```

### 運用ルール

- 最初はDryRunで判定内容を確認する。
- 実行時にwatch_sourcesとwatch_runsを同時更新する。
- Web取得は別の処理が担当する。
- 変更検出だけでcasesやeventsへ直接登録しない。
- 候補情報はresearch_queueへ送る。
- 取得失敗も監視履歴として残す。
- 人間未確認の自動結果はhuman_reviewed=falseとする。
- AllowBackdatedは履歴修正時だけ使用する。

## unknown の扱い

- 未確認の項目は空欄にせず、原則として `unknown` を入力する。
- ただし target_case_id は、research_type が `既存案件の続報` / `データ修正候補` の場合、
  および research_status が `登録済み` の場合は `unknown` を使用できない。
  既存案件との関連が確定していない段階では、これらの research_type / research_status を使わない。

## 正式案件へ登録するまでの流れ（新規案件）

1. `未調査`：discovery_url を発見した直後の状態。
2. `調査中`：自治体公式・官公庁・入札資料など一次情報の確認を進めている状態。
3. `登録候補`：正式登録に足る事実（自治体名・案件内容・出典）が確認できた状態。
4. cases.csv へ新規行として登録する（新しい case_id を発行する）。
5. `登録済み`：cases.csv への登録が完了した状態。target_case_id に発行した case_id を入力する。

## 既存案件の続報を登録する流れ

1. `続報確認待ち`：既存案件（target_case_id）に関する続報の可能性がある情報を発見した状態。
2. `調査中`：続報の内容を一次情報で確認している状態。
3. events.csv へ新規イベント行として追加する。
4. 必要に応じて cases.csv の該当行の current_status / end_date / source_url_2 / source_type_2 /
   last_checked / notes を更新する。
5. `登録済み`：events.csv への追加（および必要な cases.csv 更新）が完了した状態。

## 入力時の注意

- PR TIMES や報道のみを根拠に正式登録（cases.csv への登録・登録済みへの変更）を確定しない。
- 可能な限り自治体公式・官公庁・入札資料など一次情報を確認する。
- 新規案件を登録する前に、同一案件が既に cases.csv に存在しないか必ず確認する。
- 契約金額・日付・企業名などを推測で補完しない。確認できない場合は `unknown` とする。
- `対象外` と判断した候補も削除せず、判断理由を research_notes に残す。
