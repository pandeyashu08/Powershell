
<#
.SYNOPSIS
    Installs essential applications on a fresh Windows installation.

.DESCRIPTION
    Installs configured applications using WinGet, Microsoft Store,
    or direct downloads from official web sources.

    Checks whether applications are already installed, skips detected
    installations, records results, and continues when an app fails.

.PARAMETER Apps
    Optional application keys to install. If omitted, all apps are selected.

.PARAMETER ListOnly
    Displays configured applications, sources, and package identifiers.

.PARAMETER About
    Displays script information.

.EXAMPLE
    .\Install-EssentialApps.ps1

.EXAMPLE
    .\Install-EssentialApps.ps1 -Apps Git, Firefox, VSCodium

.EXAMPLE
    .\Install-EssentialApps.ps1 -ListOnly

.EXAMPLE
    .\Install-EssentialApps.ps1 -About

.EXAMPLE
    Get-Help .\Install-EssentialApps.ps1 -Full

.NOTES
    Version: 1.1
    Log/report directory:
    %LOCALAPPDATA%\EssentialApps
#>

#requires -Version 5.1

[CmdletBinding()]
param(
    [string[]]$Apps,
    [switch]$ListOnly,
    [switch]$About
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:Root = Join-Path $env:LOCALAPPDATA 'EssentialApps'
$Script:DownloadDir = Join-Path $Script:Root 'Downloads'
$Script:LogFile = Join-Path $Script:Root 'setup.log'

New-Item -ItemType Directory -Path $Script:DownloadDir -Force |
    Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (
        Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ), $Level, $Message

    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARN'    { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'Gray' }
    }

    Write-Host $line -ForegroundColor $color
    Add-Content -LiteralPath $Script:LogFile -Value $line
}

function Get-AppCatalog {
    @(
        [pscustomobject]@{
            Key = 'Veluna'
            Name = 'Veluna'
            Source = 'web'
            Id = 'rry0ku/veluna'
        }
        [pscustomobject]@{
            Key = 'Vivaldi'
            Name = 'Vivaldi'
            Source = 'winget'
            Id = 'Vivaldi.Vivaldi'
        }
        [pscustomobject]@{
            Key = 'VSCodium'
            Name = 'VSCodium'
            Source = 'winget'
            Id = 'VSCodium.VSCodium'
        }
        [pscustomobject]@{
            Key = 'WinoMail'
            Name = 'Wino Mail'
            Source = 'ms-store'
            Id = '9NCRCVJC50WL'
        }
        [pscustomobject]@{
            Key = 'Wintoys'
            Name = 'Wintoys'
            Source = 'ms-store'
            Id = '9P8LTPGCBZXD'
        }
        [pscustomobject]@{
            Key = 'Radiograph'
            Name = 'Radiograph'
            Source = 'ms-store'
            Id = '9NH1P86H06CG'
        }
        [pscustomobject]@{
            Key = 'Screenbox'
            Name = 'Screenbox'
            Source = 'winget'
            Id = 'Starpine.Screenbox'
        }
        [pscustomobject]@{
            Key = 'UniGetUI'
            Name = 'UniGetUI'
            Source = 'winget'
            Id = 'Devolutions.UniGetUI'
        }
        [pscustomobject]@{
            Key = 'Unigram'
            Name = 'Unigram'
            Source = 'winget'
            Id = 'Telegram.Unigram'
        }
        [pscustomobject]@{
            Key = 'Git'
            Name = 'Git'
            Source = 'winget'
            Id = 'Git.Git'
        }
        [pscustomobject]@{
            Key = 'Chrome'
            Name = 'Google Chrome'
            Source = 'winget'
            Id = 'Google.Chrome'
        }
        [pscustomobject]@{
            Key = 'AquileReader'
            Name = 'Aquile Reader'
            Source = 'ms-store'
            Id = '9P08T4JLTQNK'
        }
        [pscustomobject]@{
            Key = 'Firefox'
            Name = 'Firefox'
            Source = 'winget'
            Id = 'Mozilla.Firefox'
        }
        [pscustomobject]@{
            Key = 'FluentWeather'
            Name = 'FluentWeather'
            Source = 'ms-store'
            Id = '9PFD136M8457'
        }
        [pscustomobject]@{
            Key = 'FDM'
            Name = 'Free Download Manager'
            Source = 'winget'
            Id = 'SoftDeluxe.FreeDownloadManager'
        }
        [pscustomobject]@{
            Key = 'PowerToys'
            Name = 'Microsoft PowerToys'
            Source = 'winget'
            Id = 'Microsoft.PowerToys'
        }
    )
}

function Test-WinGet {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'WinGet is unavailable. Install or repair Microsoft App Installer.'
    }
}

function Test-PackageInstalled {
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet('winget', 'ms-store')]
        [string]$Source
    )

    $output = @(
        & winget.exe list --id $Id --exact --source $Source `
            --disable-interactivity 2>$null
    ) -join "`n"

    $escapedId = [regex]::Escape($Id)

    return $output -match "(?im)(?<![\w.-])$escapedId(?![\w.-])"
}

function Install-WinGetPackage {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$App
    )

    Test-WinGet

    if (Test-PackageInstalled -Id $App.Id -Source $App.Source) {
        Write-Log "$($App.Name) is already installed. Skipping." 'SUCCESS'
        return 'Skipped'
    }

    Write-Log "Installing $($App.Name) from $($App.Source)."

    $arguments = @(
        'install',
        '--id', $App.Id,
        '--exact',
        '--source', $App.Source,
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )

    & winget.exe @arguments
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "WinGet failed for $($App.Name), exit code $exitCode."
    }

    # Confirm the package appears in the installed inventory.
    if (-not (Test-PackageInstalled -Id $App.Id -Source $App.Source)) {
        Write-Log "WinGet completed but could not confirm $($App.Name)." 'WARN'
        return 'Unverified'
    }

    Write-Log "$($App.Name) installed successfully." 'SUCCESS'
    return 'Installed'
}

