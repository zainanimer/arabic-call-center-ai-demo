param([int]$Port = 8000, [switch]$OpenBrowser)
# the assistant AI Demo - local server + ElevenLabs proxy (Speech-to-Text for Agent Assist, TTS for Training).
# Start it with Start-Demo.bat (that file holds the API key and bypasses the PowerShell script policy).
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ---------------- API key ----------------
# Order: key in Start-Demo.bat -> saved key file next to this script -> ask once (visible, paste works) and save it.
$keyFile = Join-Path $base 'elevenlabs-key.txt'
function Clean-Key([string]$k) { if (-not $k) { return '' } return (($k -replace '[\x00-\x20\x7F"'']', '')).Trim() }
function Test-Key([string]$k) { return ($k -and $k.Length -ge 20 -and $k -notlike 'PASTE_*') }
$apiKey = Clean-Key $env:ELEVENLABS_API_KEY
if (-not (Test-Key $apiKey) -and (Test-Path -LiteralPath $keyFile)) {
  $apiKey = Clean-Key ([IO.File]::ReadAllText($keyFile))
  if (Test-Key $apiKey) { Write-Host 'Using the ElevenLabs key saved in elevenlabs-key.txt' -ForegroundColor DarkGray }
}
while (-not (Test-Key $apiKey)) {
  Write-Host ''
  Write-Host 'Paste your ElevenLabs API key below (it starts with sk_), then press Enter.' -ForegroundColor Yellow
  Write-Host 'Tip: right-click inside this window to paste, or press Ctrl+V.' -ForegroundColor DarkGray
  $apiKey = Clean-Key (Read-Host 'API key')
  if (-not (Test-Key $apiKey)) {
    Write-Host "That does not look like a full ElevenLabs key ($($apiKey.Length) characters). Copy it again from ElevenLabs > Developers > API Keys." -ForegroundColor Red
  } else {
    [IO.File]::WriteAllText($keyFile, $apiKey)
    Write-Host 'Key saved to elevenlabs-key.txt in the demo folder, you will not be asked again. Delete that file to change the key.' -ForegroundColor Green
  }
}
# ---------------- Google Gemini key (FREE tier, no credit card): writes the answer to every customer line ----------------
$geminiKeyFile = Join-Path $base 'gemini-key.txt'
function Test-GeminiKey([string]$k) { return ($k -and $k.Length -ge 30 -and $k -notlike 'PASTE_*') }
$geminiKey = Clean-Key $env:GEMINI_API_KEY
if (-not (Test-GeminiKey $geminiKey) -and (Test-Path -LiteralPath $geminiKeyFile)) { $geminiKey = Clean-Key ([IO.File]::ReadAllText($geminiKeyFile)) }
if (-not (Test-GeminiKey $geminiKey) -and $env:DEMO_SKIP_GEMINI -ne '1') {
  Write-Host ''
  Write-Host 'FREE AI answers for ANY call: paste a Google Gemini API key (free, no credit card).' -ForegroundColor Yellow
  Write-Host 'Get it at https://aistudio.google.com/apikey  (Create API key). It usually starts with AIza.' -ForegroundColor DarkGray
  Write-Host 'Right-click to paste, then Enter. Press Enter on its own to skip.' -ForegroundColor DarkGray
  for ($i = 0; $i -lt 3; $i++) {
    $geminiKey = Clean-Key (Read-Host 'Gemini API key')
    if (-not $geminiKey) { break }
    if (Test-GeminiKey $geminiKey) { [IO.File]::WriteAllText($geminiKeyFile, $geminiKey); Write-Host 'Gemini key saved to gemini-key.txt.' -ForegroundColor Green; break }
    Write-Host "That does not look like a full Gemini key ($($geminiKey.Length) characters)." -ForegroundColor Red
  }
}
if (-not (Test-GeminiKey $geminiKey)) { $geminiKey = '' }
$geminiBase = [string]$env:GEMINI_BASE_URL; if ([string]::IsNullOrWhiteSpace($geminiBase)) { $geminiBase = 'https://generativelanguage.googleapis.com' }; $geminiBase = $geminiBase.TrimEnd('/')
$script:geminiModels = @(); if ($env:GEMINI_MODEL) { $script:geminiModels = @((Clean-Key $env:GEMINI_MODEL)) }

# ---------------- Claude (Anthropic) key: writes the agent's answer for every customer question ----------------
$claudeKeyFile = Join-Path $base 'anthropic-key.txt'
function Test-ClaudeKey([string]$k) { return ($k -and $k.Length -ge 30 -and $k -like 'sk-ant-*') }
$claudeKey = Clean-Key $env:ANTHROPIC_API_KEY
if (-not (Test-ClaudeKey $claudeKey) -and (Test-Path -LiteralPath $claudeKeyFile)) { $claudeKey = Clean-Key ([IO.File]::ReadAllText($claudeKeyFile)) }
if (-not (Test-ClaudeKey $claudeKey) -and $env:DEMO_ASK_CLAUDE -eq '1') {
  Write-Host ''
  Write-Host 'Optional: paste your Anthropic Claude API key (starts with sk-ant-) so the assistant writes a real answer to every customer question.' -ForegroundColor Yellow
  Write-Host 'Right-click to paste, then Enter. Press Enter on its own to skip (keyword answers only).' -ForegroundColor DarkGray
  for ($i = 0; $i -lt 3; $i++) {
    $claudeKey = Clean-Key (Read-Host 'Claude API key')
    if (-not $claudeKey) { break }
    if (Test-ClaudeKey $claudeKey) { [IO.File]::WriteAllText($claudeKeyFile, $claudeKey); Write-Host 'Claude key saved to anthropic-key.txt.' -ForegroundColor Green; break }
    Write-Host "That does not look like a Claude key ($($claudeKey.Length) characters, should start with sk-ant-)." -ForegroundColor Red
  }
}
if (-not (Test-ClaudeKey $claudeKey)) { $claudeKey = '' }
$script:claudeModel = Clean-Key $env:ANTHROPIC_MODEL
$aiProvider = if ($geminiKey) { 'gemini' } elseif ($claudeKey) { 'claude' } else { '' }
$claudeBase = [string]$env:ANTHROPIC_BASE_URL; if ([string]::IsNullOrWhiteSpace($claudeBase)) { $claudeBase = 'https://api.anthropic.com' }; $claudeBase = $claudeBase.TrimEnd('/')
$keyHint = if ($apiKey.Length -ge 4) { '...' + $apiKey.Substring($apiKey.Length - 4) } else { 'set' }

