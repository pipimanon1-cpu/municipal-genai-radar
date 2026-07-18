# data/research/README.md

このディレクトリは、正式登録前の調査候補・続報候補・修正候補を管理する
research_queue.csv を格納する。

入力時に守るべき全般ルールは [CLAUDE.md](../../CLAUDE.md) を、
正式案件データの入力ルールは [data/validation/README.md](../validation/README.md) を参照すること。

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
