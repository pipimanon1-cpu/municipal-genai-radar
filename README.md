# municipal-genai-radar
日本の自治体における生成AIの実証・調達・本導入・成果・横展開を追跡するデータベース

## データ検証

data/validation/cases.csv と data/validation/events.csv の形式・整合性を検証する。

```
powershell -ExecutionPolicy Bypass -File scripts/validate-data.ps1
```
