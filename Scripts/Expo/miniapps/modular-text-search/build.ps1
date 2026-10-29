$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$tool = Join-Path $repo 'Scripts\Expo'
$local = $PSScriptRoot
$dist = Join-Path $local 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Push-Location $tool
try {
  & '.\node_modules\.bin\tsc6.cmd' --noEmit -p '.\miniapps\modular-text-search\tsconfig.json'
  if ($LASTEXITCODE -ne 0) { throw "TypeScript check failed" }
  & '.\node_modules\.bin\react-native.cmd' bundle --entry-file '.\miniapps\modular-text-search\index.ts' --platform ios --dev false --bundle-output (Join-Path $dist 'bundle.js') --config '.\metro.config.cjs'
  if ($LASTEXITCODE -ne 0) { throw "Metro bundling failed" }
} finally {
  Pop-Location
}
$stage = Join-Path $dist 'stage'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item (Join-Path $dist 'bundle.js') (Join-Path $stage 'bundle.js') -Force
Copy-Item (Join-Path $local 'script.json') (Join-Path $stage 'script.json') -Force
Copy-Item (Join-Path $local 'package.json') (Join-Path $stage 'package.json') -Force
$zip = Join-Path $dist 'ModularTextSearch.zip'
$out = Join-Path $dist 'ModularTextSearch.hanlinExpo'
Compress-Archive -LiteralPath (Join-Path $stage 'bundle.js'),(Join-Path $stage 'script.json'),(Join-Path $stage 'package.json') -DestinationPath $zip -Force
Move-Item $zip $out -Force
Write-Host "Built $out"
Get-FileHash $out -Algorithm SHA256
