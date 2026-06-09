param(
    [Parameter(Mandatory = $true, Position = 0)][string]$InputIso,
    [Parameter(Mandatory = $true, Position = 1)][string]$OutputIso,
    [ValidateSet('chrome', 'opera', 'firefox', 'brave', 'all')]
    [string[]]$Browsers = @(),
    [string]$AppFolders = '',
    [string]$SettingsConfigPath = '',
    [string]$BrowserConfigPath = '',
    [string]$UnattendUri = '',
    [string]$UnattendXmlPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    Split-Path -Parent $PSCommandPath
}
elseif (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    throw 'Unable to determine script root for build-winiso.ps1'
}

if ([string]::IsNullOrWhiteSpace($SettingsConfigPath)) {
    $SettingsConfigPath = Join-Path $scriptRoot 'config/orchestrator.json'
}

. (Join-Path $scriptRoot 'scripts/Common.ps1')

if (-not (Test-Path -LiteralPath $SettingsConfigPath -PathType Leaf)) {
    Stop-FailFast -Message "Settings config not found: $SettingsConfigPath"
}

$orchestratorSettings = Get-Content -LiteralPath $SettingsConfigPath -Raw | ConvertFrom-Json

function Resolve-SettingsPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $scriptRoot $Path
}

$requiredSettingKeys = @(
    'componentName',
    'browserConfigPath',
    'unattendUri',
    'downloadedUnattendFileName',
    'workingRootName',
    'stageRootName',
    'defaultAppsFolder'
)

foreach ($key in $requiredSettingKeys) {
    $value = $orchestratorSettings.$key
    if ([string]::IsNullOrWhiteSpace($value)) {
        Stop-FailFast -Message "Missing required setting '$key' in $SettingsConfigPath"
    }
}

if ($null -eq $orchestratorSettings.scripts) {
    Stop-FailFast -Message "Missing required object 'scripts' in $SettingsConfigPath"
}

foreach ($scriptKey in @('installBrowsers', 'addRunOnceApps', 'runOnceManager', 'applyUnattend')) {
    $value = $orchestratorSettings.scripts.$scriptKey
    if ([string]::IsNullOrWhiteSpace($value)) {
        Stop-FailFast -Message "Missing required script setting '$scriptKey' in $SettingsConfigPath"
    }
}

$component = $orchestratorSettings.componentName
$isWindowsPlatform = $env:OS -eq 'Windows_NT'

$resolvedBrowserConfigPath = if (-not [string]::IsNullOrWhiteSpace($BrowserConfigPath)) { $BrowserConfigPath } else { Resolve-SettingsPath -Path $orchestratorSettings.browserConfigPath }
$resolvedUnattendUri = if (-not [string]::IsNullOrWhiteSpace($UnattendUri)) { $UnattendUri } else { $orchestratorSettings.unattendUri }

$installBrowsersScript = Resolve-SettingsPath -Path $orchestratorSettings.scripts.installBrowsers
$addRunOnceAppsScript = Resolve-SettingsPath -Path $orchestratorSettings.scripts.addRunOnceApps
$runOnceManagerScript = Resolve-SettingsPath -Path $orchestratorSettings.scripts.runOnceManager
$applyUnattendScript = Resolve-SettingsPath -Path $orchestratorSettings.scripts.applyUnattend

$workingRoot = Join-Path $env:TEMP $orchestratorSettings.workingRootName
$stageRoot = Join-Path $workingRoot $orchestratorSettings.stageRootName
$defaultAppsFolder = Resolve-SettingsPath -Path $orchestratorSettings.defaultAppsFolder

$downloadedUnattendPath = Join-Path (Get-Location) $orchestratorSettings.downloadedUnattendFileName
$cleanupDownloadedUnattend = $false

Write-Log -Component $component -Status START -Message 'Starting orchestration.'

