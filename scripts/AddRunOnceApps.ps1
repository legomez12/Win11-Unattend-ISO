param(
    [Parameter(Mandatory = $true)][string]$StageRoot,
    [string]$AppFolders = '',
    [Parameter(Mandatory = $true)][string]$DefaultAppsFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$component = 'AddRunOnceApps'
Write-Log -Component $component -Status START -Message 'Preparing local app installer staging.'

trap {
    Write-Log -Component $component -Status FAILURE -Message $_.Exception.Message
    Write-Log -Component $component -Status CLEANUP -Message 'Application staging cleanup complete.'
    throw
}

$usingDefaultFolder = [string]::IsNullOrWhiteSpace($AppFolders)
$folderList = if ($usingDefaultFolder) {
    @($DefaultAppsFolder)
}
else {
    @(Split-CommaSeparated -Value $AppFolders)
}

if (@($folderList).Count -eq 0) {
    Stop-FailFast -Message 'No app folder paths were provided after parsing AppFolders.'
}

$discovered = @()
foreach ($folder in $folderList) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        if ($usingDefaultFolder) {
            Write-Log -Component $component -Status INFO -Message 'Default ./apps folder missing. Skipping local app staging.'
            Write-Log -Component $component -Status CLEANUP -Message 'Application staging cleanup complete.'
            return [pscustomobject]@{
                RunOnceEntries = @()
                StagedCount    = 0
            }
        }

        Stop-FailFast -Message "User-specified app folder not found: $folder"
    }

    $installers = @(Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { $_.Extension -in @('.exe', '.msi') })
    if (@($installers).Count -eq 0) {
        if ($usingDefaultFolder) {
            Write-Log -Component $component -Status INFO -Message 'Default ./apps folder is empty. Skipping local app staging.'
            Write-Log -Component $component -Status CLEANUP -Message 'Application staging cleanup complete.'
            return [pscustomobject]@{
                RunOnceEntries = @()
                StagedCount    = 0
            }
        }

        Stop-FailFast -Message "User-specified app folder has no .exe/.msi installers: $folder"
    }

    $discovered += [pscustomobject]@{
        RootPath   = $folder
        RootName   = Split-Path -Leaf $folder
        Installers = $installers
    }
}

$appStageDir = Join-Path $StageRoot 'sources/$OEM$/$1/AppInstallers'
New-DirectoryIfMissing -Path $appStageDir

$runOnceEntries = @()

foreach ($group in $discovered) {
    foreach ($installer in $group.Installers) {
        $relative = Get-RelativePath -BasePath $group.RootPath -TargetPath $installer.FullName
        if (-not $usingDefaultFolder -and @($folderList).Count -gt 1) {
            $relative = Join-Path $group.RootName $relative
        }

        $destination = Join-Path $appStageDir $relative
        $destinationParent = Split-Path -Parent $destination
        New-DirectoryIfMissing -Path $destinationParent
        Copy-Item -LiteralPath $installer.FullName -Destination $destination -Force

        $winRelative = $relative.Replace('/', '\\')
        $winPath = "C:\AppInstallers\\$winRelative"

        if ($installer.Extension -ieq '.msi') {
            $command = 'msiexec /i "{0}" /qn /norestart' -f $winPath
            $entryName = "Install MSI $($installer.Name)"
        }
        else {
            $command = '"{0}"' -f $winPath
            $entryName = "Install EXE $($installer.Name)"
        }

        $runOnceEntries += [pscustomobject]@{
            Name    = $entryName
            Command = $command
        }
    }
}

Write-Log -Component $component -Status SUCCESS -Message "Staged $($runOnceEntries.Count) application installers in $appStageDir"
Write-Log -Component $component -Status CLEANUP -Message 'Application staging cleanup complete.'

[pscustomobject]@{
    RunOnceEntries = $runOnceEntries
    StagedCount    = $runOnceEntries.Count
}
