$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$sdk = Join-Path $repo 'build\MiniAppSDK-Expo'
$report = Join-Path $PSScriptRoot '.hanlin-authoring\build-report.json'
$dist = Join-Path $PSScriptRoot 'dist'
& node (Join-Path $repo 'Scripts\Expo\prepare-types.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Original Expo type preparation failed' }
& node (Join-Path $repo 'Scripts\MiniApps\stage-sdk.mjs') "--output=$sdk" '--engines=expo,scriptwidget'
if ($LASTEXITCODE -ne 0) { throw 'Host-matching Expo SDK preparation failed' }
$previousCompiler = $env:HANLIN_AUTHORING_TYPESCRIPT
try {
  $env:HANLIN_AUTHORING_TYPESCRIPT = Join-Path $repo 'Scripts\Expo\node_modules\typescript\lib\typescript.js'
  & node (Join-Path $repo 'Scripts\MiniApps\miniapp.mjs') build --sdk $sdk --engine expo --project $PSScriptRoot --report $report
  if ($LASTEXITCODE -ne 0) { throw "MiniApp compilation failed. Diagnostics: $report" }
} finally {
  $env:HANLIN_AUTHORING_TYPESCRIPT = $previousCompiler
}
$result = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
if (-not $result.succeeded -or -not $result.archivePath) { throw 'The compiler returned no successful archive' }
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$out = Join-Path $dist 'ModularTextSearch.hanlinExpo'
Copy-Item -LiteralPath $result.archivePath -Destination $out -Force
Write-Host "Built $out with editable sources, original SDK identity and compiler diagnostics"
Get-FileHash $out -Algorithm SHA256
