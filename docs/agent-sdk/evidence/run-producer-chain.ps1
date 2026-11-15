param([Parameter(Mandatory=$true)][string]$ProducerRoot)
$ErrorActionPreference = 'Stop'
if ((Get-PSDrive C).Free -lt 8GB) { throw 'C: reserve below 8 GiB' }
$producerProofRoot = (Resolve-Path -LiteralPath $ProducerRoot).Path
$consumerProofRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$proofBuild = Join-Path $consumerProofRoot 'Packages/HanlinAgentSDK/.build/producer-chain'
New-Item -ItemType Directory -Path $proofBuild -Force | Out-Null
$productionBuild = Join-Path $producerProofRoot '.build/x86_64-unknown-windows-msvc/debug'
$testingRoot = Join-Path (Split-Path (Split-Path $env:SDKROOT -Parent) -Parent) 'Library/Testing-6.3.3/usr'
$testingModules = Join-Path $testingRoot 'lib/swift/windows'
$testingLibraries = Join-Path $testingModules 'x86_64'
$runner = Join-Path $proofBuild 'Runner.swift'
[IO.File]::WriteAllText($runner, "import Foundation`nimport Testing`n@main struct Runner { static func main() async { let result: CInt = await Testing.__swiftPMEntryPoint(); exit(result) } }`n", [Text.UTF8Encoding]::new($false))
$testPaths = @(
    'Tests/SwiftAISDKTests/GenerateText/RawToolInputPropagationTests.swift',
    'Tests/SwiftAISDKTests/GenerateText/ToResponseMessagesTests.swift',
    'Tests/SwiftAISDKTests/GenerateText/ExecuteToolCallProviderMetadataTests.swift',
    'Tests/SwiftAISDKTests/TestSupport/MockTracer.swift',
    'Tests/AISDKProviderUtilsTests/ModelMessageCodableTests.swift'
)
$productionModules = @('AISDKProvider','AISDKProviderUtils','AISDKZodAdapter','EventSourceParser','GatewayProvider','AISDKJSONSchema','SwiftAISDK')
$objects = @()
$inputPaths = @()
foreach ($module in $productionModules) {
    $objects += Get-ChildItem -LiteralPath (Join-Path $productionBuild ($module + '.build')) -Filter '*.swift.o' -File | ForEach-Object FullName
    $objects += Join-Path $productionBuild ('Modules/' + $module + '.o')
    $inputPaths += Get-ChildItem -LiteralPath (Join-Path $producerProofRoot ('Sources/' + $module)) -Filter '*.swift' -Recurse -File | ForEach-Object FullName
}
$testSources = @($testPaths | ForEach-Object { Join-Path $producerProofRoot $_ })
$inputPaths += $testSources
$before = @($inputPaths | Sort-Object -Unique | ForEach-Object { @{path=[IO.Path]::GetRelativePath($producerProofRoot,$_).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()} })
$responseFile = Join-Path $proofBuild 'objects.rsp'
[IO.File]::WriteAllLines($responseFile, @($objects | ForEach-Object { '"' + $_ + '"' }), [Text.UTF8Encoding]::new($false))
$executable = Join-Path $proofBuild 'ProducerChainTests.exe'
$compileArgs = @('-swift-version','6','-parse-as-library','-module-name','HanlinRawInputScopedTests','-I',(Join-Path $productionBuild 'Modules'),'-I',$testingModules,'-L',$testingLibraries,'-lTesting') + $testSources + @($runner,('@' + $responseFile),'-o',$executable)
& swiftc @compileArgs *> (Join-Path $PSScriptRoot 'producer-chain-link.log')
if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $PSScriptRoot 'producer-chain-link.log') -Tail 40; throw 'Scoped test compilation/link failed' }
$savedProofPath = $env:Path
try {
    $env:Path = (Join-Path $testingRoot 'bin64') + ';' + $env:Path
    & $executable *> (Join-Path $PSScriptRoot 'producer-chain-run.log')
    $proofExit = $LASTEXITCODE
} finally { $env:Path = $savedProofPath }
$after = @($inputPaths | Sort-Object -Unique | ForEach-Object { @{path=[IO.Path]::GetRelativePath($producerProofRoot,$_).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()} })
if (($before | ConvertTo-Json -Depth 6 -Compress) -ne ($after | ConvertTo-Json -Depth 6 -Compress)) { throw 'Source inputs changed during proof' }
$proof = @{
    scope='Actual complete SwiftAISDK production module graph built by root SwiftPM manifest, linked to selected real repository Swift Testing suites; NOT root swift test pass, Hanlin Session or Apple proof'
    rootSwiftTest='BLOCKED_UNCHANGED_WINDOWS_REVAI_URLSESSION_SHARED'
    producerRoot=$producerProofRoot
    producerBaseline=(& git -C $producerProofRoot rev-parse HEAD).Trim()
    sourceInputs=$before
    modules=$productionModules
    testPaths=$testPaths
    runner=[IO.File]::ReadAllText($runner)
    compileArguments=$compileArgs
    runExit=$proofExit
    hanlinSession='NOT_RUN'
    apple='NOT_RUN'
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'producer-chain-proof.json'), ($proof | ConvertTo-Json -Depth 8).Replace("`r`n","`n") + "`n", [Text.UTF8Encoding]::new($false))
Get-Content (Join-Path $PSScriptRoot 'producer-chain-run.log') -Tail 18
if ($proofExit -ne 0) { throw ('Scoped Swift Testing run failed: ' + $proofExit) }
