[CmdletBinding()]
param(
    [string]$StateRoot,
    [string]$RimeUserDir,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { exit 0 }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'InputTranslate\windows-rime'
}
if (-not $RimeUserDir) {
    $RimeUserDir = ''
    try {
        $RimeUserDir = [string](Get-ItemPropertyValue -Path 'HKCU:\Software\Rime\Weasel' -Name 'RimeUserDir' -ErrorAction SilentlyContinue)
    } catch { $RimeUserDir = '' }
    if (-not $RimeUserDir) {
        if (-not $env:APPDATA) { exit 0 }
        $RimeUserDir = Join-Path $env:APPDATA 'Rime'
    }
}

$StateRoot = [System.IO.Path]::GetFullPath($StateRoot)
$RimeUserDir = [System.IO.Path]::GetFullPath($RimeUserDir)
$ConfigPath = Join-Path $StateRoot 'deepseek-config.json'
$KeyPath = Join-Path $StateRoot 'deepseek.key.dpapi'
$StopPath = Join-Path $StateRoot 'worker.stop'
$LogPath = Join-Path $StateRoot 'worker.log'
$QueuePath = Join-Path $RimeUserDir 'input_translate_missing.txt'
$CachePath = Join-Path $RimeUserDir 'input_translate_ai_cache.tsv'
$VersionPath = Join-Path $RimeUserDir 'input_translate_ai_cache.version'
$EnglishQueuePath = Join-Path $RimeUserDir 'input_translate_english_missing.txt'
$ChineseCachePath = Join-Path $RimeUserDir 'input_translate_ai_chinese_cache.tsv'
$ChineseVersionPath = Join-Path $RimeUserDir 'input_translate_ai_chinese_cache.version'
$EnabledPath = Join-Path $RimeUserDir 'input_translate_ai_enabled'
$OfflineDictionaryPath = Join-Path $RimeUserDir 'bilingual_english.tsv'
$MaxBatchSize = 12
$DebounceMilliseconds = 500

function Write-WorkerLog {
    param([string]$Message)
    try {
        if (Test-Path -LiteralPath $LogPath) {
            $item = Get-Item -LiteralPath $LogPath
            if ($item.Length -gt 65536) {
                Move-Item -LiteralPath $LogPath -Destination ($LogPath + '.old') -Force
            }
        }
        Add-Content -LiteralPath $LogPath -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    } catch { }
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    try { return (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Read-ProtectedSecret {
    if (-not (Test-Path -LiteralPath $KeyPath)) { return '' }
    $pointer = [IntPtr]::Zero
    try {
        $encrypted = (Get-Content -LiteralPath $KeyPath -Raw -Encoding ASCII).Trim()
        if (-not $encrypted) { return '' }
        $secure = ConvertTo-SecureString $encrypted
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } catch {
        return ''
    } finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function Test-HanTerm {
    param([string]$Text)
    if (-not $Text -or $Text.Length -gt 16 -or $Text -match "[\t\r\n]") { return $false }
    $count = 0
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $codepoint = [char]::ConvertToUtf32($Text, $index)
        if ($codepoint -gt 0xFFFF) { $index++ }
        $isHan = ($codepoint -ge 0x3400 -and $codepoint -le 0x4DBF) -or
            ($codepoint -ge 0x4E00 -and $codepoint -le 0x9FFF) -or
            ($codepoint -ge 0xF900 -and $codepoint -le 0xFAFF) -or
            ($codepoint -ge 0x20000 -and $codepoint -le 0x2CEAF) -or
            $codepoint -eq 0x3007
        if (-not $isHan) { return $false }
        $count++
    }
    return $count -gt 0 -and $count -le 8
}

function Test-EnglishTerm {
    param([string]$Text)
    return [bool]($Text -and $Text.Length -le 30 -and $Text -cmatch "^[a-z][a-z'-]*$")
}

function Format-Gloss {
    param([string]$Text)
    if (-not $Text) { return '' }
    $value = [regex]::Replace($Text, '\s+', ' ').Trim()
    $value = [regex]::Replace($value, '\s*\([^)]*\)', '').Trim()
    if ($value.Contains(';')) { $value = $value.Split(';')[0].Trim() }
    if ($value.Length -gt 24 -and $value.Contains(',')) { $value = $value.Split(',')[0].Trim() }
    if ($value.Length -gt 24) {
        $prefix = $value.Substring(0, 24)
        $boundary = $prefix.LastIndexOf(' ')
        if ($boundary -ge 8) { $value = $prefix.Substring(0, $boundary) }
        else { $value = $prefix }
    }
    $value = $value.Trim(' ', ',', ';', ':', '.', '-')
    if ($value -notmatch '[A-Za-z]' -or $value -match '[\u3400-\u9FFF]') { return '' }
    return $value
}

function Format-ChineseGloss {
    param([string]$Text)
    if (-not $Text) { return '' }
    $value = [regex]::Replace($Text, '\s+', '').Trim()
    if ($value.Contains('；')) { $value = $value.Split('；')[0] }
    if ($value.Contains(';')) { $value = $value.Split(';')[0] }
    if ($value.Contains('，')) { $value = $value.Split('，')[0] }
    if ($value.Contains(',')) { $value = $value.Split(',')[0] }
    if ($value.Length -gt 6) { $value = $value.Substring(0, 6) }
    if ($value -notmatch '[\u3400-\u9FFF]' -or $value -match '[A-Za-z\t\r\n]') { return '' }
    return $value
}

function Read-Cache {
    param([string]$Path = $CachePath)
    $mapping = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $mapping }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $parts = $line.Split("`t", 2)
        if ($parts.Count -eq 2 -and -not $mapping.ContainsKey($parts[0])) {
            $mapping[$parts[0]] = $parts[1]
        }
    }
    return $mapping
}

function Write-Cache {
    param(
        [hashtable]$Mapping,
        [string]$Path = $CachePath,
        [string]$CacheVersionPath = $VersionPath,
        [string]$Header = '# Simplified Chinese | short English gloss; generated locally through the user configured API.'
    )
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add($Header)
    foreach ($key in ($Mapping.Keys | Sort-Object)) {
        [void]$lines.Add("$key`t$($Mapping[$key])")
    }
    $temporary = $Path + '.tmp.' + $PID
    [System.IO.File]::WriteAllLines($temporary, $lines, $Utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
    [System.IO.File]::WriteAllText($CacheVersionPath, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString(), $Utf8NoBom)
}

function Append-Queue {
    param(
        [string[]]$Terms,
        [string]$Path = $QueuePath
    )
    if (-not $Terms -or $Terms.Count -eq 0) { return }
    $content = (($Terms | Select-Object -Unique) -join "`n") + "`n"
    [System.IO.File]::AppendAllText($Path, $content, $Utf8NoBom)
}

function Read-Queue {
    param([string]$Path)
    $unique = @{}
    $terms = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Path)) { return $terms.ToArray() }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        $term = $line.Trim()
        if ((Test-HanTerm $term) -and -not $unique.ContainsKey($term)) {
            $unique[$term] = $true
            $terms.Add($term)
        }
    }
    return $terms.ToArray()
}

