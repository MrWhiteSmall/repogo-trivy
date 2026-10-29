$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw '此入口仅整理 Windows x64。其他架构请查看官方文档。' }
$expected = '1051f49cb22d5284f43425f72aad9cda63ca12ceb92e7caa06903490c82dc9bf'
$runtime = Join-Path $PSScriptRoot '.runtime'
$null = New-Item -ItemType Directory -Force -Path "$runtime/downloads", "$runtime/bin", "$runtime/reports"
$archive = "$runtime/downloads/trivy_0.76.1_windows-64bit.zip"
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/aquasecurity/trivy/releases/download/v0.76.1/trivy_0.76.1_windows-64bit.zip' -OutFile "$archive.part"
    Move-Item -LiteralPath "$archive.part" -Destination $archive -Force
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant() -ne $expected) { throw '下载包校验不一致，已停止。将该缓存文件移出后重试，不要跳过校验。' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $entry = $zip.GetEntry('trivy.exe')
    if ($null -eq $entry) { throw '官方包内未找到 trivy.exe' }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, "$runtime/bin/trivy.exe", $true)
} finally { $zip.Dispose() }
$exe = "$runtime/bin/trivy.exe"
& $exe --version
if ($LASTEXITCODE -ne 0) { throw '程序版本读取失败' }
$previousConfig = $env:TRIVY_CONFIG
try {
    $env:TRIVY_CONFIG = "$runtime/no-default-config.yaml"
    $summary = @()
    foreach ($stage in @('before','after')) {
        $target = "$runtime/practice-$stage"
        $null = New-Item -ItemType Directory -Force -Path $target
        Copy-Item -LiteralPath "$PSScriptRoot/samples/$stage.txt" -Destination "$target/demo.txt" -Force
        $report = "$runtime/reports/$stage.json"
        & $exe --cache-dir "$runtime/cache" fs --scanners secret --skip-version-check --disable-telemetry --offline-scan --secret-config "$PSScriptRoot/practice-secret.yaml" --format json --exit-code 1 --output $report $target
        $code = $LASTEXITCODE
        if (-not (Test-Path -LiteralPath $report)) { throw '未生成报告，请阅读上方错误' }
        $data = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
        $findings = @($data.Results | ForEach-Object { $_.Secrets } | Where-Object { $null -ne $_ })
        $want = if ($stage -eq 'before') { 1 } else { 0 }
        if ($code -ne $want -or $findings.Count -ne $want) { throw "$stage 未符合练习预期：退出码 $code / 发现 $($findings.Count)" }
        if ($stage -eq 'before' -and $findings[0].RuleID -ne 'repogo-demo-only') { throw '命中规则与练习不一致' }
        $summary += [pscustomobject]@{stage=$stage;exit_code=$code;findings=$findings.Count}
        Write-Host "$stage : 发现 $($findings.Count) 项 / 退出码 $code"
    }
    $summary | ConvertTo-Json | Set-Content -LiteralPath "$runtime/reports/summary.json" -Encoding UTF8
    Write-Host '练习通过：1 到 0，仅验证自定义假数据规则，不代表真实项目无泄漏。报告在 .runtime/reports/'
} finally { $env:TRIVY_CONFIG = $previousConfig }
