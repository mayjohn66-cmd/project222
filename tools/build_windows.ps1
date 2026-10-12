[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GodotExe,
    [string]$ProjectDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory,
    [string]$TemplateDirectory,
    [string]$BuildLabel = 'playtest'
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path -LiteralPath $ProjectDirectory).Path
$engine=(Resolve-Path -LiteralPath $GodotExe).Path
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $projectRoot ('builds/'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'/windows') }
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath (Join-Path $outputRoot 'Project222.exe')) { throw 'Choose a new output folder; an existing build will not be overwritten.' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$logRoot=Join-Path (Split-Path $outputRoot -Parent) ((Split-Path $outputRoot -Leaf)+'-build-logs')
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$revision=(& git -C $projectRoot rev-parse HEAD).Trim()
$trackedChanges=@(& git -C $projectRoot diff --name-only HEAD)
if ($trackedChanges.Count -gt 0) { throw 'Commit tracked source changes before creating the candidate build.' }
$untracked=@(& git -C $projectRoot ls-files --others --exclude-standard)
if (@($untracked | Where-Object { $_ -match '^(art|data|scenes|script|addons|tools)/' -and $_ -notmatch '\.(import|translation|uid)$' }).Count -gt 0) { throw 'Commit new runtime/build sources before building.' }
$buildRoot=Join-Path $logRoot 'source'
if (Test-Path -LiteralPath $buildRoot) { throw 'Choose a new output folder with a clean build staging directory.' }
$sourceArchive=Join-Path $logRoot 'source.zip'
& git -C $projectRoot archive --format=zip ('--output='+$sourceArchive) HEAD project.godot export_presets.cfg art data script scenes addons
if ($LASTEXITCODE -ne 0) { throw 'Cannot archive source revision.' }
[IO.Compression.ZipFile]::ExtractToDirectory($sourceArchive,$buildRoot)
# 빌드 전용 복사본에서만 에디터 연결 서버를 끈다. 원본 프로젝트의 Revvy 설정은 보존한다.
$stagedProject=Join-Path $buildRoot 'project.godot'
$stagedConfig=[IO.File]::ReadAllText($stagedProject).Replace('"res://addons/revvy/plugin.cfg", ','')
[IO.File]::WriteAllText($stagedProject,$stagedConfig)
function Invoke-Engine([string]$Step,[string[]]$EngineArguments) {
    $stdout=Join-Path $logRoot ($Step+'.log')
    $stderr=Join-Path $logRoot ($Step+'.err')
    $process=Start-Process -FilePath $engine -ArgumentList $EngineArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit(300000)) { Stop-Process -Id $process.Id -Force; throw ($Step+' timed out') }
    if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $stdout,$stderr -Pattern 'SCRIPT ERROR','^ERROR:' -Quiet)) { throw ($Step+' failed; see '+$logRoot) }
    Write-Output ($Step+' PASS')
}
Invoke-Engine 'version' @('--version')
$version=(Get-Content -LiteralPath (Join-Path $logRoot 'version.log') -Raw).Trim()
$oldAppData=$env:APPDATA
try {
    if ($TemplateDirectory) {
        $templateRoot=(Resolve-Path -LiteralPath $TemplateDirectory).Path
        $templateVersion=([IO.File]::ReadAllText((Join-Path $templateRoot 'version.txt'))).Trim()
        if (-not $version.StartsWith($templateVersion)) { throw 'Export template version does not match editor version.' }
        $env:APPDATA=Join-Path $logRoot 'engine-runtime'
        $templateTarget=Join-Path $env:APPDATA ('Godot/export_templates/'+$templateVersion)
        New-Item -ItemType Directory -Path $templateTarget -Force | Out-Null
        foreach ($name in @('version.txt','windows_release_x86_64.exe','windows_release_x86_64_console.exe','windows_debug_x86_64.exe','windows_debug_x86_64_console.exe')) {
            Copy-Item -LiteralPath (Join-Path $templateRoot $name) -Destination (Join-Path $templateTarget $name)
        }
    }
    Invoke-Engine 'import1' @('--headless','--path',('"'+$buildRoot+'"'),'--editor','--import','--quit')
    Invoke-Engine 'import2' @('--headless','--path',('"'+$buildRoot+'"'),'--editor','--import','--quit')
    Invoke-Engine 'export' @('--headless','--path',('"'+$buildRoot+'"'),'--export-release','"Windows Desktop"',('"'+(Join-Path $outputRoot 'Project222.exe')+'"'))
    Invoke-Engine 'licenses' @('--headless','--script',('"'+(Join-Path $PSScriptRoot 'write_engine_licenses.gd')+'"'),'--',('"--out='+(Join-Path $outputRoot 'GODOT_LICENSES.txt')+'"'))
} finally { $env:APPDATA=$oldAppData }
foreach ($name in @('Project222.exe','Project222.pck')) {
    if (-not (Test-Path -LiteralPath (Join-Path $outputRoot $name))) { throw ('Missing '+$name) }
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../docs/배포/플레이테스트_안내.txt') -Destination (Join-Path $outputRoot 'README_KO.txt')
$manifest=[ordered]@{label=$BuildLabel;source_commit=$revision;tracked_source_dirty=$false;godot=$version;architecture='x86_64';built_at_utc=[DateTime]::UtcNow.ToString('o');files=@()}
foreach ($name in @('Project222.exe','Project222.pck','README_KO.txt','GODOT_LICENSES.txt')) {
    $file=Join-Path $outputRoot $name
    $manifest.files += [ordered]@{name=$name;bytes=(Get-Item -LiteralPath $file).Length;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()}
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputRoot 'BUILD_INFO.json') -Encoding utf8
$manifest.files | ForEach-Object { $_.sha256+'  '+$_.name } | Set-Content -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.txt') -Encoding utf8
$archive=$outputRoot+'.zip'
if (Test-Path -LiteralPath $archive) { throw 'ZIP already exists; choose a new output folder.' }
Compress-Archive -LiteralPath @((Join-Path $outputRoot 'Project222.exe'),(Join-Path $outputRoot 'Project222.pck'),(Join-Path $outputRoot 'README_KO.txt'),(Join-Path $outputRoot 'GODOT_LICENSES.txt'),(Join-Path $outputRoot 'BUILD_INFO.json'),(Join-Path $outputRoot 'SHA256SUMS.txt')) -DestinationPath $archive
Write-Output ('Windows playtest ZIP: '+$archive)
