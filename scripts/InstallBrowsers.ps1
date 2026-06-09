param(
    [Parameter(Mandatory = $true)][string]$BrowserConfigPath,
    [Parameter(Mandatory = $true)][string]$StageRoot,
    [ValidateSet('chrome', 'opera', 'firefox', 'brave', 'all')]
    [string[]]$Browsers = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$component = 'InstallBrowsers'
Write-Log -Component $component -Status START -Message 'Preparing browser installer staging.'

trap {
    Write-Log -Component $component -Status FAILURE -Message $_.Exception.Message
    Write-Log -Component $component -Status CLEANUP -Message 'Browser staging cleanup complete.'
    throw
}

if (@($Browsers).Count -eq 0) {
    Write-Log -Component $component -Status INFO -Message 'No browsers selected. Skipping browser staging.'
    Write-Log -Component $component -Status CLEANUP -Message 'Browser staging cleanup complete.'
    return [pscustomobject]@{
        SelectedBrowsers = @()
        RunOnceEntries   = @()
    }
}

if (-not (Test-Path -LiteralPath $BrowserConfigPath -PathType Leaf)) {
    Stop-FailFast -Message "Browser configuration file not found: $BrowserConfigPath"
}

$configRaw = Get-Content -LiteralPath $BrowserConfigPath -Raw
$config = $configRaw | ConvertFrom-Json

if (-not $config -or -not $config.browsers) {
    Stop-FailFast -Message "Browser configuration is invalid: $BrowserConfigPath"
}

 $browserMap = @{}
foreach ($item in $config.browsers) {
    if (-not $item.name -or -not $item.url -or -not $item.installerFile -or -not $item.silentArgs -or -not $item.displayName) {
        Stop-FailFast -Message "Browser configuration entry is missing required fields in: $BrowserConfigPath"
    }

    $browserMap[$item.name] = $item
}

$selected = if ($Browsers -contains 'all') {
    @($browserMap.Keys | Sort-Object)
}
else {
    @($Browsers | Select-Object -Unique)
}

foreach ($browser in $selected) {
    if (-not $browserMap.ContainsKey($browser)) {
        Stop-FailFast -Message "Browser '$browser' is not defined in configuration file: $BrowserConfigPath"
    }
}

$browserStageDir = Join-Path $StageRoot 'sources/$OEM$/$1/BrowserInstallers'
New-DirectoryIfMissing -Path $browserStageDir

$runOnceEntries = @()
$linkLines = @()

foreach ($browser in $selected) {
    $meta = $browserMap[$browser]
    $outputPath = Join-Path $browserStageDir $meta.installerFile

    Write-Log -Component $component -Status INFO -Message "Downloading $browser installer."
    Invoke-WebRequest -Uri $meta.url -OutFile $outputPath

    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        Stop-FailFast -Message "Failed to download installer for $browser"
    }

    $file = Get-Item -LiteralPath $outputPath
    if ($file.Length -le 0) {
        Stop-FailFast -Message "Downloaded installer for $browser is empty"
    }

    $linkLines += "$browser = $($meta.url)"
    $runOnceEntries += [pscustomobject]@{
        Name    = "Install $($meta.displayName)"
        Command = "C:\BrowserInstallers\$($meta.installerFile) $($meta.silentArgs)"
    }
}

$linksFile = Join-Path $browserStageDir 'download-links.txt'
Write-CrlfAsciiFile -Path $linksFile -Lines $linkLines

Write-Log -Component $component -Status SUCCESS -Message "Staged browser installers in $browserStageDir"
Write-Log -Component $component -Status CLEANUP -Message 'Browser staging cleanup complete.'

[pscustomobject]@{
    SelectedBrowsers = $selected
    RunOnceEntries   = $runOnceEntries
}