trap {
    Write-Log -Component $component -Status FAILURE -Message $_.Exception.Message
    Write-Log -Component $component -Status CLEANUP -Message 'Running orchestrator cleanup.'

    if ($cleanupDownloadedUnattend -and (Test-Path -LiteralPath $downloadedUnattendPath -PathType Leaf)) {
        Remove-Item -LiteralPath $downloadedUnattendPath -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $workingRoot) {
        Remove-Item -LiteralPath $workingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    throw
}

if (-not $isWindowsPlatform) {
    Stop-FailFast -Message 'This script must run on Windows. Use build-winiso.sh for Linux/WSL.'
}

if (-not (Test-Path -LiteralPath $InputIso -PathType Leaf)) {
    Stop-FailFast -Message "Input ISO not found: $InputIso"
}

foreach ($childScript in @($installBrowsersScript, $addRunOnceAppsScript, $runOnceManagerScript, $applyUnattendScript)) {
    if (-not (Test-Path -LiteralPath $childScript -PathType Leaf)) {
        Stop-FailFast -Message "Required child script not found: $childScript"
    }
}

if (Test-Path -LiteralPath $OutputIso -PathType Leaf) {
    Write-Log -Component $component -Status INFO -Message "Removing existing output ISO: $OutputIso"
    Remove-Item -LiteralPath $OutputIso -Force
}

if (Test-Path -LiteralPath $workingRoot) {
    Write-Log -Component $component -Status INFO -Message "Removing previous working directory: $workingRoot"
    Remove-Item -LiteralPath $workingRoot -Recurse -Force
}

New-DirectoryIfMissing -Path $stageRoot

$resolvedUnattendPath = ''
if (-not [string]::IsNullOrWhiteSpace($UnattendXmlPath)) {
    if (-not (Test-Path -LiteralPath $UnattendXmlPath -PathType Leaf)) {
        Stop-FailFast -Message "Provided UnattendXmlPath not found: $UnattendXmlPath"
    }

    $resolvedUnattendPath = $UnattendXmlPath
    Write-Log -Component $component -Status INFO -Message "Using local unattended XML: $resolvedUnattendPath"
}
else {
    if (Test-Path -LiteralPath $downloadedUnattendPath -PathType Leaf) {
        Write-Log -Component $component -Status INFO -Message 'Existing autounattend.xml found, deleting to avoid confusion.'
        Remove-Item -LiteralPath $downloadedUnattendPath -Force
    }

    Write-Log -Component $component -Status INFO -Message 'Downloading autounattend.xml.'
    Invoke-WebRequest -Uri $resolvedUnattendUri -OutFile $downloadedUnattendPath

    if (-not (Test-Path -LiteralPath $downloadedUnattendPath -PathType Leaf)) {
        Stop-FailFast -Message 'autounattend.xml was not created by Invoke-WebRequest'
    }

    $downloadedFile = Get-Item -LiteralPath $downloadedUnattendPath
    if ($downloadedFile.Length -le 0) {
        Stop-FailFast -Message 'autounattend.xml is empty'
    }

    $resolvedUnattendPath = $downloadedUnattendPath
    $cleanupDownloadedUnattend = $true
}

$browserResult = & $installBrowsersScript -BrowserConfigPath $resolvedBrowserConfigPath -StageRoot $stageRoot -Browsers $Browsers
$appResult = & $addRunOnceAppsScript -StageRoot $stageRoot -AppFolders $AppFolders -DefaultAppsFolder $defaultAppsFolder

$browserEntries = @($browserResult.RunOnceEntries)
$appEntries = @($appResult.RunOnceEntries)

if ($browserEntries.Count -gt 0 -or $appEntries.Count -gt 0) {
    & $runOnceManagerScript -StageRoot $stageRoot -BrowserEntries $browserEntries -ApplicationEntries $appEntries | Out-Null
}
else {
    Write-Log -Component $component -Status INFO -Message 'No browser or app entries generated. RunOnce startup script not required.'
}

& $applyUnattendScript -InputIso $InputIso -OutputIso $OutputIso -UnattendXmlPath $resolvedUnattendPath -WorkingDirectory $workingRoot -OemStageRoot $stageRoot | Out-Null

Write-Log -Component $component -Status SUCCESS -Message "Done. Output ISO: $OutputIso"
Write-Log -Component $component -Status CLEANUP -Message 'Running orchestrator cleanup.'

if ($cleanupDownloadedUnattend -and (Test-Path -LiteralPath $downloadedUnattendPath -PathType Leaf)) {
    Remove-Item -LiteralPath $downloadedUnattendPath -Force
}

if (Test-Path -LiteralPath $workingRoot) {
    Remove-Item -LiteralPath $workingRoot -Recurse -Force
}