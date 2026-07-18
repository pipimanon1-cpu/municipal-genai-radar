# data/validation/README.md

このディレクトリは、自治体生成AIレーダー（Municipal GenAI Radar）の初期検証で収集する
案件データ（cases.csv）と、案件ごとの続報・経過を記録するイベントデータ（events.csv）を格納する。
events.csv の入力ルールは [events_README.md](./events_README.md) を参照すること。

収集の手順・判定基準は [docs/VALIDATION_PLAN.md](../../docs/VALIDATION_PLAN.md) を、
入力時に守るべき全般ルールは [CLAUDE.md](../../CLAUDE.md) を参照すること。

## 基本方針

- 1行 = 1案件。同一案件の続報は cases.csv に新規行として追加せず、events.csv に追加する
  （判定方法は docs/VALIDATION_PLAN.md「5. 重複判定方法」を参照）。
  cases.csv の current_status は最新のイベントに合わせて更新する。
  別製品・別目的の施策は、同一自治体であっても別案件として cases.csv に新規登録する。
- 不明な項目は空欄にせず、原則として `unknown` を入力する（日付・数値・名称・状態など項目種別を問わない）。
  department、genai_model、start_date、end_date、users_count、contract_amount_yen、
  procurement_method など、公開情報から確認できない項目はすべて `unknown` を使用する。
  「未確認」という日本語トークンはCSV内では使用しない。
  ただし source_url_2 / source_type_2 は、2件目の出典が存在しない場合は `unknown` ではなく空欄にする
  （source_url_2 が空欄の場合は source_type_2 も空欄にする）。
- companies、department など複数の値を入力する項目は、半角セミコロン `;` で区切って列挙する
  （例：`A社;B社`）。
- 出典に明記されていない事実を推測して埋めない。
- human_reviewed が `true` になるまで、そのレコードは下書き（未確定）として扱う。

## 列定義

