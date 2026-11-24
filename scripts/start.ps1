param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$env:DOCKER_CONTEXT = 'desktop-linux'
$composeExe = Join-Path $env:ProgramFiles 'Docker/Docker/resources/cli-plugins/docker-compose.exe'
if (!(Test-Path -LiteralPath $composeExe)) { throw 'Docker Compose is not installed. Install Docker Desktop first.' }
& docker --context desktop-linux info --format '{{.ServerVersion}}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop, wait until the engine is ready, then run this script again.' }
foreach ($directory in @('storage', 'backups')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot $directory) | Out-Null
}
$runtimeEnv = Join-Path $projectRoot 'storage/.env'
if (!(Test-Path -LiteralPath $runtimeEnv)) {
    $seed = @(
        'EMBEDDING_ENGINE=native',
        'EMBEDDING_MODEL_PREF=MintplexLabs/multilingual-e5-small',
        'VECTOR_DB=lancedb',
        'DISABLE_TELEMETRY=true'
    ) -join "`n"
    [IO.File]::WriteAllText($runtimeEnv, $seed + "`n", [Text.UTF8Encoding]::new($false))
}
if (!(Select-String -LiteralPath $runtimeEnv -Pattern '^GENERIC_OPEN_AI_CUSTOM_HEADERS=' -Quiet)) {
    # This MVP uses one stable provider session for its default demo conversation.
    $providerSession = 'kb-main-' + [guid]::NewGuid().ToString('N')
    [IO.File]::AppendAllText($runtimeEnv, "`nGENERIC_OPEN_AI_CUSTOM_HEADERS=x-opencode-session:$providerSession`n", [Text.UTF8Encoding]::new($false))
}
$composeEnv = Join-Path $projectRoot '.env'
if (!(Test-Path -LiteralPath $composeEnv)) {
    Copy-Item -LiteralPath (Join-Path $projectRoot '.env.example') -Destination $composeEnv
}
& $composeExe --project-directory $projectRoot up -d
if ($LASTEXITCODE -ne 0) { throw 'Compose startup failed.' }
$portMatch = Select-String -LiteralPath $composeEnv -Pattern '^APP_PORT=(\d+)$'
$appPort = if ($portMatch) { $portMatch.Matches[0].Groups[1].Value } else { '3001' }
$baseUrl = "http://127.0.0.1:$appPort"
$ready = $false
for ($attempt = 0; $attempt -lt 45; $attempt++) {
    try {
        $response = Invoke-WebRequest -Uri "$baseUrl/api/ping" -TimeoutSec 3
        if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (!$ready) { throw 'Application is not ready. Check Compose logs; data has been preserved.' }
Write-Output "Ready: $baseUrl/start.html"
if (!$NoBrowser) { Start-Process "$baseUrl/start.html" }
