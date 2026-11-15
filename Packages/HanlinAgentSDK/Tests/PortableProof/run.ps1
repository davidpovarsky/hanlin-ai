param()
$ErrorActionPreference = 'Stop'
$sdkProofRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
Push-Location -LiteralPath $sdkProofRoot
try {
    if ((Get-PSDrive C).Free -lt 8GB) { throw 'C: reserve below 8 GiB; do not create build output' }
    $sdkProofBuild = Join-Path $sdkProofRoot 'Packages/HanlinAgentSDK/.build/portable'
    $sdkProofEvidence = Join-Path $sdkProofRoot 'docs/agent-sdk/evidence'
    New-Item -ItemType Directory -Path $sdkProofBuild,$sdkProofEvidence -Force | Out-Null
    $sdkProofLog = Join-Path $sdkProofEvidence 'portable-run.log'
    [IO.File]::WriteAllText($sdkProofLog, '', [Text.UTF8Encoding]::new($false))
    $sdkProofCommands = [Collections.Generic.List[object]]::new()
    function Invoke-SDKProofCommand {
        param([string]$Executable, [string[]]$Arguments)
        $sdkProofCommands.Add(@{executable=$Executable;arguments=$Arguments})
        & $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath $sdkProofLog -Append
        if ($LASTEXITCODE -ne 0) { throw ('Failed: ' + $Executable + ' (exit ' + $LASTEXITCODE + ')') }
    }
    $sdkProofCanonical = @(Get-ChildItem -LiteralPath Packages/HanlinPlatform/Sources/HanlinPlatformContracts -Filter '*.swift' -File | Where-Object Name -ne 'HanlinManifestSchema.swift' | ForEach-Object FullName)
    $sdkProofHosts = @(Get-ChildItem -LiteralPath Packages/HanlinAgentSDK/Sources/HanlinHostContracts -Filter '*.swift' -File | ForEach-Object FullName)
    $sdkProofStores = @(Get-ChildItem -LiteralPath Packages/HanlinAgentSDK/Sources/HanlinPersistenceAdapters -Filter '*.swift' -File | ForEach-Object FullName)
    $sdkProofDispatcher = @((Join-Path $sdkProofRoot 'Packages/HanlinAgentSDK/Sources/HanlinAgentCore/HanlinHostDispatcher.swift'), (Join-Path $sdkProofRoot 'Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleTextDelta.swift'))
    $sdkProofFixture = @(Get-ChildItem -LiteralPath Packages/HanlinAgentSDK/Tests/Fixtures -Filter '*.swift' -File | ForEach-Object FullName)
    $sdkProofInputs = $sdkProofCanonical + $sdkProofHosts + $sdkProofStores + $sdkProofDispatcher + $sdkProofFixture
    $sdkProofModules = @(
        @{name='HanlinPlatformContracts';sources=$sdkProofCanonical;libraries=@()},
        @{name='HanlinHostContracts';sources=$sdkProofHosts;libraries=@('-lHanlinPlatformContracts')},
        @{name='HanlinPersistenceAdapters';sources=$sdkProofStores;libraries=@('-lHanlinPlatformContracts','-lHanlinHostContracts')},
        @{name='HanlinAgentCore';sources=$sdkProofDispatcher;libraries=@('-lHanlinPlatformContracts','-lHanlinHostContracts')},
        @{name='HanlinSDKTestFixtures';sources=$sdkProofFixture;libraries=@('-lHanlinPlatformContracts','-lHanlinHostContracts')}
    )
    Invoke-SDKProofCommand swift @('--version')
    foreach ($sdkProofModule in $sdkProofModules) {
        $sdkProofArguments = @('-swift-version','6','-parse-as-library','-emit-library','-emit-module','-module-name',$sdkProofModule.name,'-I',$sdkProofBuild,'-L',$sdkProofBuild)
        $sdkProofArguments += $sdkProofModule.libraries + $sdkProofModule.sources
        $sdkProofArguments += @('-emit-module-path',(Join-Path $sdkProofBuild ($sdkProofModule.name + '.swiftmodule')),'-o',(Join-Path $sdkProofBuild ($sdkProofModule.name + '.dll')))
        Invoke-SDKProofCommand swiftc $sdkProofArguments
    }
    $sdkProofMain = Join-Path $sdkProofRoot 'Packages/HanlinAgentSDK/Tests/PortableProof/main.swift'
    $sdkProofInputs += $sdkProofMain
    $sdkProofExecutable = Join-Path $sdkProofBuild 'PortableProof.exe'
    Invoke-SDKProofCommand swiftc @('-swift-version','6','-parse-as-library','-I',$sdkProofBuild,'-L',$sdkProofBuild,'-lHanlinPlatformContracts','-lHanlinHostContracts','-lHanlinPersistenceAdapters','-lHanlinAgentCore','-lHanlinSDKTestFixtures',$sdkProofMain,'-o',$sdkProofExecutable)
    Invoke-SDKProofCommand $sdkProofExecutable @()
    $sdkProofManifest = [ordered]@{
        scope='Windows portable actual source closure; HanlinAgentCore includes dispatcher and pure native snapshot normalization ONLY'
        excluded=@('HanlinManifestSchema.swift (SwiftPM resource accessor)','HanlinAgentSession.swift','Providers/HanlinAppleOnDeviceProvider.swift','HanlinChatCore/SwiftAISDK/provider pipeline','Apple SDK/FoundationModels/UIKit/SwiftUI','real Anytype/Otzaria host')
        sourceHead=(git rev-parse HEAD)
        workingTree='Source changes under exclusive CHAT-SDK W1 lease; exact input hashes below'
        result='PASS'
        commands=@($sdkProofCommands)
        sources=@($sdkProofInputs | ForEach-Object { @{path=[IO.Path]::GetRelativePath($sdkProofRoot,$_).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()} })
    }
    $sdkProofJson = ($sdkProofManifest | ConvertTo-Json -Depth 8).Replace("`r`n","`n") + "`n"
    [IO.File]::WriteAllText((Join-Path $sdkProofEvidence 'portable-source-proof.json'),$sdkProofJson,[Text.UTF8Encoding]::new($false))
} finally { Pop-Location }