function Read-EnglishQueue {
    param([string]$Path)
    $unique = @{}
    $terms = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Path)) { return $terms.ToArray() }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        $term = $line.Trim().ToLowerInvariant()
        if ((Test-EnglishTerm $term) -and -not $unique.ContainsKey($term)) {
            $unique[$term] = $true
            $terms.Add($term)
        }
    }
    return $terms.ToArray()
}

function Invoke-DeepSeekTranslation {
    param(
        [string[]]$Terms,
        [string]$Secret,
        [string]$Endpoint,
        [string]$Model
    )

    $systemPrompt = @'
You compile concise English glosses for a Simplified Chinese input method.
Return JSON only in this exact shape: {"translations":[{"source":"中文","english":"short gloss"}]}.
For every supplied source term, return exactly one common dictionary meaning in natural English.
Use 1 to 4 English words and at most 24 ASCII characters. No explanations, parentheses, pinyin, articles about the task, or full sentences. Preserve every source string exactly.
'@
    $userPayload = @{ terms = @($Terms) } | ConvertTo-Json -Compress
    $body = [ordered]@{
        model = $Model
        messages = @(
            [ordered]@{ role = 'system'; content = $systemPrompt },
            [ordered]@{ role = 'user'; content = $userPayload }
        )
        thinking = [ordered]@{ type = 'disabled' }
        response_format = [ordered]@{ type = 'json_object' }
        temperature = 0.1
        max_tokens = 512
        stream = $false
    } | ConvertTo-Json -Depth 8 -Compress

    # Windows PowerShell 5.1 may decode application/json as Latin-1 when the
    # server omits a charset. Read the response bytes ourselves so Chinese
    # source terms always round-trip as UTF-8 and still match the local queue.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($Endpoint)
    $request.Method = 'POST'
    $request.ContentType = 'application/json; charset=utf-8'
    $request.Accept = 'application/json'
    $request.Headers['Authorization'] = "Bearer $Secret"
    $request.Timeout = 15000
    $request.ReadWriteTimeout = 15000
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
    $request.ContentLength = $bodyBytes.Length
    $requestStream = $null
    $webResponse = $null
    $responseStream = $null
    $memory = $null
    try {
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Close()
        $requestStream = $null

        $webResponse = $request.GetResponse()
        $responseStream = $webResponse.GetResponseStream()
        $memory = New-Object System.IO.MemoryStream
        $responseStream.CopyTo($memory)
        $responseText = [Text.Encoding]::UTF8.GetString($memory.ToArray())
    } finally {
        if ($requestStream) { $requestStream.Dispose() }
        if ($responseStream) { $responseStream.Dispose() }
        if ($memory) { $memory.Dispose() }
        if ($webResponse) { $webResponse.Dispose() }
    }
    $response = $responseText | ConvertFrom-Json

    $content = [string]$response.choices[0].message.content
    if (-not $content) { throw 'Empty API response.' }
    $content = $content.Trim()
    if ($content.StartsWith('```')) {
        $content = [regex]::Replace($content, '^```(?:json)?\s*|\s*```$', '')
    }
    $root = $content | ConvertFrom-Json
    $requested = @{}
    foreach ($term in $Terms) { $requested[$term] = $true }
    $results = @{}
    foreach ($item in @($root.translations)) {
        $source = [string]$item.source
        $english = Format-Gloss ([string]$item.english)
        if ($requested.ContainsKey($source) -and $english) {
            $results[$source] = $english
        }
    }
    return $results
}