function Test-VelunaInstalled {
    $paths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $paths) {
        $items = @(
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -and
                    $_.DisplayName -match '^Veluna(?:\s|$)'
                }
        )

        if ($items.Count -gt 0) {
            return $true
        }
    }

    return $false
}

function Install-Veluna {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$App
    )

    if (Test-VelunaInstalled) {
        Write-Log 'Veluna is already installed. Skipping.' 'SUCCESS'
        return 'Skipped'
    }

    Write-Log 'Checking the latest Veluna GitHub release.'

    $releaseUrl = "https://api.github.com/repos/$($App.Id)/releases/latest"

    $release = Invoke-RestMethod -Uri $releaseUrl `
        -Headers @{ 'User-Agent' = 'EssentialApps-PowerShell' }

    $asset = $release.assets |
        Where-Object {
            $_.name -match '^veluna-.*-x64-setup\.exe$'
        } |
        Select-Object -First 1

    if (-not $asset) {
        throw "No Windows x64 setup EXE found in release $($release.tag_name)."
    }

    $installer = Join-Path $Script:DownloadDir $asset.name

    Write-Log "Downloading Veluna $($release.tag_name)."

    Invoke-WebRequest -Uri $asset.browser_download_url `
        -OutFile $installer

    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw 'The Veluna installer was not downloaded.'
    }

    if ((Get-Item -LiteralPath $installer).Length -lt 1MB) {
        throw 'The installer is unexpectedly small. Refusing to launch it.'
    }

    Write-Log "Downloaded installer: $installer" 'SUCCESS'
    Write-Log 'Launching Veluna setup interactively.'

    $process = Start-Process -FilePath $installer -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Veluna setup exited with code $($process.ExitCode)."
    }

    if (Test-VelunaInstalled) {
        Write-Log 'Veluna installation verified.' 'SUCCESS'
        return 'Installed'
    }

    Write-Log 'Installer exited successfully, but Veluna could not be verified.' 'WARN'
    return 'Unverified'
}

if ($About) {
    @'
Install-EssentialApps.ps1
Version: 1.1

Purpose:
  Set up essential applications on a fresh Windows installation.

Sources:
  winget   - WinGet repository
  ms-store - Microsoft Store through WinGet
  web      - Veluna official GitHub release

Features:
  - Checks existing installations
  - Skips detected packages
  - Downloads and launches the Veluna installer
  - Logs successes and failures
  - Exports a CSV results report

Files:
  %LOCALAPPDATA%\EssentialApps\setup.log
  %LOCALAPPDATA%\EssentialApps\results.csv
  %LOCALAPPDATA%\EssentialApps\Downloads\

Help:
  Get-Help .\Install-EssentialApps.ps1 -Full
'@ | Write-Host
    return
}

$catalog = @(Get-AppCatalog)

if ($ListOnly) {
    $catalog |
        Select-Object Key, Name, Source, Id |
        Format-Table -AutoSize
    return
}

if ($Apps) {
    $unknown = @(
        $Apps | Where-Object {
            $_ -notin $catalog.Key
        }
    )

    if ($unknown.Count -gt 0) {
        throw "Unknown application key(s): $($unknown -join ', '). Use -ListOnly."
    }

    $selected = @(
        $catalog | Where-Object {
            $_.Key -in $Apps
        }
    )
}
else {
    $selected = $catalog
}

Write-Log "Starting setup for $($selected.Count) application(s)."
Write-Log "Log file: $Script:LogFile"

$results = [System.Collections.Generic.List[object]]::new()

foreach ($app in $selected) {
    try {
        Write-Log "Processing $($app.Name) [$($app.Source)]."

        if ($app.Source -in @('winget', 'ms-store')) {
            $status = Install-WinGetPackage -App $app
        }
        elseif ($app.Source -eq 'web') {
            $status = Install-Veluna -App $app
        }
        else {
            throw "Unsupported source: $($app.Source)"
        }

        $results.Add([pscustomobject]@{
            Application = $app.Name
            Source      = $app.Source
            Status      = $status
            Details     = ''
        })
    }
    catch {
        Write-Log "$($app.Name): $($_.Exception.Message)" 'ERROR'

        $results.Add([pscustomobject]@{
            Application = $app.Name
            Source      = $app.Source
            Status      = 'Failed'
            Details     = $_.Exception.Message
        })
    }
}

Write-Host "`n========== INSTALLATION SUMMARY ==========" -ForegroundColor Cyan
$results | Format-Table Application, Source, Status -AutoSize

$report = Join-Path $Script:Root 'results.csv'

$results | Export-Csv -LiteralPath $report -NoTypeInformation

$installed = @($results | Where-Object Status -eq 'Installed').Count
$skipped = @($results | Where-Object Status -eq 'Skipped').Count
$unverified = @($results | Where-Object Status -eq 'Unverified').Count
$failed = @($results | Where-Object Status -eq 'Failed').Count

Write-Host "Installed: $installed | Skipped: $skipped | Unverified: $unverified | Failed: $failed"
Write-Host "Log: $Script:LogFile"
Write-Host "Report: $report"

if ($failed -gt 0) {
    exit 1
}