$voiceId = [string]$env:ELEVENLABS_VOICE_ID
if ([string]::IsNullOrWhiteSpace($voiceId)) { $voiceId = '21m00Tcm4TlvDq8ikWAM' }
$sttModel = [string]$env:ELEVENLABS_STT_MODEL
if ([string]::IsNullOrWhiteSpace($sttModel)) { $sttModel = 'scribe_v2' }
$sttLanguage = [string]$env:ELEVENLABS_STT_LANGUAGE   # e.g. ar  (empty = auto-detect)
$numSpeakers = [string]$env:ELEVENLABS_NUM_SPEAKERS   # e.g. 2   (empty = auto)
$apiBase = [string]$env:ELEVENLABS_BASE_URL            # optional, e.g. https://api.eu.residency.elevenlabs.io
if ([string]::IsNullOrWhiteSpace($apiBase)) { $apiBase = 'https://api.elevenlabs.io' }
$apiBase = $apiBase.TrimEnd('/')

# ---------------- curl.exe + network ----------------
$curlCmd = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue
if (-not $curlCmd) { $curlCmd = Get-Command curl -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not $curlCmd) { throw 'curl.exe was not found. It ships with Windows 10 (1803+) and Windows 11.' }
$curlPath = $curlCmd.Source
$tmpDir = [IO.Path]::GetTempPath()
$cacheDir = Join-Path $base 'transcripts'

# curl.exe does NOT use the Windows proxy automatically. Pick it up (env var first, then system/PAC proxy).
$proxyArgs = @()
$proxy = $env:HTTPS_PROXY; if (-not $proxy) { $proxy = $env:https_proxy }
if (-not $proxy) {
  try {
    $target = [Uri]($apiBase + '/')
    $p = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($target)
    if ($p -and $p.AbsoluteUri -ne $target.AbsoluteUri) { $proxy = $p.AbsoluteUri }
  } catch {}
}
if ($proxy) { $proxyArgs = @('-x', $proxy, '--proxy-anyauth', '--proxy-user', ':') }
$script:noRevoke = ($env:DEMO_SSL_NO_REVOKE -eq '1')

function Invoke-Eleven([string[]]$requestArgs) {
  $id = [Guid]::NewGuid().ToString('N')
  $respFile = Join-Path $tmpDir ("demo-resp-$id.bin")
  $errFile = Join-Path $tmpDir ("demo-err-$id.txt")
  try {
    for ($attempt = 1; $attempt -le 2; $attempt++) {
      $all = @('-sS', '--http1.1', '--connect-timeout', '20', '--max-time', '300',
               '-H', ('xi-api-key: ' + $apiKey), '-o', $respFile, '--stderr', $errFile, '-w', '%{http_code}') + $proxyArgs
      if ($script:noRevoke) { $all += '--ssl-no-revoke' }
      $all += $requestArgs
      $codeText = & $curlPath @all
      $exit = $LASTEXITCODE
      $status = 0; [void][int]::TryParse(([string]$codeText).Trim(), [ref]$status)
      $err = if (Test-Path $errFile) { ([IO.File]::ReadAllText($errFile)).Trim() } else { '' }
      # Corporate SSL inspection often breaks Windows certificate-revocation checks (curl exit 35).
      if ($exit -eq 35 -and -not $script:noRevoke -and $err -match 'revocation|CRYPT_E|0x8009201') {
        Write-Host 'TLS revocation check failed (common behind a corporate firewall). Retrying with --ssl-no-revoke.' -ForegroundColor Yellow
        $script:noRevoke = $true; continue
      }
      break
    }
    [byte[]]$bytes = New-Object byte[] 0
    if (Test-Path $respFile) { $bytes = [IO.File]::ReadAllBytes($respFile) }
    return @{ Status = $status; Exit = $exit; Bytes = $bytes; Body = [Text.Encoding]::UTF8.GetString($bytes); Err = $err }
  } finally { Remove-Item -LiteralPath $respFile, $errFile -Force -ErrorAction SilentlyContinue }
}

