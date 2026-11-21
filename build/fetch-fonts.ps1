$ErrorActionPreference = 'Stop'
$destination = Join-Path $PSScriptRoot '../src/DeskNodes.App/Resources/Fonts'
New-Item -ItemType Directory -Force $destination | Out-Null
$staging = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $staging | Out-Null
try {
    Invoke-WebRequest -Uri 'https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Regular.ttf' -OutFile (Join-Path $staging 'LXGWWenKai-Regular.ttf')
    if ((Get-FileHash (Join-Path $staging 'LXGWWenKai-Regular.ttf') -Algorithm SHA256).Hash -ne '2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b') { throw 'SHA-256 mismatch: LXGWWenKai-Regular.ttf' }
    Invoke-WebRequest -Uri 'https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Medium.ttf' -OutFile (Join-Path $staging 'LXGWWenKai-Medium.ttf')
    if ((Get-FileHash (Join-Path $staging 'LXGWWenKai-Medium.ttf') -Algorithm SHA256).Hash -ne 'f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a') { throw 'SHA-256 mismatch: LXGWWenKai-Medium.ttf' }
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/lxgw/LxgwWenKai/v1.530/OFL.txt' -OutFile (Join-Path $staging 'OFL.txt')
    if ((Get-FileHash (Join-Path $staging 'OFL.txt') -Algorithm SHA256).Hash -ne '1a25e35da1031c6c3436fde545bb9cb5aca954e9873afe510c834b8b79bd21a0') { throw 'SHA-256 mismatch: OFL.txt' }
    Move-Item -Force (Join-Path $staging 'LXGWWenKai-Regular.ttf') (Join-Path $destination 'LXGWWenKai-Regular.ttf')
    Move-Item -Force (Join-Path $staging 'LXGWWenKai-Medium.ttf') (Join-Path $destination 'LXGWWenKai-Medium.ttf')
    Move-Item -Force (Join-Path $staging 'OFL.txt') (Join-Path $destination 'OFL.txt')
    Write-Output 'LXGW WenKai v1.530: SHA-256 verified.'
} finally {
    Remove-Item -Recurse -Force $staging
}
