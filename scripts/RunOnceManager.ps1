param(
    [Parameter(Mandatory = $true)][string]$StageRoot,
    [object[]]$BrowserEntries = @(),
    [object[]]$ApplicationEntries = @(),
    [object[]]$AdditionalEntries = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$component = 'RunOnceManager'
Write-Log -Component $component -Status START -Message 'Generating first-logon one-time runner.'

trap {
    Write-Log -Component $component -Status FAILURE -Message $_.Exception.Message
    Write-Log -Component $component -Status CLEANUP -Message 'RunOnce manager cleanup complete.'
    throw
}

$allEntries = @()
$allEntries += @($BrowserEntries)
$allEntries += @($ApplicationEntries)
$allEntries += @($AdditionalEntries)

if ($allEntries.Count -eq 0) {
    Write-Log -Component $component -Status INFO -Message 'No entries provided. Skipping RunOnce script generation.'
    Write-Log -Component $component -Status CLEANUP -Message 'RunOnce manager cleanup complete.'
    return [pscustomobject]@{
        ScriptPath = $null
        EntryCount = 0
    }
}

$startupDir = Join-Path $StageRoot 'sources/$OEM$/$1/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup'
New-DirectoryIfMissing -Path $startupDir

$startupScriptPath = Join-Path $startupDir 'install-apps-once.cmd'

$lines = @(
    '@echo off',
    'setlocal',
    'echo Running first-login installers...',
    ''
)

foreach ($entry in $allEntries) {
    if (-not $entry.Name -or -not $entry.Command) {
        Stop-FailFast -Message 'RunOnce entry is missing Name or Command.'
    }

    $lines += "echo $($entry.Name)..."
    $lines += $entry.Command
    $lines += 'if errorlevel 1 ('
    $lines += '    echo Installer returned a non-zero exit code: %errorlevel%'
    $lines += ') else ('
    $lines += "    echo Completed: $($entry.Name)"
    $lines += ')'
    $lines += ''
}

$lines += 'if exist "C:\BrowserInstallers" rmdir /s /q "C:\BrowserInstallers" >nul 2>&1'
$lines += 'if exist "C:\AppInstallers" rmdir /s /q "C:\AppInstallers" >nul 2>&1'
$lines += 'echo Done.'
$lines += 'del /f /q "%~f0" >nul 2>&1'
$lines += 'endlocal'

Write-CrlfAsciiFile -Path $startupScriptPath -Lines $lines

Write-Log -Component $component -Status SUCCESS -Message "Generated one-time startup runner: $startupScriptPath"
Write-Log -Component $component -Status CLEANUP -Message 'RunOnce manager cleanup complete.'

[pscustomobject]@{
    ScriptPath = $startupScriptPath
    EntryCount = $allEntries.Count
}
