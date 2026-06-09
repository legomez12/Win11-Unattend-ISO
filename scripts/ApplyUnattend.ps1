param(
    [Parameter(Mandatory = $true)][string]$InputIso,
    [Parameter(Mandatory = $true)][string]$OutputIso,
    [Parameter(Mandatory = $true)][string]$UnattendXmlPath,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [string]$OemStageRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$component = 'ApplyUnattend'
$extractDir = Join-Path $WorkingDirectory 'iso-extract'
$isWindowsPlatform = $env:OS -eq 'Windows_NT'
$mountedImage = $null

Write-Log -Component $component -Status START -Message 'Starting unattended ISO processing.'

trap {
    Write-Log -Component $component -Status FAILURE -Message $_.Exception.Message
    if ($mountedImage) {
        Dismount-DiskImage -ImagePath $InputIso -ErrorAction SilentlyContinue | Out-Null
        $mountedImage = $null
    }
    Write-Log -Component $component -Status CLEANUP -Message 'Cleaning temporary extraction directory.'
    if (Test-Path -LiteralPath $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    throw
}

if (-not $isWindowsPlatform) {
    Stop-FailFast -Message 'ApplyUnattend.ps1 must run on Windows.'
}

if (-not (Test-Path -LiteralPath $InputIso -PathType Leaf)) {
    Stop-FailFast -Message "Input ISO not found: $InputIso"
}

if (-not (Test-Path -LiteralPath $UnattendXmlPath -PathType Leaf)) {
    Stop-FailFast -Message "Unattend XML not found: $UnattendXmlPath"
}

$xmlFile = Get-Item -LiteralPath $UnattendXmlPath
if ($xmlFile.Length -le 0) {
    Stop-FailFast -Message "Unattend XML is empty: $UnattendXmlPath"
}

if (-not (Test-CommandAvailable -Name 'oscdimg')) {
    Stop-FailFast -Message 'oscdimg not found. Install Windows ADK Deployment Tools and ensure it is on PATH.'
}

if (Test-Path -LiteralPath $extractDir) {
    Remove-Item -LiteralPath $extractDir -Recurse -Force
}

New-DirectoryIfMissing -Path $extractDir

$sevenZip = Get-7ZipCommand
if ($sevenZip) {
    Write-Log -Component $component -Status INFO -Message "Extracting ISO with 7-Zip: $sevenZip"
    Invoke-NativeCommand -Command $sevenZip -Arguments @('x', $InputIso, "-o$extractDir")
}
elseif ($isWindowsPlatform -and -not $env:CONTAINER_SANDBOX_MOUNT_POINT) {
    Write-Log -Component $component -Status INFO -Message '7-Zip not found. Falling back to native Windows ISO mount.'

    $mountedImage = Mount-DiskImage -ImagePath $InputIso -StorageType ISO -PassThru
    $volume = $mountedImage | Get-Volume | Select-Object -First 1
    if (-not $volume -or -not $volume.DriveLetter) {
        Stop-FailFast -Message 'Mounted ISO did not expose a drive letter.'
    }

    $mountedDrive = "$($volume.DriveLetter):\\"
    if (Test-CommandAvailable -Name 'robocopy') {
        & robocopy $mountedDrive $extractDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -gt 7) {
            Stop-FailFast -Message "robocopy failed with exit code $LASTEXITCODE"
        }
    }
    else {
        Copy-Item -Path (Join-Path $mountedDrive '*') -Destination $extractDir -Recurse -Force
    }

    Dismount-DiskImage -ImagePath $InputIso | Out-Null
    $mountedImage = $null
}
else {
    Stop-FailFast -Message '7z not found. In Windows containers, Mount-DiskImage is unavailable. Install 7-Zip.'
}

Copy-Item -LiteralPath $UnattendXmlPath -Destination (Join-Path $extractDir 'autounattend.xml') -Force
Write-Log -Component $component -Status INFO -Message 'Injected autounattend.xml into extracted ISO root.'

if (-not [string]::IsNullOrWhiteSpace($OemStageRoot) -and (Test-Path -LiteralPath $OemStageRoot -PathType Container)) {
    $stageItems = @(Get-ChildItem -LiteralPath $OemStageRoot -Force)
    if ($stageItems.Count -gt 0) {
        Write-Log -Component $component -Status INFO -Message "Merging staged OEM content from $OemStageRoot"
        foreach ($item in $stageItems) {
            $destination = Join-Path $extractDir $item.Name
            if ($item.PSIsContainer) {
                New-DirectoryIfMissing -Path $destination
                $children = @(Get-ChildItem -LiteralPath $item.FullName -Force)
                foreach ($child in $children) {
                    Copy-Item -LiteralPath $child.FullName -Destination $destination -Recurse -Force
                }
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination $extractDir -Force
            }
        }
    }
}

$biosBootFile = Join-Path $extractDir 'boot/etfsboot.com'
if (-not (Test-Path -LiteralPath $biosBootFile -PathType Leaf)) {
    Stop-FailFast -Message 'Missing BIOS boot file: boot/etfsboot.com'
}

$uefiBootFile = Join-Path $extractDir 'efi/microsoft/boot/efisys.bin'
if (-not (Test-Path -LiteralPath $uefiBootFile -PathType Leaf)) {
    Stop-FailFast -Message 'Missing UEFI boot file: efi/microsoft/boot/efisys.bin'
}

$bootData = "2#p0,e,b$biosBootFile#pEF,e,b$uefiBootFile"
Write-Log -Component $component -Status INFO -Message 'Building custom ISO with oscdimg.'
Invoke-NativeCommand -Command 'oscdimg' -Arguments @(
    '-h',
    '-m',
    '-o',
    '-u2',
    '-udfver102',
    '-lWIN11_CUSTOM',
    "-bootdata:$bootData",
    $extractDir,
    $OutputIso
)

Write-Log -Component $component -Status SUCCESS -Message "Created output ISO: $OutputIso"
Write-Log -Component $component -Status CLEANUP -Message 'Cleaning temporary extraction directory.'
Remove-Item -LiteralPath $extractDir -Recurse -Force

[pscustomobject]@{
    OutputIso = $OutputIso
}
