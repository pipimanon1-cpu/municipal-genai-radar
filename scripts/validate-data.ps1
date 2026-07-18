# scripts/validate-data.ps1
# data/validation/cases.csv と data/validation/events.csv を検証する。
# 実行: powershell -ExecutionPolicy Bypass -File scripts/validate-data.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

$repoRoot = Split-Path -Parent $PSScriptRoot
$casesPath = Join-Path $repoRoot 'data\validation\cases.csv'
$eventsPath = Join-Path $repoRoot 'data\validation\events.csv'

$errors = New-Object System.Collections.Generic.List[string]

function Add-ValidationError {
    param([string]$File, [int]$Line, [string]$Column, [string]$Message)
    $errors.Add("${File}:${Line} [$Column] $Message")
}

function Read-CsvRows {
    param([string]$Path)
    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Path)
    $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $parser.SetDelimiters(',')
    $parser.HasFieldsEnclosedInQuotes = $true
    $rows = @()
    $rowNumber = 0
    while (-not $parser.EndOfData) {
        $rowNumber++
        $fields = $parser.ReadFields()
        $rows += [PSCustomObject]@{ Line = $rowNumber; Fields = $fields }
    }
    $parser.Close()
    return $rows
}

function Test-DateOrUnknown {
    param([string]$Value)
    return ($Value -eq 'unknown') -or ($Value -match '^\d{4}-\d{2}-\d{2}$')
}

function Test-BooleanOrUnknown {
    param([string]$Value)
    return $Value -in @('true', 'false', 'unknown')
}

function Test-IntegerOrUnknown {
    param([string]$Value)
    return ($Value -eq 'unknown') -or ($Value -match '^[0-9]+$')
}

$allowedCurrentStatus = @(
    '情報収集中', '検討・方針策定', '連携協定', '実証予定', '実証中',
    '実証結果公表', '調達・公募', '契約・採択', '本導入', '共同利用',
    '効果検証', '他自治体展開', '終了', '続報未確認'
)

$allowedSourceType = @('自治体公式', '企業公式', '官公庁', '議会資料', '予算・入札', '報道', 'その他')

$allowedQuantitativeResultType = @('実測', '実測からの推計', '事前試算', '目標', '定性評価', 'unknown')

$allowedEventType = @(
    '構想発表', '連携協定', '公募開始', '採択・契約', '実証開始', '実証終了',
    '実証結果公表', '本導入', '共同利用開始', '効果公表', '他自治体展開',
    'サービス終了', '続報確認', 'その他'
)

# ---- cases.csv ----
$casesFile = 'cases.csv'
$casesRows = Read-CsvRows -Path $casesPath
$caseIds = New-Object System.Collections.Generic.HashSet[string]
$caseDataCount = 0

if ($casesRows.Count -eq 0) {
    Add-ValidationError -File $casesFile -Line 0 -Column '-' -Message 'ファイルが空です'
}
else {
    $header = $casesRows[0]
    if ($header.Fields.Count -ne 30) {
        Add-ValidationError -File $casesFile -Line $header.Line -Column '-' -Message "ヘッダーが30列ではありません（実際: $($header.Fields.Count)列）"
    }

    for ($i = 1; $i -lt $casesRows.Count; $i++) {
        $row = $casesRows[$i]
        $f = $row.Fields
        $caseDataCount++

        if ($f.Count -ne 30) {
            Add-ValidationError -File $casesFile -Line $row.Line -Column '-' -Message "データ行が30列ではありません（実際: $($f.Count)列）"
            continue
        }

        $caseId = $f[0]
        if ($caseId -notmatch '^MGR-[0-9]{4}$') {
            Add-ValidationError -File $casesFile -Line $row.Line -Column 'case_id' -Message "形式が不正です: $caseId"
        }
        elseif (-not $caseIds.Add($caseId)) {
            Add-ValidationError -File $casesFile -Line $row.Line -Column 'case_id' -Message "case_idが重複しています: $caseId"
        }

        $currentStatus = $f[14]
        if ($currentStatus -notin $allowedCurrentStatus) {
            Add-ValidationError -File $casesFile -Line $row.Line -Column 'current_status' -Message "許可されていない値です: $currentStatus"
        }

        foreach ($dateCol in @(@{ Idx = 11; Name = 'announcement_date' }, @{ Idx = 12; Name = 'start_date' }, @{ Idx = 13; Name = 'end_date' }, @{ Idx = 27; Name = 'last_checked' })) {
            $val = $f[$dateCol.Idx]
            if (-not (Test-DateOrUnknown $val)) {
                Add-ValidationError -File $casesFile -Line $row.Line -Column $dateCol.Name -Message "YYYY-MM-DDまたはunknownではありません: $val"
            }
        }

        $quantitativeResultType = $f[19]
        if ($quantitativeResultType -notin $allowedQuantitativeResultType) {
            Add-ValidationError -File $casesFile -Line $row.Line -Column 'quantitative_result_type' -Message "許可されていない値です: $quantitativeResultType"
        }

        foreach ($boolCol in @(@{ Idx = 20; Name = 'commercialized' }, @{ Idx = 21; Name = 'shared_use' }, @{ Idx = 22; Name = 'expanded_to_other_municipalities' }) ) {
            $val = $f[$boolCol.Idx]
            if (-not (Test-BooleanOrUnknown $val)) {
                Add-ValidationError -File $casesFile -Line $row.Line -Column $boolCol.Name -Message "true/false/unknown以外の値です: $val"
            }
        }

        $sourceType1 = $f[24]
        if ($sourceType1 -notin $allowedSourceType) {
            Add-ValidationError -File $casesFile -Line $row.Line -Column 'source_type_1' -Message "許可されていない値です: $sourceType1"
        }

        $sourceUrl1 = $f[23]
        if ($sourceUrl1 -notlike 'https://*') {
            Add-ValidationError -File $casesFile -Line $row.Line -Column 'source_url_1' -Message "https://で始まっていません: $sourceUrl1"
        }

        $sourceUrl2 = $f[25]
        $sourceType2 = $f[26]
        if ([string]::IsNullOrEmpty($sourceUrl2)) {
            if (-not [string]::IsNullOrEmpty($sourceType2)) {
                Add-ValidationError -File $casesFile -Line $row.Line -Column 'source_type_2' -Message 'source_url_2が空欄なのにsource_type_2が空欄ではありません'
            }
        }
        else {
            if ($sourceUrl2 -notlike 'https://*') {
                Add-ValidationError -File $casesFile -Line $row.Line -Column 'source_url_2' -Message "https://で始まっていません: $sourceUrl2"
            }
            if ($sourceType2 -notin $allowedSourceType) {
                Add-ValidationError -File $casesFile -Line $row.Line -Column 'source_type_2' -Message "許可されていない値です: $sourceType2"
            }
        }

        foreach ($intCol in @(@{ Idx = 15; Name = 'users_count' }, @{ Idx = 16; Name = 'contract_amount_yen' })) {
            $val = $f[$intCol.Idx]
            if (-not (Test-IntegerOrUnknown $val)) {
                Add-ValidationError -File $casesFile -Line $row.Line -Column $intCol.Name -Message "整数またはunknownではありません: $val"
            }
        }
    }
}