function Invoke-Claude([string[]]$requestArgs) {
  $id = [Guid]::NewGuid().ToString('N')
  $respFile = Join-Path $tmpDir ("demo-claude-$id.bin"); $errFile = Join-Path $tmpDir ("demo-claude-err-$id.txt")
  try {
    $all = @('-sS', '--http1.1', '--connect-timeout', '20', '--max-time', '240', '-H', ('x-api-key: ' + $claudeKey), '-H', 'anthropic-version: 2023-06-01',
             '-o', $respFile, '--stderr', $errFile, '-w', '%{http_code}') + $proxyArgs
    if ($script:noRevoke) { $all += '--ssl-no-revoke' }
    $all += $requestArgs
    $codeText = & $curlPath @all
    $exit = $LASTEXITCODE; $status = 0; [void][int]::TryParse(([string]$codeText).Trim(), [ref]$status)
    $err = if (Test-Path $errFile) { ([IO.File]::ReadAllText($errFile)).Trim() } else { '' }
    [byte[]]$bytes = New-Object byte[] 0
    if (Test-Path $respFile) { $bytes = [IO.File]::ReadAllBytes($respFile) }
    return @{ Status = $status; Exit = $exit; Bytes = $bytes; Body = [Text.Encoding]::UTF8.GetString($bytes); Err = $err }
  } finally { Remove-Item -LiteralPath $respFile, $errFile -Force -ErrorAction SilentlyContinue }
}
function Invoke-Gemini([string[]]$requestArgs) {
  $id = [Guid]::NewGuid().ToString('N')
  $respFile = Join-Path $tmpDir ("demo-gem-$id.bin"); $errFile = Join-Path $tmpDir ("demo-gem-err-$id.txt")
  try {
    $all = @('-sS', '--http1.1', '--connect-timeout', '20', '--max-time', '240', '-H', ('x-goog-api-key: ' + $geminiKey),
             '-o', $respFile, '--stderr', $errFile, '-w', '%{http_code}') + $proxyArgs
    if ($script:noRevoke) { $all += '--ssl-no-revoke' }
    $all += $requestArgs
    $codeText = & $curlPath @all
    $exit = $LASTEXITCODE; $status = 0; [void][int]::TryParse(([string]$codeText).Trim(), [ref]$status)
    $err = if (Test-Path $errFile) { ([IO.File]::ReadAllText($errFile)).Trim() } else { '' }
    [byte[]]$bytes = New-Object byte[] 0
    if (Test-Path $respFile) { $bytes = [IO.File]::ReadAllBytes($respFile) }
    return @{ Status = $status; Exit = $exit; Bytes = $bytes; Body = [Text.Encoding]::UTF8.GetString($bytes); Err = $err }
  } finally { Remove-Item -LiteralPath $respFile, $errFile -Force -ErrorAction SilentlyContinue }
}
function Get-GeminiModels {
  # Candidate models, best first: newest stable "flash" (free tier), then flash previews, then flash-lite.
  if ($script:geminiModels.Count -gt 0) { return $script:geminiModels }
  $found = @()
  try {
    $r = Invoke-Gemini @(($geminiBase + '/v1beta/models?pageSize=200'))
    if ($r.Status -eq 200) {
      $ms = @(($r.Body | ConvertFrom-Json).models | Where-Object { $_.supportedGenerationMethods -contains 'generateContent' } | ForEach-Object { ([string]$_.name) -replace '^models/', '' })
      $ver = { param($n) if ($n -match 'gemini-(\d+(?:\.\d+)?)') { [double]$Matches[1] } else { 0 } }
      $stable = $ms | Where-Object { $_ -match '^gemini-[\d.]+-flash$' } | Sort-Object { & $ver $_ } -Descending
      $prev = $ms | Where-Object { $_ -match '^gemini-[\d.]+-flash-preview' } | Sort-Object { & $ver $_ } -Descending
      $lite = $ms | Where-Object { $_ -match '^gemini-[\d.]+-flash-lite$' } | Sort-Object { & $ver $_ } -Descending
      $alias = $ms | Where-Object { $_ -match '^gemini-flash(-lite)?-latest$' }
      # Flash-Lite first: fastest and the largest free daily allowance.
      $found = @(@($lite | Select-Object -First 2) + @($alias | Where-Object { $_ -match 'lite' }) + @($stable | Select-Object -First 2) + @($alias | Where-Object { $_ -notmatch 'lite' }) + @($prev) | Where-Object { $_ } | Select-Object -Unique -First 8)
    }
  } catch {}
  # Listing failed (network / limit): use Google's always-current aliases and do NOT remember them, so the next call retries the listing.
  if ($found.Count -eq 0) { return @('gemini-flash-lite-latest', 'gemini-flash-latest') }
  $script:geminiModels = @($found)
  return $script:geminiModels
}
function Get-ClaudeModel {
  if ($script:claudeModel) { return $script:claudeModel }
  # Pick the newest Sonnet model this key can use (the list is returned newest first).
  try {
    $r = Invoke-Claude @(($claudeBase + '/v1/models?limit=100'))
    if ($r.Status -eq 200) {
      $ids = @(($r.Body | ConvertFrom-Json).data | ForEach-Object { $_.id })
      $pick = $ids | Where-Object { $_ -match 'sonnet' } | Select-Object -First 1
      if (-not $pick) { $pick = $ids | Select-Object -First 1 }
      if ($pick) { $script:claudeModel = [string]$pick; return $script:claudeModel }
    }
  } catch {}
  return 'claude-sonnet-5-5'
}
function ConvertTo-JsonText($obj) {
  if ($PSVersionTable.PSVersion.Major -ge 7) { return ($obj | ConvertTo-Json -Depth 50 -Compress) }
  $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $ser.MaxJsonLength = 2147483647; $ser.RecursionLimit = 100
  return $ser.Serialize($obj)
}

function Get-Hint($status, $body, $exit) {
  if ($exit -in 5, 6, 7) { return 'This PC cannot reach api.elevenlabs.io. Check the internet connection, or ask IT to allow api.elevenlabs.io (HTTPS 443). If you use a proxy, set HTTPS_PROXY in Start-Demo.bat.' }
  if ($exit -eq 28) { return 'The request timed out. Check the network / proxy, or try a shorter recording.' }
  if ($exit -in 35, 60) { return 'TLS/SSL error talking to ElevenLabs (often corporate SSL inspection). Set DEMO_SSL_NO_REVOKE=1 in the .bat, or ask IT to allow api.elevenlabs.io.' }
  if ($status -eq 400 -and $body -match '(?i)<html') { return 'The request was rejected as malformed. This almost always means the API key contains invalid characters (for example it was not pasted correctly). Close this window, delete elevenlabs-key.txt in the demo folder, start Start-Demo.bat again and paste the full key (sk_...).' }
  if ($status -eq 401 -or $body -match 'invalid_api_key|missing_permissions') { return 'The API key is wrong or does not have the "Speech to Text" permission. In ElevenLabs > Developers > API Keys, create/edit the key, enable Speech to Text (and Text to Speech), then paste it into Start-Demo.bat.' }
  if ($status -eq 402 -or $body -match 'quota|credits|payment') { return 'The ElevenLabs account is out of credits or the plan does not include this feature.' }
  if ($status -eq 403) { return 'ElevenLabs refused the request (403). If you are on a free plan from a VPN/company network ElevenLabs may block it; check the account and key restrictions.' }
  if ($status -eq 429) { return 'Rate limit reached. Wait a moment and try again.' }
  if ($status -eq 413) { return 'The audio file is too large.' }
  return ''
}
function Get-ErrorMessage($body) {
  if ($body -match '(?is)<title>(.*?)</title>') { return ('Rejected before reaching ElevenLabs: ' + $Matches[1]) }
  try { $o = $body | ConvertFrom-Json } catch { return $body }
  if ($o.detail) {
    if ($o.detail -is [string]) { return $o.detail }
    if ($o.detail.message) { return [string]$o.detail.message }
    return ($o.detail | ConvertTo-Json -Compress -Depth 5)
  }
  if ($o.error -and $o.error.message) { return [string]$o.error.message }
  if ($o.message) { return [string]$o.message }
  return $body
}

