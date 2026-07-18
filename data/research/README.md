# data/research/README.md

このディレクトリは、半自走調査のための情報源台帳 watch_sources.csv と、
正式登録前の調査候補・続報候補・修正候補を管理する research_queue.csv を格納する。

入力時に守るべき全般ルールは [CLAUDE.md](../../CLAUDE.md) を、
正式案件データの入力ルールは [data/validation/README.md](../validation/README.md) を参照すること。

## 4つのファイルの役割

- **watch_sources.csv**：定期監視する情報源（自治体公式サイト・官公庁・入札情報等）の台帳。
- **research_queue.csv**：定期監視や手動調査で発見した未検証の候補を管理する台帳。
- **cases.csv**：検証済み案件の現在の状態を管理する（[data/validation/](../validation/)）。
- **events.csv**：検証済み案件の時系列イベントを管理する（[data/validation/](../validation/)）。

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