| 列名 | 内容 | 入力ルール |
|---|---|---|
| case_id | 案件を一意に識別するID | `MGR-0001`, `MGR-0002`... の形式に統一する（正規表現 `^MGR-[0-9]{4}$`）。一度発行したIDは変更・再利用しない。 |
| case_title | 案件名（識別用の短い見出し） | 「〇〇市 生成AI議事録作成実証」のように、自治体名と取り組み内容が分かる簡潔な文言にする。 |
| municipality | 市区町村・一部事務組合名 | 都道府県単位の案件の場合は都道府県名を入力し、この列は `-`（該当なし）とする。不明な場合は `unknown`。 |
| prefecture | 都道府県名 | 都道府県が主体の案件でも、市区町村の案件でも、所属都道府県は必ず入力する。 |
| municipality_type | 自治体区分 | `都道府県` / `市` / `区` / `町` / `村` / `一部事務組合` のいずれかを入力する。 |
| department | 担当部署 | 発表内で確認できる担当課・部局名。不明な場合は `unknown`。 |
| companies | 関与する企業名 | 複数ある場合はセミコロン `;` で区切って列挙する（例：`A社;B社`）。 |
| product_name | 製品・サービス名 | 「生成AI」「AIチャットボット」等の一般名詞のみは不可。具体名が不明な場合は `unknown`。 |
| genai_model | 利用している生成AI・モデルの種別 | 例：`ChatGPT`, `Azure OpenAI Service`, `Gemini` など。公表されていない場合は `unknown`。 |
| use_case | 具体的な利用用途 | 例：「議事録作成」「住民からの問い合わせ対応」「例規審査支援」など、簡潔に記述する。 |
| primary_category | 主要な取り組み分類 | 例：`職員業務効率化` / `住民サービス` / `政策検討支援` など、案件の主目的を1つ選ぶ。 |
| announcement_date | 公表日（発表・報道日） | `YYYY-MM-DD` 形式。日単位が不明な場合は `YYYY-MM` まででもよい。契約日・実施日と混同しない（CLAUDE.md参照）。 |
| start_date | 実施（実証・導入等）の開始日 | `YYYY-MM-DD` 形式。公表日と異なる場合は必ず区別して入力する。不明な場合は `unknown`。 |
| end_date | 実施（実証等）の終了日、または本導入への移行日 | `YYYY-MM-DD` 形式。継続中の場合は `継続中` と入力する。不明な場合は `unknown`。 |
| current_status | 案件の進捗段階 | 下記「ステータス一覧」から1つを選択する。複数の段階が同時に読み取れる場合は、最新の段階を採用する。 |
| users_count | 利用者数・利用対象者数 | 職員数、住民利用件数など、公表されている数値をそのまま入力する。単位が分かるように記載する（例：`職員約500人`）。不明な場合は `unknown`。 |
| contract_amount_yen | 契約金額・予算額（円） | 数値のみを入力する（例：`3000000`）。円以外の単位（税込/税抜、上限額等）の注記は notes に記載する。不明な場合は `unknown`。 |
| procurement_method | 調達方式 | 例：`公募型プロポーザル` / `一般競争入札` / `随意契約` / `実証実験（無償）` など。不明な場合は `unknown`。 |
| quantitative_result | 定量的な成果 | 例：「問い合わせ対応時間を月間20時間削減」など、公表されている数値成果を記載する。定性的な感想のみの場合はここに入れず notes に記載する。 |
| commercialized | 本導入（商用・本格運用）に至ったか | `true` / `false` / `unknown` のいずれかを入力する。`false` は公式情報で本導入に至っていないことが明確に確認できる場合のみ使用し、確認できない場合は `unknown` とする。 |
| shared_use | 複数自治体・広域での共同利用があるか | `true` / `false` / `unknown`。`false` は公式情報で否定が確認できる場合のみ使用する。 |
| expanded_to_other_municipalities | 他自治体への横展開が確認できるか | `true` / `false` / `unknown`。`false` は公式情報で否定が確認できる場合のみ使用する。横展開先が分かる場合は notes に自治体名を記載する。 |
| source_url_1 | 主たる出典のURL | 可能な限り一次情報（自治体・企業の公式発表）のURLを入力する。 |
| source_type_1 | source_url_1 の情報源種別 | `自治体公式` / `企業公式` / `官公庁` / `議会資料` / `予算・入札` / `報道` / `その他` のいずれかを入力する。 |
| source_url_2 | 補助的な出典のURL | 2件目の出典がある場合に入力する。存在しない場合は `unknown` ではなく空欄にする。 |
| source_type_2 | source_url_2 の情報源種別 | source_type_1 と同じ選択肢から入力する。source_url_2 が空欄の場合はこの列も空欄にする。 |
| last_checked | 最終確認日 | このレコードの内容を最後に確認・更新した日付（`YYYY-MM-DD`）。 |
| human_reviewed | 人間によるレビュー済みか | `true` / `false`。`false` の間は下書き（未確定情報）として扱う（CLAUDE.md参照）。 |
| notes | 補足事項 | 続報の履歴、判断に迷った点、他の列に書ききれない事実などを自由記述する。推測は書かず、事実と `unknown`（未確認情報）を区別して記載する。 |

## ステータス一覧（current_status）

- 情報収集中
- 検討・方針策定
- 連携協定
- 実証予定
- 実証中
- 実証結果公表
- 調達・公募
- 契約・採択
- 本導入
- 共同利用
- 効果検証
- 他自治体展開
- 終了
- 続報なし

## 入力時の注意

- 実証（PoC）と本導入は明確に区別する。実証中の案件を安易に「本導入」にしない。
- 続報を確認した場合は、新しい行を追加するのではなく、既存行の
  current_status / end_date / source_url_2 / source_type_2 / last_checked / notes を更新する。
- 元記事の本文や画像はそのまま転載せず、事実の要約と出典URLの記載にとどめる。
- カンマ `,` を含む値を入力する場合は、CSVの規則に従いダブルクォートで囲む。
