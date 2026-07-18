# scripts/validate-data.ps1
# data/validation/cases.csv と data/validation/events.csv、
# data/research/research_queue.csv、data/research/watch_sources.csv を検証する。
# 実行: powershell -ExecutionPolicy Bypass -File scripts/validate-data.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

$repoRoot = Split-Path -Parent $PSScriptRoot
$casesPath = Join-Path $repoRoot 'data\validation\cases.csv'
$eventsPath = Join-Path $repoRoot 'data\validation\events.csv'
$researchQueuePath = Join-Path $repoRoot 'data\research\research_queue.csv'
$watchSourcesPath = Join-Path $repoRoot 'data\research\watch_sources.csv'

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

$allowedResearchType = @('新規案件', '既存案件の続報', 'データ修正候補')

$allowedDiscoverySource = @(
    '自治体公式', '企業公式', '官公庁', '予算・入札', '議会資料', 'PR TIMES', '報道', 'その他'
)

$allowedResearchStatus = @('未調査', '調査中', '登録候補', '登録済み', '保留', '対象外', '続報確認待ち')

$allowedPriority = @('高', '中', '低')

$allowedMunicipalityType = @('都道府県', '市', '特別区', '町', '村', '広域連合', '協議会', '官公庁', 'その他')

$allowedWatchSourceType = @('自治体公式', '官公庁', '予算・入札', '議会資料', '企業公式', 'PR TIMES', '報道', 'その他')

$allowedWatchScope = @('新着情報', '報道発表', '入札・プロポーザル', '契約結果', 'DX・AI施策', '個別案件', 'その他')

$allowedCheckFrequency = @('毎日', '週2回', '毎週', '隔週', '毎月', '手動')

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

# ---- research_queue.csv ----
$researchQueueFile = 'research_queue.csv'
$researchQueueDataCount = 0

if (-not (Test-Path $researchQueuePath)) {
    Add-ValidationError -File $researchQueueFile -Line 0 -Column '-' -Message 'ファイルが存在しません'
}
else {
    $queueRows = Read-CsvRows -Path $researchQueuePath
    $queueIds = New-Object System.Collections.Generic.HashSet[string]

    if ($queueRows.Count -eq 0) {
        Add-ValidationError -File $researchQueueFile -Line 0 -Column '-' -Message 'ファイルが空です'
    }
    else {
        $expectedHeader = @(
            'queue_id', 'research_type', 'discovered_date', 'municipality', 'prefecture',
            'case_title', 'discovery_url', 'discovery_source', 'research_status',
            'target_case_id', 'priority', 'next_check_date', 'last_updated', 'research_notes'
        )
        $header = $queueRows[0]
        if (@(Compare-Object -ReferenceObject $expectedHeader -DifferenceObject $header.Fields -SyncWindow 0).Count -ne 0 -or $header.Fields.Count -ne 14) {
            Add-ValidationError -File $researchQueueFile -Line $header.Line -Column '-' -Message "ヘッダーが指定の14列と一致しません（実際: $($header.Fields -join ',')）"
        }

        for ($i = 1; $i -lt $queueRows.Count; $i++) {
            $row = $queueRows[$i]
            $f = $row.Fields
            $researchQueueDataCount++

            if ($f.Count -ne 14) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column '-' -Message "データ行が14列ではありません（実際: $($f.Count)列）"
                continue
            }

            $queueId = $f[0]
            if ($queueId -notmatch '^MRQ-[0-9]{4}$') {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'queue_id' -Message "形式が不正です: $queueId"
            }
            elseif (-not $queueIds.Add($queueId)) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'queue_id' -Message "queue_idが重複しています: $queueId"
            }

            $researchType = $f[1]
            if ($researchType -notin $allowedResearchType) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'research_type' -Message "許可されていない値です: $researchType"
            }

            $discoveredDate = $f[2]
            if (-not (Test-DateOrUnknown $discoveredDate)) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'discovered_date' -Message "YYYY-MM-DDまたはunknownではありません: $discoveredDate"
            }

            $discoveryUrl = $f[6]
            if ($discoveryUrl -notlike 'https://*') {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'discovery_url' -Message "https://で始まっていません: $discoveryUrl"
            }

            $discoverySource = $f[7]
            if ($discoverySource -notin $allowedDiscoverySource) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'discovery_source' -Message "許可されていない値です: $discoverySource"
            }

            $researchStatus = $f[8]
            if ($researchStatus -notin $allowedResearchStatus) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'research_status' -Message "許可されていない値です: $researchStatus"
            }

            $targetCaseId = $f[9]
            if ($targetCaseId -ne 'unknown' -and $targetCaseId -notmatch '^MGR-[0-9]{4}$') {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'target_case_id' -Message "形式が不正です: $targetCaseId"
            }

            if ($targetCaseId -eq 'unknown') {
                if ($researchType -in @('既存案件の続報', 'データ修正候補')) {
                    Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'target_case_id' -Message "research_typeが「$researchType」の場合、target_case_idにunknownは使用できません"
                }
                if ($researchStatus -eq '登録済み') {
                    Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'target_case_id' -Message 'research_statusが「登録済み」の場合、target_case_idにunknownは使用できません'
                }
            }
            elseif ($targetCaseId -match '^MGR-[0-9]{4}$' -and $targetCaseId -notin $caseIds) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'target_case_id' -Message "cases.csvに存在しないcase_idです: $targetCaseId"
            }

            $priority = $f[10]
            if ($priority -notin $allowedPriority) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'priority' -Message "許可されていない値です: $priority"
            }

            $nextCheckDate = $f[11]
            if (-not (Test-DateOrUnknown $nextCheckDate)) {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'next_check_date' -Message "YYYY-MM-DDまたはunknownではありません: $nextCheckDate"
            }

            $lastUpdated = $f[12]
            if ($lastUpdated -notmatch '^\d{4}-\d{2}-\d{2}$') {
                Add-ValidationError -File $researchQueueFile -Line $row.Line -Column 'last_updated' -Message "YYYY-MM-DD形式ではありません: $lastUpdated"
            }
        }
    }
}

