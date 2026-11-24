$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$portMatch = Select-String -LiteralPath (Join-Path $projectRoot '.env') -Pattern '^APP_PORT=(\d+)$'
$appPort = if ($portMatch) { $portMatch.Matches[0].Groups[1].Value } else { '3001' }
$appBase = "http://127.0.0.1:$appPort"
$ping = Invoke-WebRequest -Uri "$appBase/api/ping" -TimeoutSec 10
$guide = Invoke-WebRequest -Uri "$appBase/start.html" -TimeoutSec 10
$workspaces = Invoke-RestMethod -Uri "$appBase/api/workspaces" -TimeoutSec 10
$workspaceResults = @()
foreach ($workspace in $workspaces.workspaces) {
    $details = Invoke-RestMethod -Uri "$appBase/api/workspace/$($workspace.slug)" -TimeoutSec 10
    $entry = @($details.workspace)[0]
    $workspaceResults += [ordered]@{
        name = $entry.name
        mode = $entry.chatMode
        indexedDocuments = @($entry.documents).Count
    }
}
$result = [ordered]@{
    applicationResponds = $ping.StatusCode -eq 200
    guideResponds = $guide.StatusCode -eq 200 -and $guide.Content.Contains('API Key')
    workspaces = $workspaceResults
    llmAcceptance = 'Not checked by this script: verify real responses and source citations separately.'
}
$reportPath = Join-Path $projectRoot 'verification/local-status.json'
[IO.File]::WriteAllText($reportPath, ($result | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 5
