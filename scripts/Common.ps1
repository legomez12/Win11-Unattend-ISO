Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Component,
        [ValidateSet('START', 'SUCCESS', 'FAILURE', 'CLEANUP', 'INFO', 'WARN')]
        [string]$Status = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )

    Write-Host "[$Component][$Status] $Message"
}

function Stop-FailFast {
    param([Parameter(Mandatory = $true)][string]$Message)

    throw $Message
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)

    [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Get-7ZipCommand {
    $candidates = @(
        '7z',
        'C:\ProgramData\chocolatey\bin\7z.exe',
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe'
    )

    foreach ($candidate in $candidates) {
        if ($candidate -eq '7z') {
            if (Test-CommandAvailable -Name '7z') {
                return '7z'
            }
            continue
        }

        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Write-CrlfAsciiFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines
    )

    $content = [string]::Join("`r`n", $Lines) + "`r`n"
    [System.IO.File]::WriteAllText($Path, $content, [System.Text.Encoding]::ASCII)
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath.TrimEnd('\', '/'))
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $baseFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFullPath += [System.IO.Path]::DirectorySeparatorChar
    }

    if ($targetFullPath.StartsWith($baseFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $targetFullPath.Substring($baseFullPath.Length)
    }

    return [System.IO.Path]::GetFileName($TargetPath)
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Split-CommaSeparated {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @($Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
