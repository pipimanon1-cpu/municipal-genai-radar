# scripts/record-watch-run.ps1
# data/research/watch_sources.csv の確認結果を data/research/watch_runs.csv へ1件追加し、
# 対応する watch_sources.csv の last_checked / next_check_date を同時に更新する。
# Webページの取得処理は行わない。与えられた確認結果を記録するだけの機能である。
# 実行: powershell -ExecutionPolicy Bypass -File scripts/record-watch-run.ps1 -SourceId MWS-0001 -CheckResult 成功 ...

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceId,

    [Parameter(Mandatory = $true)]
    [string]$CheckResult,

    [string]$CheckedAt,
    [string]$HttpStatus = 'unknown',
    [string]$FinalUrl = 'unknown',
    [string]$PageTitle = 'unknown',
    [string]$ContentHash = 'unknown',
    [string]$ChangeSummary = '',
    [string]$MatchedKeywords = '',
    [string]$QueueCandidateStatus = '未判定',
    [string]$QueueId = 'unknown',
    [string]$CheckedBy = 'human',
    [string]$HumanReviewed = 'false',
    [string]$Notes = '',
    [string]$NextCheckDate,
    [string]$WatchSourcesPath = 'data/research/watch_sources.csv',
    [string]$WatchRunsPath = 'data/research/watch_runs.csv',
    [switch]$DryRun,
    [switch]$AllowBackdated
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

$repoRoot = Split-Path -Parent $PSScriptRoot
$isCustomPath = $PSBoundParameters.ContainsKey('WatchSourcesPath') -or $PSBoundParameters.ContainsKey('WatchRunsPath')

$allowedCheckResult = @('成功', '一部取得', '失敗')
$allowedQueueCandidateStatus = @('未判定', '不要', '候補', '登録済み', '保留')
$allowedCheckedBy = @('human', 'claude', 'automation')
$allowedCheckFrequency = @('毎日', '週2回', '毎週', '隔週', '毎月', '手動')

$expectedWatchSourcesHeader = @(
    'source_id', 'organization', 'prefecture', 'municipality_type', 'source_name',
    'source_url', 'source_type', 'watch_scope', 'keywords', 'check_frequency',
    'last_checked', 'next_check_date', 'is_active', 'priority', 'notes'
)
$expectedWatchRunsHeader = @(
    'run_id', 'source_id', 'checked_at', 'check_result', 'http_status', 'final_url',
    'page_title', 'content_hash', 'previous_content_hash', 'change_detected', 'change_type',
    'change_summary', 'matched_keywords', 'queue_candidate_status', 'queue_id', 'checked_by',
    'human_reviewed', 'notes'
)

# ---- 汎用ヘルパー ----

function Resolve-RepoPath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-Path $repoRoot $Path
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

function Get-RawLines {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    $lines = $text -split "`n"
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
        $lines = $lines[0..($lines.Count - 2)]
    }
    return , $lines
}

function Write-RawLines {
    param([string]$Path, [string[]]$Lines)
    $content = ($Lines -join "`n") + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function ConvertTo-CsvField {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value -match '[",\r\n]') {
        return '"' + ($Value -replace '"', '""') + '"'
    }
    return $Value
}

function ConvertTo-CsvLine {
    param([string[]]$Values)
    return ($Values | ForEach-Object { ConvertTo-CsvField $_ }) -join ','
}

