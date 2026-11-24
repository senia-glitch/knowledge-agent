$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:DOCKER_CONTEXT = 'desktop-linux'
& (Join-Path $env:ProgramFiles 'Docker/Docker/resources/cli-plugins/docker-compose.exe') --project-directory $projectRoot stop
if ($LASTEXITCODE -ne 0) { throw 'Compose stop failed.' }
Write-Output 'Project stopped. Documents and settings are preserved.'