function Invoke-DeepSeekChineseGloss {
    param(
        [string[]]$Terms,
        [string]$Secret,
        [string]$Endpoint,
        [string]$Model
    )

    $systemPrompt = @'
You compile concise Simplified Chinese glosses for English words in an input method.
Return JSON only in this exact shape: {"translations":[{"source":"english","chinese":"简短释义"}]}.
For every supplied source word, return exactly one common everyday meaning in Simplified Chinese.
Use 1 to 6 Chinese characters. No explanations, parentheses, pinyin, labels, or full sentences. Preserve every lowercase source string exactly.
'@
    $userPayload = @{ terms = @($Terms) } | ConvertTo-Json -Compress
    $body = [ordered]@{
        model = $Model
        messages = @(
            [ordered]@{ role = 'system'; content = $systemPrompt },
            [ordered]@{ role = 'user'; content = $userPayload }
        )
        thinking = [ordered]@{ type = 'disabled' }
        response_format = [ordered]@{ type = 'json_object' }
        temperature = 0.1
        max_tokens = 512
        stream = $false
    } | ConvertTo-Json -Depth 8 -Compress

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($Endpoint)
    $request.Method = 'POST'
    $request.ContentType = 'application/json; charset=utf-8'
    $request.Accept = 'application/json'
    $request.Headers['Authorization'] = "Bearer $Secret"
    $request.Timeout = 15000
    $request.ReadWriteTimeout = 15000
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
    $request.ContentLength = $bodyBytes.Length
    $requestStream = $null
    $webResponse = $null
    $responseStream = $null
    $memory = $null
    try {
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Close()
        $requestStream = $null

        $webResponse = $request.GetResponse()
        $responseStream = $webResponse.GetResponseStream()
        $memory = New-Object System.IO.MemoryStream
        $responseStream.CopyTo($memory)
        $responseText = [Text.Encoding]::UTF8.GetString($memory.ToArray())
    } finally {
        if ($requestStream) { $requestStream.Dispose() }
        if ($responseStream) { $responseStream.Dispose() }
        if ($memory) { $memory.Dispose() }
        if ($webResponse) { $webResponse.Dispose() }
    }
    $response = $responseText | ConvertFrom-Json
    $content = [string]$response.choices[0].message.content
    if (-not $content) { throw 'Empty API response.' }
    $content = $content.Trim()
    if ($content.StartsWith('```')) {
        $content = [regex]::Replace($content, '^```(?:json)?\s*|\s*```$', '')
    }
    $root = $content | ConvertFrom-Json
    $requested = @{}
    foreach ($term in $Terms) { $requested[$term] = $true }
    $results = @{}
    foreach ($item in @($root.translations)) {
        $source = ([string]$item.source).ToLowerInvariant()
        $chinese = Format-ChineseGloss ([string]$item.chinese)
        if ($requested.ContainsKey($source) -and $chinese) {
            $results[$source] = $chinese
        }
    }
    return $results
}

New-Item -ItemType Directory -Force -Path $StateRoot, $RimeUserDir | Out-Null
$config = Read-Config
if ($null -eq $config -or -not [bool]$config.enabled -or -not (Test-Path -LiteralPath $EnabledPath)) { exit 0 }
$secret = Read-ProtectedSecret
if (-not $secret) { exit 0 }
$endpoint = if ($config.endpoint) { [string]$config.endpoint } else { 'https://api.deepseek.com/chat/completions' }
$model = if ($config.model) { [string]$config.model } else { 'deepseek-v4-flash' }
$offlineDictionary = Read-Cache -Path $OfflineDictionaryPath