# ---- events.csv ----
$eventsFile = 'events.csv'
$eventsRows = Read-CsvRows -Path $eventsPath
$eventIds = New-Object System.Collections.Generic.HashSet[string]
$eventDataCount = 0

if ($eventsRows.Count -eq 0) {
    Add-ValidationError -File $eventsFile -Line 0 -Column '-' -Message 'ファイルが空です'
}
else {
    $header = $eventsRows[0]
    if ($header.Fields.Count -ne 12) {
        Add-ValidationError -File $eventsFile -Line $header.Line -Column '-' -Message "ヘッダーが12列ではありません（実際: $($header.Fields.Count)列）"
    }

    for ($i = 1; $i -lt $eventsRows.Count; $i++) {
        $row = $eventsRows[$i]
        $f = $row.Fields
        $eventDataCount++

        if ($f.Count -ne 12) {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column '-' -Message "データ行が12列ではありません（実際: $($f.Count)列）"
            continue
        }

        $eventId = $f[0]
        if ($eventId -notmatch '^MGE-[0-9]{6}$') {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'event_id' -Message "形式が不正です: $eventId"
        }
        elseif (-not $eventIds.Add($eventId)) {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'event_id' -Message "event_idが重複しています: $eventId"
        }

        $caseId = $f[1]
        if ($caseId -notin $caseIds) {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'case_id' -Message "cases.csvに存在しないcase_idです: $caseId"
        }

        $eventType = $f[3]
        if ($eventType -notin $allowedEventType) {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'event_type' -Message "許可されていない値です: $eventType"
        }

        $eventDate = $f[2]
        if (-not (Test-DateOrUnknown $eventDate)) {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'event_date' -Message "YYYY-MM-DDまたはunknownではありません: $eventDate"
        }

        $sourceUrl = $f[7]
        if ($sourceUrl -notlike 'https://*') {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'source_url' -Message "https://で始まっていません: $sourceUrl"
        }

        $sourceType = $f[8]
        if ($sourceType -notin $allowedSourceType) {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'source_type' -Message "許可されていない値です: $sourceType"
        }

        $humanReviewed = $f[10]
        if (-not (Test-BooleanOrUnknown $humanReviewed)) {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'human_reviewed' -Message "true/false/unknown以外の値です: $humanReviewed"
        }

        $lastChecked = $f[9]
        if ($lastChecked -notmatch '^\d{4}-\d{2}-\d{2}$') {
            Add-ValidationError -File $eventsFile -Line $row.Line -Column 'last_checked' -Message "YYYY-MM-DD形式ではありません: $lastChecked"
        }
    }
}

# ---- 結果出力 ----
if ($errors.Count -eq 0) {
    Write-Output 'Validation passed'
    Write-Output "Cases: $caseDataCount"
    Write-Output "Events: $eventDataCount"
    Write-Output 'Errors: 0'
    exit 0
}
else {
    Write-Output 'Validation failed'
    foreach ($e in $errors) {
        Write-Output $e
    }
    Write-Output "Cases: $caseDataCount"
    Write-Output "Events: $eventDataCount"
    Write-Output "Errors: $($errors.Count)"
    exit 1
}
