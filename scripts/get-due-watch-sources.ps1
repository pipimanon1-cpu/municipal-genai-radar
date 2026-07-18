# scripts/get-due-watch-sources.ps1
# data/research/watch_sources.csv から、確認予定日が本日以前（超過・本日を含む）の
# 有効な監視ソースを抽出する。Webページへのアクセス・差分検出・research_queueへの
# 登録は行わない。
# 実行: powershell -ExecutionPolicy Bypass -File scripts/get-due-watch-sources.ps1

param(
    [string]$InputPath = 'data/research/watch_sources.csv',
    [string]$TargetDate,
    [string]$OutputPath,
    [string]$Priority,
    [switch]$IncludeInactive
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

$repoRoot = Split-Path -Parent $PSScriptRoot

$canonicalColumns = @(
    'source_id', 'organization', 'prefecture', 'municipality_type', 'source_name',
    'source_url', 'source_type', 'watch_scope', 'keywords', 'check_frequency',
    'last_checked', 'next_check_date', 'is_active', 'priority', 'notes'
)
$allowedPriority = @('高', '中', '低')
$priorityOrder = @{ '高' = 0; '中' = 1; '低' = 2 }

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

function Resolve-InputPath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
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

# ---- パラメータ検証 ----

if ($PSBoundParameters.ContainsKey('Priority')) {
    if ($Priority -notin $allowedPriority) {
        Write-Output "エラー: Priorityの値が不正です: $Priority（高・中・低のいずれかを指定してください）"
        exit 1
    }
}

if ($PSBoundParameters.ContainsKey('TargetDate')) {
    if (-not (Test-StrictDate $TargetDate)) {
        Write-Output "エラー: TargetDateの形式が不正です: $TargetDate（YYYY-MM-DD形式で指定してください）"
        exit 1
    }
    $targetDateStr = $TargetDate
}
else {
    $targetDateStr = Get-Date -Format 'yyyy-MM-dd'
}
$targetDateValue = ConvertTo-StrictDate $targetDateStr

# ---- 入力ファイルの検証 ----

$resolvedInputPath = Resolve-InputPath -Path $InputPath

if (-not (Test-Path $resolvedInputPath)) {
    Write-Output "エラー: 入力ファイルが見つかりません: $resolvedInputPath"
    exit 1
}

$rows = Read-CsvRows -Path $resolvedInputPath

if ($rows.Count -eq 0) {
    Write-Output "エラー: ヘッダーが存在しません: $resolvedInputPath"
    exit 1
}

$headerRow = $rows[0]
$missingColumns = $canonicalColumns | Where-Object { $_ -notin $headerRow.Fields }
if ($missingColumns.Count -gt 0) {
    Write-Output "エラー: 必須列が不足しています: $($missingColumns -join ', ')"
    exit 1
}

$columnIndex = @{}
for ($i = 0; $i -lt $headerRow.Fields.Count; $i++) {
    $columnIndex[$headerRow.Fields[$i]] = $i
}
$expectedFieldCount = $headerRow.Fields.Count

$sources = New-Object System.Collections.Generic.List[object]

for ($i = 1; $i -lt $rows.Count; $i++) {
    $row = $rows[$i]
    $f = $row.Fields

    if ($f.Count -ne $expectedFieldCount) {
        Write-Output "エラー: $($row.Line)行目の列数がヘッダーと一致しません（期待: $expectedFieldCount, 実際: $($f.Count)）"
        exit 1
    }

    $sourceId = $f[$columnIndex['source_id']]
    if ([string]::IsNullOrEmpty($sourceId)) {
        Write-Output "エラー: $($row.Line)行目のsource_idが空欄です"
        exit 1
    }

    $isActive = $f[$columnIndex['is_active']]
    if ($isActive -notin @('true', 'false')) {
        Write-Output "エラー: source_id=$sourceId のis_activeが不正です: $isActive"
        exit 1
    }

    $priorityValue = $f[$columnIndex['priority']]
    if ($priorityValue -notin $allowedPriority) {
        Write-Output "エラー: source_id=$sourceId のpriorityが不正です: $priorityValue"
        exit 1
    }

    $nextCheckDate = $f[$columnIndex['next_check_date']]
    if ($nextCheckDate -ne 'unknown' -and -not (Test-StrictDate $nextCheckDate)) {
        Write-Output "エラー: source_id=$sourceId のnext_check_dateが不正です: $nextCheckDate"
        exit 1
    }

    $sources.Add([PSCustomObject]@{
        SourceId         = $sourceId
        Organization     = $f[$columnIndex['organization']]
        Prefecture       = $f[$columnIndex['prefecture']]
        MunicipalityType = $f[$columnIndex['municipality_type']]
        SourceName       = $f[$columnIndex['source_name']]
        SourceUrl        = $f[$columnIndex['source_url']]
        SourceType       = $f[$columnIndex['source_type']]
        WatchScope       = $f[$columnIndex['watch_scope']]
        Keywords         = $f[$columnIndex['keywords']]
        CheckFrequency   = $f[$columnIndex['check_frequency']]
        LastChecked      = $f[$columnIndex['last_checked']]
        NextCheckDate    = $nextCheckDate
        IsActive         = $isActive
        Priority         = $priorityValue
        Notes            = $f[$columnIndex['notes']]
    })
}

# ---- 集計対象の絞り込み ----

$watchSourcesCount = $sources.Count
$activeSourcesCount = ($sources | Where-Object { $_.IsActive -eq 'true' }).Count

$scopedSources = if ($IncludeInactive) { $sources } else { $sources | Where-Object { $_.IsActive -eq 'true' } }
if ($PSBoundParameters.ContainsKey('Priority')) {
    $scopedSources = $scopedSources | Where-Object { $_.Priority -eq $Priority }
}

$overdueSources = @($scopedSources | Where-Object { $_.NextCheckDate -ne 'unknown' -and (ConvertTo-StrictDate $_.NextCheckDate) -lt $targetDateValue })
$dueTodaySources = @($scopedSources | Where-Object { $_.NextCheckDate -ne 'unknown' -and (ConvertTo-StrictDate $_.NextCheckDate) -eq $targetDateValue })
$futureSources = @($scopedSources | Where-Object { $_.NextCheckDate -ne 'unknown' -and (ConvertTo-StrictDate $_.NextCheckDate) -gt $targetDateValue })
$unscheduledSources = @($scopedSources | Where-Object { $_.NextCheckDate -eq 'unknown' })

$dueSources = @($overdueSources + $dueTodaySources) | Sort-Object -Property `
    @{ Expression = { $priorityOrder[$_.Priority] } }, `
    @{ Expression = { ConvertTo-StrictDate $_.NextCheckDate } }, `
    @{ Expression = { $_.SourceId } }

# ---- コンソール表示 ----

Write-Output "Watch sources: $watchSourcesCount"
Write-Output "Active sources: $activeSourcesCount"
Write-Output "Due sources: $($dueSources.Count)"
Write-Output "Overdue: $($overdueSources.Count)"
Write-Output "Due today: $($dueTodaySources.Count)"
Write-Output "Future: $($futureSources.Count)"
Write-Output "Unscheduled active: $($unscheduledSources.Count)"
Write-Output "Target date: $targetDateStr"

if ($dueSources.Count -eq 0) {
    Write-Output '確認対象はありません。'
}
else {
    Write-Output '確認対象:'
    $tableText = $dueSources | Format-Table -AutoSize -Wrap -Property @(
        @{ Label = 'source_id'; Expression = { $_.SourceId } },
        @{ Label = 'organization'; Expression = { $_.Organization } },
        @{ Label = 'source_name'; Expression = { $_.SourceName } },
        @{ Label = 'priority'; Expression = { $_.Priority } },
        @{ Label = 'next_check_date'; Expression = { $_.NextCheckDate } },
        @{ Label = 'watch_scope'; Expression = { $_.WatchScope } },
        @{ Label = 'source_url'; Expression = { $_.SourceUrl } }
    ) | Out-String -Width 4096
    Write-Output $tableText.TrimEnd()
}

# ---- CSV出力 ----

if ($PSBoundParameters.ContainsKey('OutputPath')) {
    $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outputDir = Split-Path -Parent $resolvedOutputPath
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((ConvertTo-CsvLine $canonicalColumns))
    foreach ($s in $dueSources) {
        $lines.Add((ConvertTo-CsvLine @(
            $s.SourceId, $s.Organization, $s.Prefecture, $s.MunicipalityType, $s.SourceName,
            $s.SourceUrl, $s.SourceType, $s.WatchScope, $s.Keywords, $s.CheckFrequency,
            $s.LastChecked, $s.NextCheckDate, $s.IsActive, $s.Priority, $s.Notes
        )))
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($resolvedOutputPath, $lines, $utf8NoBom)
}

exit 0