# ---- watch_sources.csv ----
$watchSourcesFile = 'watch_sources.csv'
$watchSourcesDataCount = 0

if (-not (Test-Path $watchSourcesPath)) {
    Add-ValidationError -File $watchSourcesFile -Line 0 -Column '-' -Message 'ファイルが存在しません'
}
else {
    $watchRows = Read-CsvRows -Path $watchSourcesPath
    $watchSourceIds = New-Object System.Collections.Generic.HashSet[string]

    if ($watchRows.Count -eq 0) {
        Add-ValidationError -File $watchSourcesFile -Line 0 -Column '-' -Message 'ファイルが空です'
    }
    else {
        $expectedWatchHeader = @(
            'source_id', 'organization', 'prefecture', 'municipality_type', 'source_name',
            'source_url', 'source_type', 'watch_scope', 'keywords', 'check_frequency',
            'last_checked', 'next_check_date', 'is_active', 'priority', 'notes'
        )
        $header = $watchRows[0]
        if (@(Compare-Object -ReferenceObject $expectedWatchHeader -DifferenceObject $header.Fields -SyncWindow 0).Count -ne 0 -or $header.Fields.Count -ne 15) {
            Add-ValidationError -File $watchSourcesFile -Line $header.Line -Column '-' -Message "ヘッダーが指定の15列と一致しません（実際: $($header.Fields -join ',')）"
        }

        for ($i = 1; $i -lt $watchRows.Count; $i++) {
            $row = $watchRows[$i]
            $f = $row.Fields
            $watchSourcesDataCount++

            if ($f.Count -ne 15) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column '-' -Message "データ行が15列ではありません（実際: $($f.Count)列）"
                continue
            }

            $sourceId = $f[0]
            if ($sourceId -notmatch '^MWS-[0-9]{4}$') {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'source_id' -Message "形式が不正です: $sourceId"
            }
            elseif (-not $watchSourceIds.Add($sourceId)) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'source_id' -Message "source_idが重複しています: $sourceId"
            }

            $organization = $f[1]
            if ([string]::IsNullOrEmpty($organization)) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'organization' -Message '空欄です'
            }

            $prefecture = $f[2]
            if ([string]::IsNullOrEmpty($prefecture)) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'prefecture' -Message '空欄です'
            }

            $municipalityType = $f[3]
            if ($municipalityType -notin $allowedMunicipalityType) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'municipality_type' -Message "許可されていない値です: $municipalityType"
            }

            $sourceName = $f[4]
            if ([string]::IsNullOrEmpty($sourceName)) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'source_name' -Message '空欄です'
            }

            $sourceUrl = $f[5]
            if ($sourceUrl -notlike 'https://*') {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'source_url' -Message "https://で始まっていません: $sourceUrl"
            }

            $sourceType = $f[6]
            if ($sourceType -notin $allowedWatchSourceType) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'source_type' -Message "許可されていない値です: $sourceType"
            }

            $watchScope = $f[7]
            if ($watchScope -notin $allowedWatchScope) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'watch_scope' -Message "許可されていない値です: $watchScope"
            }

            $checkFrequency = $f[9]
            if ($checkFrequency -notin $allowedCheckFrequency) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'check_frequency' -Message "許可されていない値です: $checkFrequency"
            }

            $lastChecked = $f[10]
            if (-not (Test-DateOrUnknown $lastChecked)) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'last_checked' -Message "YYYY-MM-DDまたはunknownではありません: $lastChecked"
            }

            $nextCheckDate = $f[11]
            if (-not (Test-DateOrUnknown $nextCheckDate)) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'next_check_date' -Message "YYYY-MM-DDまたはunknownではありません: $nextCheckDate"
            }

            $isActive = $f[12]
            if ($isActive -notin @('true', 'false')) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'is_active' -Message "true/false以外の値です: $isActive"
            }

            $priority = $f[13]
            if ($priority -notin $allowedPriority) {
                Add-ValidationError -File $watchSourcesFile -Line $row.Line -Column 'priority' -Message "許可されていない値です: $priority"
            }
        }
    }
}

# ---- 結果出力 ----
if ($errors.Count -eq 0) {
    Write-Output 'Validation passed'
    Write-Output "Cases: $caseDataCount"
    Write-Output "Events: $eventDataCount"
    Write-Output "Research queue: $researchQueueDataCount"
    Write-Output "Watch sources: $watchSourcesDataCount"
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
    Write-Output "Research queue: $researchQueueDataCount"
    Write-Output "Watch sources: $watchSourcesDataCount"
    Write-Output "Errors: $($errors.Count)"
    exit 1
}