# ---------------- HTTP helpers ----------------
function Send-Bytes($ctx, [byte[]]$bytes, $contentType = 'application/octet-stream', $status = 200, $headers = @{}) {
  $ctx.Response.StatusCode = $status; $ctx.Response.ContentType = $contentType
  Add-Cors $ctx
  foreach ($k in $headers.Keys) { $ctx.Response.AddHeader($k, [string]$headers[$k]) }
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length); $ctx.Response.Close()
}
# Lets the page work even when index.html is opened straight from the folder (file://).
function Add-Cors($ctx) {
  $ctx.Response.AddHeader('Access-Control-Allow-Origin', '*')
  $ctx.Response.AddHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
  $ctx.Response.AddHeader('Access-Control-Allow-Headers', 'Content-Type')
  $ctx.Response.AddHeader('Access-Control-Allow-Private-Network', 'true')
  $ctx.Response.AddHeader('Access-Control-Expose-Headers', 'X-Demo-Cache')
}
function Send-Json($ctx, $obj, $status = 200) {
  Send-Bytes $ctx ([Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 10 -Compress))) 'application/json; charset=utf-8' $status
}
if ($PSVersionTable.PSVersion.Major -lt 6) { try { Add-Type -AssemblyName System.Web.Extensions } catch {} }
function Read-JsonBody($ctx) {
  $sr = New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
  try { $text = $sr.ReadToEnd() } finally { $sr.Dispose() }
  # Windows PowerShell 5.1 ConvertFrom-Json is limited to ~2MB; base64 audio is bigger, so raise the limit.
  if ($PSVersionTable.PSVersion.Major -ge 7) { return ($text | ConvertFrom-Json -AsHashtable) }
  $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $ser.MaxJsonLength = 2147483647
  return $ser.DeserializeObject($text)   # Dictionary[string,object]
}
function Get-Field($d, $name) {
  if ($null -eq $d) { return $null }
  # JavaScriptSerializer gives Dictionary[string,object] (PS 5.1); ConvertFrom-Json -AsHashtable gives a hashtable (PS 7).
  try { if ($d.ContainsKey($name)) { return $d[$name] } else { return $null } } catch {}
  try { return $d.$name } catch { return $null }
}
function Get-Mime($ext) { switch ($ext) { '.mp3' { 'audio/mpeg' } '.wav' { 'audio/wav' } '.m4a' { 'audio/mp4' } '.mp4' { 'audio/mp4' } '.webm' { 'audio/webm' } '.ogg' { 'audio/ogg' } '.opus' { 'audio/ogg' } '.flac' { 'audio/flac' } '.aac' { 'audio/aac' } default { 'audio/mpeg' } } }
function Find-LocalFile([string]$name) {
  $leaf = [IO.Path]::GetFileName($name)
  foreach ($c in @((Join-Path $base $name), (Join-Path $base $leaf), (Join-Path (Join-Path $base 'calls') $leaf))) {
    $full = [IO.Path]::GetFullPath($c)
    if ($full.StartsWith([IO.Path]::GetFullPath($base)) -and (Test-Path -LiteralPath $full -PathType Leaf)) { return $full }
  }
  return $null
}

# ---------------- Sample calls with BOTH voices (agent + customer), created once with ElevenLabs TTS ----------------
# Any calls\NAME.script.txt with lines "A: ..." (agent) / "C: ..." (customer) becomes calls\NAME.mp3.
function Invoke-TTS([string]$voice, [string]$text, [string]$outFile) {
  $pf = Join-Path $tmpDir ('demo-ttsgen-' + [Guid]::NewGuid().ToString('N') + '.json')
  try {
    $payload = @{ text = $text; model_id = 'eleven_multilingual_v2'; voice_settings = @{ stability = 0.45; similarity_boost = 0.8; style = 0.15 } } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($pf, $payload, (New-Object Text.UTF8Encoding($false)))
    $r = Invoke-Eleven @('-X', 'POST', ($apiBase + '/v1/text-to-speech/' + $voice + '?output_format=mp3_44100_128'), '-H', 'Content-Type: application/json', '-H', 'Accept: audio/mpeg', '--data-binary', ('@' + $pf))
    return $r
  } finally { Remove-Item -LiteralPath $pf -Force -ErrorAction SilentlyContinue }
}
$callsDir0 = Join-Path $base 'calls'
if (Test-Path -LiteralPath $callsDir0) {
  Get-ChildItem -LiteralPath $callsDir0 -Filter '*.script.txt' -File | ForEach-Object {
    $target = Join-Path $callsDir0 ($_.Name -replace '\.script\.txt$', '.mp3')
    if (Test-Path -LiteralPath $target) { return }
    $lines = @([IO.File]::ReadAllLines($_.FullName, [Text.Encoding]::UTF8) | Where-Object { $_ -match '^\s*[AC]\s*:' })
    if ($lines.Count -eq 0) { return }
    $agentVoice = if ($env:DEMO_AGENT_VOICE) { $env:DEMO_AGENT_VOICE } else { 'pNInz6obpgDQGcFmaJgB' }      # ElevenLabs premade male voice
    $custVoice = if ($env:DEMO_CUSTOMER_VOICE) { $env:DEMO_CUSTOMER_VOICE } else { 'EXAVITQu4vr4xnSDxMaL' }  # ElevenLabs premade female voice
    Write-Host "Creating the sample call $([IO.Path]::GetFileName($target)) with two ElevenLabs voices (one time, $($lines.Count) lines)..." -ForegroundColor Cyan
    $ms = New-Object IO.MemoryStream; $ok = $true; $n = 0
    foreach ($ln in $lines) {
      $n++
      $isAgent = $ln -match '^\s*A\s*:'
      $text = ($ln -replace '^\s*[AC]\s*:\s*', '').Trim() + ' <break time="0.7s" />'
      $voice = if ($isAgent) { $agentVoice } else { $custVoice }
      $r = Invoke-TTS $voice $text ''
      if ($r.Status -eq 404 -or ($r.Status -eq 400 -and $r.Body -match 'voice')) {
        # Voice not available on this account: fall back to the default voice for the agent and Rachel for the customer.
        $voice = if ($isAgent) { $voiceId } else { '21m00Tcm4TlvDq8ikWAM' }
        if ($isAgent -and $voice -eq '21m00Tcm4TlvDq8ikWAM') { $voice = 'TxGEqnHWrfWFTfGW9XjX' }
        $r = Invoke-TTS $voice $text ''
      }
      if ($r.Status -ne 200 -or $r.Bytes.Length -lt 500) {
        Write-Host "  Line $n failed: HTTP $($r.Status) $(Get-ErrorMessage $r.Body) $($r.Err)" -ForegroundColor Red
        $h = Get-Hint $r.Status $r.Body $r.Exit; if ($h) { Write-Host "  $h" -ForegroundColor Yellow }
        Write-Host '  (Your ElevenLabs key needs the "Text to Speech" permission to create this call.)' -ForegroundColor Yellow
        $ok = $false; break
      }
      $ms.Write($r.Bytes, 0, $r.Bytes.Length)
      Write-Host "  $n/$($lines.Count) $(if ($isAgent) { 'agent' } else { 'customer' })" -ForegroundColor DarkGray
    }
    if ($ok) { [IO.File]::WriteAllBytes($target, $ms.ToArray()); Write-Host "Sample call ready: calls\$([IO.Path]::GetFileName($target))" -ForegroundColor Green }
    $ms.Dispose()
  }
}