function Test-StrictDate {
    param([string]$Value)
    $parsed = [DateTime]::MinValue
    return [DateTime]::TryParseExact(
        $Value, 'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
}

function ConvertTo-StrictDate {
    param([string]$Value)
    return [DateTime]::ParseExact($Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-DateOrUnknown {
    param([string]$Value)
    return ($Value -eq 'unknown') -or (Test-StrictDate $Value)
}

function Test-Rfc3339 {
    param([string]$Value)
    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$') {
        return $false
    }
    $parsed = [System.DateTimeOffset]::MinValue
    return [System.DateTimeOffset]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
}

function Test-CsvHeader {
    param([string[]]$Actual, [string[]]$Expected)
    if ($Actual.Count -ne $Expected.Count) { return $false }
    for ($i = 0; $i -lt $Expected.Count; $i++) {
        if ($Actual[$i] -ne $Expected[$i]) { return $false }
    }
    return $true
}

$errors = New-Object System.Collections.Generic.List[string]
function Add-ScriptError {
    param([string]$Message)
    $errors.Add($Message)
}

function Exit-OnErrors {
    if ($errors.Count -gt 0) {
        Write-Output 'エラー:'
        foreach ($e in $errors) { Write-Output "- $e" }
        exit 1
    }
}

# ---- フェーズ1: 単体パラメータの検証（ファイル参照なし） ----

if ($SourceId -notmatch '^MWS-[0-9]{4}$') {
    Add-ScriptError "SourceIdの形式が不正です: $SourceId"
}

if ($CheckResult -notin $allowedCheckResult) {
    Add-ScriptError "CheckResultが許可されていない値です: $CheckResult"
}

if (-not $PSBoundParameters.ContainsKey('CheckedAt')) {
    $CheckedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
}
if (-not (Test-Rfc3339 $CheckedAt)) {
    Add-ScriptError "CheckedAtがタイムゾーン付きRFC3339形式ではありません（秒とタイムゾーンが必須）: $CheckedAt"
}

if ($HttpStatus -ne 'unknown') {
    if ($HttpStatus -notmatch '^[0-9]+$' -or [int]$HttpStatus -lt 100 -or [int]$HttpStatus -gt 599) {
        Add-ScriptError "HttpStatusは100から599の整数またはunknownである必要があります: $HttpStatus"
    }
}

if ($FinalUrl -ne 'unknown' -and $FinalUrl -notlike 'https://*') {
    Add-ScriptError "FinalUrlはhttps://で始まるURLまたはunknownである必要があります: $FinalUrl"
}

if ([string]::IsNullOrEmpty($PageTitle)) {
    Add-ScriptError 'PageTitleは空欄にできません（取得できない場合はunknownを指定してください）'
}

if ($ContentHash -ne 'unknown') {
    if ($ContentHash -match '^[a-f0-9]{64}$') {
        # OK
    }
    elseif ($ContentHash -match '^[A-Fa-f0-9]{64}$') {
        Add-ScriptError "ContentHashに大文字16進数が含まれています。小文字へ自動変換せずエラーとします: $ContentHash"
    }
    else {
        Add-ScriptError "ContentHashは64文字の小文字16進数またはunknownである必要があります: $ContentHash"
    }
}

if ($CheckResult -eq '成功') {
    if ($HttpStatus -eq 'unknown') {
        Add-ScriptError 'CheckResultが成功の場合、HttpStatusをunknownにはできません'
    }
    if ($ContentHash -eq 'unknown') {
        Add-ScriptError 'CheckResultが成功の場合、ContentHashをunknownにはできません'
    }
}

if ($QueueCandidateStatus -notin $allowedQueueCandidateStatus) {
    Add-ScriptError "QueueCandidateStatusが許可されていない値です: $QueueCandidateStatus"
}

if ($QueueId -ne 'unknown' -and $QueueId -notmatch '^MRQ-[0-9]{4}$') {
    Add-ScriptError "QueueIdの形式が不正です: $QueueId"
}

if ($QueueCandidateStatus -eq '登録済み' -and $QueueId -eq 'unknown') {
    Add-ScriptError 'QueueCandidateStatusが登録済みの場合、QueueIdにunknownは使用できません'
}

if ($CheckedBy -notin $allowedCheckedBy) {
    Add-ScriptError "CheckedByが許可されていない値です: $CheckedBy"
}

if ($HumanReviewed -notin @('true', 'false')) {
    Add-ScriptError "HumanReviewedはtrueまたはfalseである必要があります: $HumanReviewed"
}

$nextCheckDateExplicit = $PSBoundParameters.ContainsKey('NextCheckDate')
if ($nextCheckDateExplicit -and -not (Test-DateOrUnknown $NextCheckDate)) {
    Add-ScriptError "NextCheckDateはYYYY-MM-DD形式またはunknownである必要があります: $NextCheckDate"
}

Exit-OnErrors

# ---- フェーズ2: ファイル参照が必要な検証 ----

$resolvedWatchSourcesPath = Resolve-RepoPath $WatchSourcesPath
$resolvedWatchRunsPath = Resolve-RepoPath $WatchRunsPath
$researchQueuePath = Join-Path $repoRoot 'data/research/research_queue.csv'

if (-not (Test-Path $resolvedWatchSourcesPath)) {
    Add-ScriptError "watch_sources.csvが見つかりません: $resolvedWatchSourcesPath"
}
if (-not (Test-Path $resolvedWatchRunsPath)) {
    Add-ScriptError "watch_runs.csvが見つかりません: $resolvedWatchRunsPath"
}
Exit-OnErrors

$watchSourceRows = Read-CsvRows -Path $resolvedWatchSourcesPath
if ($watchSourceRows.Count -eq 0 -or -not (Test-CsvHeader -Actual $watchSourceRows[0].Fields -Expected $expectedWatchSourcesHeader)) {
    Add-ScriptError "watch_sources.csvのヘッダーが想定の15列と一致しません: $resolvedWatchSourcesPath"
    Exit-OnErrors
}

$sourceRow = $null
for ($i = 1; $i -lt $watchSourceRows.Count; $i++) {
    if ($watchSourceRows[$i].Fields.Count -ne 15) {
        Add-ScriptError "watch_sources.csvの$($watchSourceRows[$i].Line)行目が15列ではありません"
        continue
    }
    if ($watchSourceRows[$i].Fields[0] -eq $SourceId) {
        $sourceRow = $watchSourceRows[$i]
        break
    }
}
Exit-OnErrors

if ($null -eq $sourceRow) {
    Add-ScriptError "watch_sources.csvにSourceIdが存在しません: $SourceId"
    Exit-OnErrors
}

$organization = $sourceRow.Fields[1]
$checkFrequency = $sourceRow.Fields[9]
$existingLastChecked = $sourceRow.Fields[10]
$existingNextCheckDate = $sourceRow.Fields[11]

if ($checkFrequency -notin $allowedCheckFrequency) {
    Add-ScriptError "watch_sources.csvのcheck_frequencyが不正です（source_id=$SourceId）: $checkFrequency"
}
Exit-OnErrors

if ($QueueId -ne 'unknown') {
    if (-not (Test-Path $researchQueuePath)) {
        Add-ScriptError "research_queue.csvが見つかりません: $researchQueuePath"
    }
    else {
        $queueRows = Read-CsvRows -Path $researchQueuePath
        $queueIds = New-Object System.Collections.Generic.HashSet[string]
        for ($i = 1; $i -lt $queueRows.Count; $i++) {
            if ($queueRows[$i].Fields.Count -gt 0) { [void]$queueIds.Add($queueRows[$i].Fields[0]) }
        }
        if (-not $queueIds.Contains($QueueId)) {
            Add-ScriptError "research_queue.csvに存在しないQueueIdです: $QueueId"
        }
    }
}
Exit-OnErrors

$checkedDateStr = $CheckedAt.Substring(0, 10)
$checkedDate = ConvertTo-StrictDate $checkedDateStr

$isBackdated = $false
if ($existingLastChecked -ne 'unknown') {
    $existingLastCheckedDate = ConvertTo-StrictDate $existingLastChecked
    if ($checkedDate -lt $existingLastCheckedDate) {
        $isBackdated = $true
    }
}

if ($isBackdated -and -not $AllowBackdated) {
    Add-ScriptError "CheckedAt($checkedDateStr)が既存last_checked($existingLastChecked)より古いです。過去日時のログを追加する場合はAllowBackdatedを指定してください"
}
Exit-OnErrors

# ---- watch_runs.csv 読み込み・重複チェック・run_id採番・前回ハッシュ取得 ----

$watchRunRows = Read-CsvRows -Path $resolvedWatchRunsPath
if ($watchRunRows.Count -eq 0 -or -not (Test-CsvHeader -Actual $watchRunRows[0].Fields -Expected $expectedWatchRunsHeader)) {
    Add-ScriptError "watch_runs.csvのヘッダーが想定の18列と一致しません: $resolvedWatchRunsPath"
    Exit-OnErrors
}

$existingRunIds = New-Object System.Collections.Generic.HashSet[string]
$maxRunNumber = 0
$sourceRuns = New-Object System.Collections.Generic.List[object]

for ($i = 1; $i -lt $watchRunRows.Count; $i++) {
    $row = $watchRunRows[$i]
    if ($row.Fields.Count -ne 18) {
        Add-ScriptError "watch_runs.csvの$($row.Line)行目が18列ではありません"
        continue
    }
    $runId = $row.Fields[0]
    [void]$existingRunIds.Add($runId)
    if ($runId -match '^MWR-([0-9]{6})$') {
        $num = [int]$matches[1]
        if ($num -gt $maxRunNumber) { $maxRunNumber = $num }
    }
    if ($row.Fields[1] -eq $SourceId) {
        $sourceRuns.Add([PSCustomObject]@{
            CheckedAt   = $row.Fields[2]
            ContentHash = $row.Fields[7]
            FinalUrl    = $row.Fields[5]
        })
    }
}
Exit-OnErrors

if ($sourceRuns | Where-Object { $_.CheckedAt -eq $CheckedAt }) {
    Add-ScriptError "同じsource_idについて、CheckedAtが同一のrunが既に存在します（重複実行の可能性）: $CheckedAt"
}
Exit-OnErrors

$sortedSourceRuns = $sourceRuns | Sort-Object -Property @{ Expression = { [System.DateTimeOffset]::Parse($_.CheckedAt, [System.Globalization.CultureInfo]::InvariantCulture) } } -Descending

$previousContentHash = 'unknown'
foreach ($run in $sortedSourceRuns) {
    if ($run.ContentHash -ne 'unknown') {
        $previousContentHash = $run.ContentHash
        break
    }
}

$latestRun = $sortedSourceRuns | Select-Object -First 1

$newRunNumber = $maxRunNumber + 1
$runId = 'MWR-{0:D6}' -f $newRunNumber
if ($existingRunIds.Contains($runId)) {
    Add-ScriptError "採番したrun_idが既に存在します: $runId"
    Exit-OnErrors
}

# ---- 変更判定 ----

if ($CheckResult -eq '失敗') {
    $changeDetected = 'unknown'
    $changeType = '取得失敗'
}
elseif ($previousContentHash -eq 'unknown') {
    $changeDetected = 'unknown'
    $changeType = '初回確認'
}
elseif ($null -ne $latestRun -and $latestRun.FinalUrl -ne 'unknown' -and $FinalUrl -ne 'unknown' -and $latestRun.FinalUrl -ne $FinalUrl) {
    $changeDetected = 'true'
    $changeType = 'URL変更'
}
elseif ($ContentHash -eq 'unknown') {
    $changeDetected = 'unknown'
    $changeType = '判定不能'
}
elseif ($ContentHash -eq $previousContentHash) {
    $changeDetected = 'false'
    $changeType = '変更なし'
}
else {
    $changeDetected = 'true'
    $changeType = '内容変更'
}

if (($changeType -eq '内容変更' -or $changeType -eq 'URL変更') -and [string]::IsNullOrEmpty($ChangeSummary)) {
    Add-ScriptError "change_typeが「$changeType」の場合、ChangeSummaryを空欄にはできません"
}
Exit-OnErrors

# ---- 次回確認日の計算 ----

function Get-NextCheckDateValue {
    param([string]$BaseDateStr, [string]$Frequency)
    $baseDate = ConvertTo-StrictDate $BaseDateStr
    switch ($Frequency) {
        '毎日' { return $baseDate.AddDays(1).ToString('yyyy-MM-dd') }
        '週2回' { return $baseDate.AddDays(3).ToString('yyyy-MM-dd') }
        '毎週' { return $baseDate.AddDays(7).ToString('yyyy-MM-dd') }
        '隔週' { return $baseDate.AddDays(14).ToString('yyyy-MM-dd') }
        '毎月' { return $baseDate.AddMonths(1).ToString('yyyy-MM-dd') }
        '手動' { return 'unknown' }
    }
    return 'unknown'
}

if ($isBackdated) {
    $targetLastChecked = $existingLastChecked
    $targetNextCheckDate = $existingNextCheckDate
}
else {
    $targetLastChecked = $checkedDateStr
    if ($nextCheckDateExplicit) {
        $targetNextCheckDate = $NextCheckDate
    }
    else {
        $targetNextCheckDate = Get-NextCheckDateValue -BaseDateStr $checkedDateStr -Frequency $checkFrequency
    }
}

# ---- 書き込み内容の組み立て・列数検証 ----

$updatedSourceFields = @($sourceRow.Fields)
$updatedSourceFields[10] = $targetLastChecked
$updatedSourceFields[11] = $targetNextCheckDate
if ($updatedSourceFields.Count -ne 15) {
    Add-ScriptError "更新後のwatch_sources.csv行が15列ではありません"
}

$newRunFields = @(
    $runId, $SourceId, $CheckedAt, $CheckResult, $HttpStatus, $FinalUrl,
    $PageTitle, $ContentHash, $previousContentHash, $changeDetected, $changeType,
    $ChangeSummary, $MatchedKeywords, $QueueCandidateStatus, $QueueId, $CheckedBy,
    $HumanReviewed, $Notes
)
if ($newRunFields.Count -ne 18) {
    Add-ScriptError "追加するwatch_runs.csv行が18列ではありません"
}
Exit-OnErrors

# ---- 実行結果の表示 ----

function Write-RunSummary {
    Write-Output "Run ID: $runId"
    Write-Output "Source ID: $SourceId"
    Write-Output "Organization: $organization"
    Write-Output "Checked at: $CheckedAt"
    Write-Output "Check result: $CheckResult"
    Write-Output "Previous hash: $previousContentHash"
    Write-Output "Current hash: $ContentHash"
    Write-Output "Change detected: $changeDetected"
    Write-Output "Change type: $changeType"
    Write-Output "Old last checked: $existingLastChecked"
    Write-Output "New last checked: $targetLastChecked"
    Write-Output "Old next check: $existingNextCheckDate"
    Write-Output "New next check: $targetNextCheckDate"
    Write-Output "Queue candidate status: $QueueCandidateStatus"
    Write-Output "Dry run: $($DryRun.IsPresent)"
}

if ($DryRun) {
    Write-RunSummary
    exit 0
}

# ---- 安全な書き込み（一時ファイル・バックアップ・置換・検証） ----

$sourceRawLines = Get-RawLines -Path $resolvedWatchSourcesPath
$runsRawLines = Get-RawLines -Path $resolvedWatchRunsPath

$targetLineIndex = $sourceRow.Line - 1
if ($targetLineIndex -lt 0 -or $targetLineIndex -ge $sourceRawLines.Count) {
    Write-Output "エラー: watch_sources.csvの対象行位置を特定できませんでした"
    exit 1
}

$updatedSourceRawLines = @($sourceRawLines)
$updatedSourceRawLines[$targetLineIndex] = ConvertTo-CsvLine $updatedSourceFields

$updatedRunsRawLines = @($runsRawLines)
$updatedRunsRawLines += ConvertTo-CsvLine $newRunFields

$stamp = [DateTime]::Now.ToString('yyyyMMddHHmmssfff')
$tmpSourcesPath = "$resolvedWatchSourcesPath.tmp-$stamp"
$tmpRunsPath = "$resolvedWatchRunsPath.tmp-$stamp"
$backupSourcesPath = "$resolvedWatchSourcesPath.bak-$stamp"
$backupRunsPath = "$resolvedWatchRunsPath.bak-$stamp"

$restored = $false

try {
    Write-RawLines -Path $tmpSourcesPath -Lines $updatedSourceRawLines
    Write-RawLines -Path $tmpRunsPath -Lines $updatedRunsRawLines

    $tmpSourceRows = Read-CsvRows -Path $tmpSourcesPath
    $tmpRunRows = Read-CsvRows -Path $tmpRunsPath
    foreach ($r in $tmpSourceRows) {
        if ($r.Fields.Count -ne 15) { throw "一時watch_sources.csvの$($r.Line)行目が15列ではありません" }
    }
    foreach ($r in $tmpRunRows) {
        if ($r.Fields.Count -ne 18) { throw "一時watch_runs.csvの$($r.Line)行目が18列ではありません" }
    }

    Copy-Item -Path $resolvedWatchSourcesPath -Destination $backupSourcesPath -Force
    Copy-Item -Path $resolvedWatchRunsPath -Destination $backupRunsPath -Force

    Move-Item -Path $tmpSourcesPath -Destination $resolvedWatchSourcesPath -Force
    Move-Item -Path $tmpRunsPath -Destination $resolvedWatchRunsPath -Force

    $validationPassed = $true
    $validationOutput = @()

    if (-not $isCustomPath) {
        $validateScriptPath = Join-Path $repoRoot 'scripts\validate-data.ps1'
        $validationOutput = & powershell.exe -ExecutionPolicy Bypass -File $validateScriptPath 2>&1
        $validationPassed = ($LASTEXITCODE -eq 0)
    }

    if (-not $validationPassed) {
        Copy-Item -Path $backupSourcesPath -Destination $resolvedWatchSourcesPath -Force
        Copy-Item -Path $backupRunsPath -Destination $resolvedWatchRunsPath -Force
        $restored = $true
        Remove-Item -Path $backupSourcesPath, $backupRunsPath -Force -ErrorAction SilentlyContinue
        Write-Output 'Validation failed. watch_sources.csvとwatch_runs.csvをバックアップから復元しました。'
        foreach ($line in $validationOutput) { Write-Output $line }
        exit 1
    }

    Remove-Item -Path $backupSourcesPath, $backupRunsPath -Force -ErrorAction SilentlyContinue
}
catch {
    if (-not $restored) {
        if (Test-Path $backupSourcesPath) { Copy-Item -Path $backupSourcesPath -Destination $resolvedWatchSourcesPath -Force }
        if (Test-Path $backupRunsPath) { Copy-Item -Path $backupRunsPath -Destination $resolvedWatchRunsPath -Force }
        Remove-Item -Path $backupSourcesPath, $backupRunsPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $tmpSourcesPath, $tmpRunsPath -Force -ErrorAction SilentlyContinue
    Write-Output "エラー: 書き込みに失敗したため復元しました: $($_.Exception.Message)"
    exit 1
}

Write-RunSummary
Write-Output 'Watch run recorded successfully.'
exit 0