$mutexCreated = $false
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    $stateHashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($StateRoot.ToLowerInvariant()))
    $stateId = ([Convert]::ToBase64String($stateHashBytes) -replace '[^A-Za-z0-9]', '').Substring(0, 16)
} finally {
    $sha256.Dispose()
}
$mutexName = 'Local\InputTranslateDeepSeekWorker_' + [Environment]::UserName.Replace('\', '_') + '_' + $stateId
$mutex = New-Object Threading.Mutex($true, $mutexName, [ref]$mutexCreated)
if (-not $mutexCreated) { $mutex.Dispose(); exit 0 }

try {
    $staleChinese = Get-ChildItem -LiteralPath $RimeUserDir -Filter 'input_translate_missing.work.*' -File -ErrorAction SilentlyContinue
    foreach ($item in $staleChinese) {
        Append-Queue -Terms (Read-Queue $item.FullName) -Path $QueuePath
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
    }
    $staleEnglish = Get-ChildItem -LiteralPath $RimeUserDir -Filter 'input_translate_english_missing.work.*' -File -ErrorAction SilentlyContinue
    foreach ($item in $staleEnglish) {
        Append-Queue -Terms (Read-EnglishQueue $item.FullName) -Path $EnglishQueuePath
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-WorkerLog 'Worker started.'

    do {
        if (Test-Path -LiteralPath $StopPath) { break }

        $job = $null
        $jobs = @(
            [ordered]@{
                Direction = 'zh-en'; Queue = $QueuePath; Cache = $CachePath; Version = $VersionPath
                WorkName = "input_translate_missing.work.$PID"
            },
            [ordered]@{
                Direction = 'en-zh'; Queue = $EnglishQueuePath; Cache = $ChineseCachePath; Version = $ChineseVersionPath
                WorkName = "input_translate_english_missing.work.$PID"
            }
        )
        foreach ($candidateJob in $jobs) {
            if (-not (Test-Path -LiteralPath $candidateJob.Queue)) { continue }
            $queueInfo = Get-Item -LiteralPath $candidateJob.Queue -ErrorAction SilentlyContinue
            if ($null -ne $queueInfo -and ((Get-Date) - $queueInfo.LastWriteTime).TotalMilliseconds -ge $DebounceMilliseconds) {
                $job = $candidateJob
                break
            }
        }
        if ($null -eq $job) {
            if ($Once) { break }
            Start-Sleep -Milliseconds 250
            continue
        }

        $workPath = Join-Path $RimeUserDir $job.WorkName
        try { Move-Item -LiteralPath $job.Queue -Destination $workPath -Force }
        catch {
            if ($Once) { break }
            Start-Sleep -Milliseconds 250
            continue
        }

        $cache = Read-Cache -Path $job.Cache
        $queuedTerms = if ($job.Direction -eq 'zh-en') { Read-Queue $workPath } else { Read-EnglishQueue $workPath }
        if ($job.Direction -eq 'zh-en') {
            $pending = @($queuedTerms | Where-Object {
                -not $cache.ContainsKey($_) -and -not $offlineDictionary.ContainsKey($_)
            })
        } else {
            $pending = @($queuedTerms | Where-Object { -not $cache.ContainsKey($_) })
        }
        Remove-Item -LiteralPath $workPath -Force -ErrorAction SilentlyContinue
        if ($pending.Count -eq 0) {
            if ($Once) { break }
            continue
        }

        $batch = @($pending | Select-Object -First $MaxBatchSize)
        $remainder = @($pending | Select-Object -Skip $MaxBatchSize)
        if ($remainder.Count -gt 0) { Append-Queue -Terms $remainder -Path $job.Queue }

        try {
            if ($job.Direction -eq 'zh-en') {
                $translated = Invoke-DeepSeekTranslation -Terms $batch -Secret $secret -Endpoint $endpoint -Model $model
            } else {
                $translated = Invoke-DeepSeekChineseGloss -Terms $batch -Secret $secret -Endpoint $endpoint -Model $model
            }
            foreach ($term in $translated.Keys) { $cache[$term] = $translated[$term] }
            if ($translated.Count -gt 0) {
                $header = if ($job.Direction -eq 'zh-en') {
                    '# Simplified Chinese | short English gloss; generated locally through the user configured API.'
                } else {
                    '# English word | short Simplified Chinese gloss; generated locally through the user configured API.'
                }
                Write-Cache -Mapping $cache -Path $job.Cache -CacheVersionPath $job.Version -Header $header
            }
            Write-WorkerLog ("Translated {0} of {1} queued {2} terms." -f $translated.Count, $batch.Count, $job.Direction)
        } catch {
            Append-Queue -Terms $batch -Path $job.Queue
            Write-WorkerLog ("API request failed for {0} ({1}); queued terms retained." -f $job.Direction, $_.Exception.GetType().Name)
            if (-not $Once) { Start-Sleep -Seconds 60 }
        }

        if ($Once) { break }
    } while ($true)
} finally {
    Write-WorkerLog 'Worker stopped.'
    if ($mutexCreated) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