# ---------------- Start listener ----------------
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() } catch { throw "Could not start on port $Port (is the demo already running, or is the port used by another app?). Change PORT in Start-Demo.bat. Details: $($_.Exception.Message)" }
Write-Host ''
Write-Host "the assistant AI Demo running at http://localhost:$Port/" -ForegroundColor Green
Write-Host "ElevenLabs key $keyHint  |  STT model: $sttModel  |  TTS voice: $voiceId" -ForegroundColor Cyan
if ($aiProvider -eq 'gemini') { Write-Host "AI answers ON: Google Gemini free tier (model $((Get-GeminiModels)[0]))" -ForegroundColor Cyan } elseif ($claudeKey) { Write-Host "Claude answers ON (key ...$($claudeKey.Substring($claudeKey.Length-4)), model $(Get-ClaudeModel))" -ForegroundColor Cyan } else { Write-Host 'Answers: prepared answers for the 3 sample calls (free, no AI key needed)' -ForegroundColor Cyan }
if ($proxy) { Write-Host "Using proxy: $proxy" -ForegroundColor Cyan }
Write-Host 'Keep this window open during the demo. Close it to stop the server.'
Write-Host ''
if ($OpenBrowser) { Start-Process "http://localhost:$Port/" }

while ($listener.IsListening) {
  $ctx = $null
  try {
    $ctx = $listener.GetContext()
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
    if ($ctx.Request.HttpMethod -eq 'OPTIONS') { Add-Cors $ctx; $ctx.Response.StatusCode = 204; $ctx.Response.Close(); continue }

    if ($path -eq '/api/config') {
      $origin = [string]$ctx.Request.Headers['Origin']
      $trusted = (-not $origin) -or $origin -eq 'null' -or $origin -match '^https?://(localhost|127\.0\.0\.1)(:\d+)?$'
      $gk = if ($trusted -and $aiProvider -eq 'gemini') { $geminiKey } else { '' }
      $gm = if ($aiProvider -eq 'gemini') { @(Get-GeminiModels) } else { @() }
      Send-Json $ctx @{ geminiKey = $gk; geminiModels = $gm; geminiBase = $geminiBase; provider = 'ElevenLabs'; sttModel = $sttModel; ttsModel = 'eleven_multilingual_v2'; voiceId = $voiceId; keyHint = $keyHint; proxy = [bool]$proxy; ai = [bool]$aiProvider; aiProvider = $aiProvider; aiModel = $(if ($aiProvider -eq 'gemini') { (Get-GeminiModels)[0] } elseif ($aiProvider -eq 'claude') { Get-ClaudeModel } else { '' }) }
      continue
    }

    if ($path -eq '/api/stt') {
      $j = Read-JsonBody $ctx
      $force = [bool](Get-Field $j 'force')
      $source = [string](Get-Field $j 'source')
      if ($source) {
        $file = Find-LocalFile $source
        if (-not $file) { Send-Json $ctx @{ error = "Recording '$source' was not found next to index.html." } 404; continue }
        $bytes = [IO.File]::ReadAllBytes($file); $fname = [IO.Path]::GetFileName($file)
      } else {
        $b64 = [string](Get-Field $j 'base64')
        if (-not $b64) { Send-Json $ctx @{ error = 'No audio data was received.' } 400; continue }
        $bytes = [Convert]::FromBase64String($b64); $fname = [IO.Path]::GetFileName([string](Get-Field $j 'filename'))
        if (-not $fname) { $fname = 'recording.mp3' }
        try {
          $callsDir = Join-Path $base 'calls'; if (-not (Test-Path $callsDir)) { New-Item -ItemType Directory -Path $callsDir | Out-Null }
          $keep = Join-Path $callsDir (($fname -replace '[\\/:*?"<>|]', '_'))
          if (-not (Test-Path -LiteralPath $keep)) { [IO.File]::WriteAllBytes($keep, $bytes); Write-Host "Saved new call to calls\$([IO.Path]::GetFileName($keep))" -ForegroundColor DarkGray }
        } catch {}
      }
      if ($bytes.Length -lt 100) { Send-Json $ctx @{ error = 'The audio file is empty or too small.' } 400; continue }

      $ext = [IO.Path]::GetExtension($fname).ToLowerInvariant(); if ($ext -notmatch '^\.[a-z0-9]{2,5}$') { $ext = '.mp3' }
      $safeBase = ([IO.Path]::GetFileNameWithoutExtension($fname) -replace '[^A-Za-z0-9_-]', '_')
      $cacheFile = Join-Path $cacheDir ("$safeBase-$($bytes.Length)-$sttModel.json")
      if (-not $force -and (Test-Path -LiteralPath $cacheFile)) {
        Write-Host "STT  $fname  (saved transcript)" -ForegroundColor DarkGray
        Send-Bytes $ctx ([IO.File]::ReadAllBytes($cacheFile)) 'application/json; charset=utf-8' 200 @{ 'X-Demo-Cache' = 'hit' }
        continue
      }

      $tmpAudio = Join-Path $tmpDir ('demo-stt-' + [Guid]::NewGuid().ToString('N') + $ext)
      try {
        [IO.File]::WriteAllBytes($tmpAudio, $bytes)
        Write-Host "STT  $fname  ($([math]::Round($bytes.Length/1KB)) KB) -> ElevenLabs $sttModel ..." -ForegroundColor Cyan
        $model = $sttModel
        for ($try = 1; $try -le 2; $try++) {
          $req = @('-X', 'POST', ($apiBase + '/v1/speech-to-text'), '-H', 'Accept: application/json',
                   '-F', ('file=@' + $tmpAudio + ';type=' + (Get-Mime $ext) + ';filename=upload' + $ext),
                   '-F', ('model_id=' + $model), '-F', 'diarize=true', '-F', 'tag_audio_events=false', '-F', 'timestamps_granularity=word')
          if ($sttLanguage) { $req += @('-F', ('language_code=' + $sttLanguage)) }
          if ($numSpeakers) { $req += @('-F', ('num_speakers=' + $numSpeakers)) }
          $r = Invoke-Eleven $req
          # If this account/region does not offer the configured model yet, fall back to scribe_v1 once.
          if ($try -eq 1 -and $model -ne 'scribe_v1' -and $r.Status -in 400, 404, 422 -and $r.Body -match 'model') {
            Write-Host "Model $model rejected, retrying with scribe_v1" -ForegroundColor Yellow; $model = 'scribe_v1'; continue
          }
          break
        }
        if ($r.Exit -ne 0 -and $r.Status -eq 0) {
          Write-Host "STT network error: curl exit $($r.Exit) $($r.Err)" -ForegroundColor Red
          Send-Json $ctx @{ error = "Could not connect to ElevenLabs (curl exit $($r.Exit)): $($r.Err)"; hint = (Get-Hint 0 '' $r.Exit) } 502; continue
        }
        if ($r.Status -ge 400 -or $r.Status -eq 0) {
          $msg = Get-ErrorMessage $r.Body
          Write-Host "STT HTTP $($r.Status): $msg" -ForegroundColor Red
          Send-Json $ctx @{ error = "ElevenLabs STT HTTP $($r.Status): $msg"; status = $r.Status; hint = (Get-Hint $r.Status $r.Body $r.Exit) } 502; continue
        }
        if ($r.Body -notmatch '"text"') {
          Send-Json $ctx @{ error = 'ElevenLabs answered but no transcript text was in the response.'; raw = $r.Body.Substring(0, [Math]::Min(500, $r.Body.Length)) } 502; continue
        }
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir | Out-Null }
        [IO.File]::WriteAllBytes((Join-Path $cacheDir ("$safeBase-$($bytes.Length)-$sttModel.json")), $r.Bytes)
        Write-Host "STT  $fname  done ($model)" -ForegroundColor Green
        Send-Bytes $ctx $r.Bytes 'application/json; charset=utf-8' 200 @{ 'X-Demo-Cache' = 'miss' }
        continue
      } finally { Remove-Item -LiteralPath $tmpAudio -Force -ErrorAction SilentlyContinue }
    }

    if ($path -eq '/api/calls') {
      # Every recording in the demo folder and its "calls" sub-folder = "any call in the system".
      $list = @()
      # Calls named in calls\hidden.txt (one file name per line) are not shown as samples.
      $hiddenFile = Join-Path (Join-Path $base 'calls') 'hidden.txt'
      $hidden = @(); if (Test-Path -LiteralPath $hiddenFile) { $hidden = @([IO.File]::ReadAllLines($hiddenFile, [Text.Encoding]::UTF8) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' }) }
      foreach ($dir in @($base, (Join-Path $base 'calls'))) {
        if (Test-Path -LiteralPath $dir) {
          Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -match '^\.(mp3|wav|m4a|ogg|opus|webm|flac|aac|mp4)$' -and ($hidden -notcontains $_.Name) -and ($hidden -notcontains $_.BaseName) } | ForEach-Object {
            $rel = if ($dir -eq $base) { $_.Name } else { 'calls/' + $_.Name }
            $list += @{ name = $_.Name; path = $rel; size = $_.Length }
          }
        }
      }
      Send-Json $ctx @{ calls = $list }; continue
    }

    if ($path -eq '/api/knowledge') {
      # Knowledge base = text files in the "knowledge" folder (menus, rooms, programs, policies...).
      # knowledge\general is always used; the business sub-folder is picked from the call; unknown calls use everything.
      $kbRoot = Join-Path $base 'knowledge'
      $business = [string]$ctx.Request.QueryString['business']
      $map = @{ 'Hotels' = 'hotel'; 'Restaurant' = 'restaurant'; 'Educational Platform' = 'education'; 'Pizza Shop' = 'pizza' }
      $dirs = @()
      if (Test-Path -LiteralPath $kbRoot) {
        $sub = $map[$business]
        if ($sub -and (Test-Path -LiteralPath (Join-Path $kbRoot $sub))) { $dirs = @((Join-Path $kbRoot 'general'), (Join-Path $kbRoot $sub)) }
        else { $dirs = @($kbRoot) }
      }
      $files = @(); $total = 0
      foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        Get-ChildItem -LiteralPath $d -File -Recurse | Where-Object { $_.Extension -match '^\.(txt|md|csv|json|tsv)$' -and $_.Name -ne 'README.txt' } | Sort-Object FullName | ForEach-Object {
          if ($total -ge 60000) { return }
          $t = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
          if ($t.Length -gt 15000) { $t = $t.Substring(0, 15000) + "`n...(truncated)" }
          $total += $t.Length
          $rel = $_.FullName.Substring($kbRoot.Length).TrimStart('\', '/') -replace '\\', '/'
          $files += @{ name = $rel; text = $t }
        }
      }
      Send-Json $ctx @{ business = $business; files = $files }; continue
    }

    if ($path -eq '/api/answers') {
      if (-not $aiProvider) { Send-Json $ctx @{ error = 'No AI key configured. Restart Start-Demo.bat and paste a free Gemini key. Add ANTHROPIC_API_KEY to Start-Demo.bat or restart and paste it.'; hint = 'Without it the assistant uses keyword answers.' } 400; continue }
      $j = Read-JsonBody $ctx
      $req = Get-Field $j 'request'
      if (-not $req) { Send-Json $ctx @{ error = 'No request body.' } 400; continue }
      if ($aiProvider -eq 'gemini') {
        $json = ConvertTo-JsonText $req
        $sha = [Security.Cryptography.SHA256]::Create()
        $hash = (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('gemini' + $json)) | ForEach-Object { $_.ToString('x2') })).Substring(0, 24)
        $cacheFile = Join-Path $cacheDir ("answers-gemini-$hash.json")
        if ((-not [bool](Get-Field $j 'force')) -and (Test-Path -LiteralPath $cacheFile)) {
          Write-Host 'AI   answers (saved copy)' -ForegroundColor DarkGray
          Send-Bytes $ctx ([IO.File]::ReadAllBytes($cacheFile)) 'application/json; charset=utf-8' 200 @{ 'X-Demo-Cache' = 'hit'; 'X-Demo-Provider' = 'gemini' }; continue
        }
        $payloadFile = Join-Path $tmpDir ('demo-gem-req-' + [Guid]::NewGuid().ToString('N') + '.json')
        try {
          if (-not $script:cool) { $script:cool = @{} }
          if (-not $script:thinkOk) { $script:thinkOk = @{} }
          $order = @((Get-GeminiModels) | Where-Object { -not $script:cool[$_] -or $script:cool[$_] -lt (Get-Date) })
          if ($order.Count -eq 0) { $order = @(Get-GeminiModels) }
          $r = $null; $usedModel = ''; $sw = [Diagnostics.Stopwatch]::StartNew()
          foreach ($m in $order) {
            # SPEED: switch Gemini "thinking" to its lowest setting. Gemini 3 uses thinkingLevel, 2.5 uses thinkingBudget.
            # Variants are tried in order; the one this model accepts is remembered.
            $variants = if ($m -match 'gemini-2\.') { @('budget0', 'none') } else { @('minimal', 'low', 'none') }
            if ($script:thinkOk[$m]) { $variants = @($script:thinkOk[$m]) }
            foreach ($v in $variants) {
              $gc = Get-Field $req 'generationConfig'
              if ($gc) {
                if ($v -eq 'minimal') { $gc['thinkingConfig'] = @{ thinkingLevel = 'minimal' } }
                elseif ($v -eq 'low') { $gc['thinkingConfig'] = @{ thinkingLevel = 'low' } }
                elseif ($v -eq 'budget0') { $gc['thinkingConfig'] = @{ thinkingBudget = 0 } }
                elseif ($gc.ContainsKey('thinkingConfig')) { [void]$gc.Remove('thinkingConfig') }
              }
              [IO.File]::WriteAllText($payloadFile, (ConvertTo-JsonText $req), (New-Object Text.UTF8Encoding($false)))
              Write-Host "AI   Gemini $m (thinking: $v) ..." -ForegroundColor Cyan
              $r = Invoke-Gemini @('-X', 'POST', ($geminiBase + '/v1beta/models/' + $m + ':generateContent'), '-H', 'Content-Type: application/json', '--max-time', '40', '--data-binary', ('@' + $payloadFile))
              if ($r.Status -eq 400 -and $r.Body -match '(?i)thinking') { continue }   # this model does not accept that thinking setting
              if ($r.Status -eq 200) { $script:thinkOk[$m] = $v }
              break
            }
            $usedModel = $m
            # Free-tier quota is per model: if one model is busy/limited/unavailable, use the next one for a while.
            if ($r.Status -in 404, 429, 500, 503) {
              $script:cool[$m] = (Get-Date).AddSeconds($(if ($r.Status -eq 404) { 3600 } else { 60 }))
              Write-Host "AI   $m -> HTTP $($r.Status), using the next model for now" -ForegroundColor Yellow; continue
            }
            break
          }
          if ($r.Status -eq 0) { Send-Json $ctx @{ error = "Could not connect to Gemini (curl exit $($r.Exit)): $($r.Err)"; hint = 'Check internet / proxy, or ask IT to allow generativelanguage.googleapis.com.' } 502; continue }
          if ($r.Status -ge 400) {
            $msg = Get-ErrorMessage $r.Body
            $hint = if ($r.Status -in 400, 401, 403 -and $r.Body -match 'API_KEY|API key|PERMISSION') { 'The Gemini key is not valid. Delete gemini-key.txt, restart the .bat and paste the key again from aistudio.google.com/apikey.' } elseif ($r.Status -eq 429) { 'Free-tier limit reached for now. Wait a minute (or until tomorrow for the daily limit) and click Transcribe again.' } elseif ($r.Body -match 'location is not supported|FAILED_PRECONDITION') { 'Gemini free tier is not available from this country/network.' } else { '' }
            Write-Host "AI   HTTP $($r.Status): $msg" -ForegroundColor Red
            Send-Json $ctx @{ error = "Gemini HTTP $($r.Status): $msg"; hint = $hint } 502; continue
          }
          if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir | Out-Null }
          [IO.File]::WriteAllBytes($cacheFile, $r.Bytes)
          Write-Host ("AI   answer ready ($usedModel) in {0:N1}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
          Send-Bytes $ctx $r.Bytes 'application/json; charset=utf-8' 200 @{ 'X-Demo-Cache' = 'miss'; 'X-Demo-Provider' = 'gemini' }; continue
        } finally { Remove-Item -LiteralPath $payloadFile -Force -ErrorAction SilentlyContinue }
      }
      $model = Get-ClaudeModel
      $req['model'] = $model
      $json = ConvertTo-JsonText $req
      $sha = [Security.Cryptography.SHA256]::Create()
      $hash = (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)) | ForEach-Object { $_.ToString('x2') })).Substring(0, 24)
      $cacheFile = Join-Path $cacheDir ("answers-$hash.json")
      if ((-not [bool](Get-Field $j 'force')) -and (Test-Path -LiteralPath $cacheFile)) {
        Write-Host 'AI   answers (saved copy)' -ForegroundColor DarkGray
        Send-Bytes $ctx ([IO.File]::ReadAllBytes($cacheFile)) 'application/json; charset=utf-8' 200 @{ 'X-Demo-Cache' = 'hit' }; continue
      }
      $payloadFile = Join-Path $tmpDir ('demo-claude-req-' + [Guid]::NewGuid().ToString('N') + '.json')
      try {
        [IO.File]::WriteAllText($payloadFile, $json, (New-Object Text.UTF8Encoding($false)))
        Write-Host "AI   writing answers with $model ..." -ForegroundColor Cyan
        $r = Invoke-Claude @('-X', 'POST', ($claudeBase + '/v1/messages'), '-H', 'content-type: application/json', '--data-binary', ('@' + $payloadFile))
        if ($r.Status -eq 0) { Send-Json $ctx @{ error = "Could not connect to Claude (curl exit $($r.Exit)): $($r.Err)"; hint = 'Check internet / proxy, or ask IT to allow api.anthropic.com.' } 502; continue }
        if ($r.Status -ge 400) {
          $msg = Get-ErrorMessage $r.Body
          $hint = if ($r.Status -eq 401) { 'The Claude key is invalid. Delete anthropic-key.txt and restart to paste it again.' } elseif ($r.Status -eq 404) { 'Model not available for this key. Set ANTHROPIC_MODEL in Start-Demo.bat.' } elseif ($r.Status -in 402, 429, 529) { 'Credits, rate limit or Claude is busy. Try again in a minute.' } else { '' }
          Write-Host "AI   HTTP $($r.Status): $msg" -ForegroundColor Red
          Send-Json $ctx @{ error = "Claude HTTP $($r.Status): $msg"; hint = $hint } 502; continue
        }
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir | Out-Null }
        [IO.File]::WriteAllBytes($cacheFile, $r.Bytes)
        Write-Host 'AI   answers ready' -ForegroundColor Green
        Send-Bytes $ctx $r.Bytes 'application/json; charset=utf-8' 200 @{ 'X-Demo-Cache' = 'miss' }; continue
      } finally { Remove-Item -LiteralPath $payloadFile -Force -ErrorAction SilentlyContinue }
    }

    if ($path -eq '/api/tts') {
      $j = Read-JsonBody $ctx
      $text = [string](Get-Field $j 'text')
      if ([string]::IsNullOrWhiteSpace($text)) { Send-Json $ctx @{ error = 'No text was supplied for TTS.' } 400; continue }
      $vid = [string](Get-Field $j 'voice_id'); if (-not $vid) { $vid = $voiceId }
      $payloadFile = Join-Path $tmpDir ('demo-tts-' + [Guid]::NewGuid().ToString('N') + '.json')
      try {
        # Write the JSON body to a UTF-8 file so Arabic text is not mangled by native-argument quoting.
        $payload = @{ text = $text; model_id = 'eleven_multilingual_v2' } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($payloadFile, $payload, (New-Object Text.UTF8Encoding($false)))
        $r = Invoke-Eleven @('-X', 'POST', ($apiBase + '/v1/text-to-speech/' + $vid), '-H', 'Content-Type: application/json', '-H', 'Accept: audio/mpeg', '--data-binary', ('@' + $payloadFile))
        if ($r.Status -ge 400 -or $r.Status -eq 0 -or $r.Bytes.Length -lt 100) {
          $msg = if ($r.Status -eq 0) { "curl exit $($r.Exit): $($r.Err)" } else { Get-ErrorMessage $r.Body }
          Send-Json $ctx @{ error = "ElevenLabs TTS HTTP $($r.Status): $msg"; hint = (Get-Hint $r.Status $r.Body $r.Exit) } 502; continue
        }
        Send-Bytes $ctx $r.Bytes 'audio/mpeg'; continue
      } finally { Remove-Item -LiteralPath $payloadFile -Force -ErrorAction SilentlyContinue }
    }

    # ---------------- static files ----------------
    $relative = if ($path -eq '/') { 'index.html' } else { $path.TrimStart('/') }
    $full = Find-LocalFile $relative
    if (-not $full -and $relative -eq 'index.html') { $full = Find-LocalFile 'index 2.html' }
    if (-not $full) { $ctx.Response.StatusCode = 404; $ctx.Response.Close(); continue }
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    $ct = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'; '.css' = 'text/css'; '.json' = 'application/json'; '.mp3' = 'audio/mpeg'; '.wav' = 'audio/wav'; '.m4a' = 'audio/mp4'; '.ogg' = 'audio/ogg'; '.opus' = 'audio/ogg'; '.png' = 'image/png'; '.svg' = 'image/svg+xml' }[$ext]
    if (-not $ct) { $ct = 'application/octet-stream' }
    $bytes = [IO.File]::ReadAllBytes($full)
    $hdr = @{ 'Accept-Ranges' = 'bytes'; 'Cache-Control' = 'no-store' }
    $range = $ctx.Request.Headers['Range']
    if ($range -and $range -match '^bytes=(\d*)-(\d*)$' -and $bytes.Length -gt 0) {
      $start = if ($Matches[1]) { [long]$Matches[1] } else { [Math]::Max(0, $bytes.Length - [long]$Matches[2]) }
      $end = if ($Matches[1] -and $Matches[2]) { [Math]::Min([long]$Matches[2], $bytes.Length - 1) } else { $bytes.Length - 1 }
      if ($start -gt $end) { $start = 0 }
      $len = [int]($end - $start + 1)
      $ctx.Response.StatusCode = 206; $ctx.Response.ContentType = $ct
      foreach ($k in $hdr.Keys) { $ctx.Response.AddHeader($k, $hdr[$k]) }
      $ctx.Response.AddHeader('Content-Range', "bytes $start-$end/$($bytes.Length)")
      $ctx.Response.ContentLength64 = $len
      $ctx.Response.OutputStream.Write($bytes, [int]$start, $len); $ctx.Response.Close()
    } else {
      Send-Bytes $ctx $bytes $ct 200 $hdr
    }
  } catch {
    $m = $_.Exception.Message
    if ($m -notmatch 'network name is no longer available|connection was aborted|forcibly closed|I/O operation') { Write-Host "Error: $m" -ForegroundColor Red }
    if ($ctx) { try { Send-Json $ctx @{ error = $m } 500 } catch {} }
  }
}
$listener.Stop()
