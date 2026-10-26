<#
.SYNOPSIS
    Installs essential Windows applications from WinGet, Microsoft Store, and the official Veluna release.

.DESCRIPTION
    INSTALLATION FLOW
      1. Load the application catalog and select all apps or keys passed to -Apps.
      2. For WinGet/Store apps, verify winget.exe and the required source.
      3. Query WinGet's installed inventory; skip a package when its exact ID is detected.
      4. Otherwise install using the exact ID, --silent, non-interactive agreement options,
         and a user installation scope for Git to avoid machine-wide elevation where supported.
      5. For Veluna, check the uninstall registry, query the official GitHub latest-release API,
         select the Windows x64 setup EXE, download it, check its signature status, and run /S.
      6. Record Installed, Skipped, Preview, Unverified, or Failed and continue after individual failures.
      7. Save a text log and CSV report in %LOCALAPPDATA%\EssentialApps.

    SOURCE RULES
      - winget: WinGet Community Repository, source name "winget".
      - ms-store: Microsoft Store, accessed through WinGet source name "msstore".
      - web: Veluna's official GitHub release API and its Windows x64 setup asset.

    SAFETY/REPORTING
      - Does not reset WinGet sources automatically.
      - Does not bypass installer security warnings or ignore WinGet package hash failures.
      - Veluna's /S switch was confirmed in the user's environment. The script checks Authenticode
        status: valid signatures are logged; unsigned files produce a warning; other signature states
        are rejected. The download URL is checked against the official repository's release path.
      - WinGet installs use --silent to suppress installer wizards. Git uses --scope user.
      - Use -Reinstall with selected app keys to force a silent reinstall of apps already detected.
      - WinGet exit code 0 is not treated as proof of installation unless inventory verification succeeds.
        Store inventory may not always be queryable, so results can be marked Unverified.

.PARAMETER Apps
    Optional application keys to install. If omitted, all catalog entries are selected.

.PARAMETER ListOnly
    Show the catalog without installing.

.PARAMETER About
    Display the script's purpose, flow, and output locations.

.PARAMETER WhatIf
    Preview installation actions without changing the system.

.EXAMPLE
    .\Install-EssentialApps.ps1

.EXAMPLE
    .\Install-EssentialApps.ps1 -Apps Git, Vivaldi, Veluna

.EXAMPLE
    .\Install-EssentialApps.ps1 -ListOnly

.EXAMPLE
    .\Install-EssentialApps.ps1 -WhatIf

.EXAMPLE
    .\Install-EssentialApps.ps1 -About

.EXAMPLE
    Get-Help .\Install-EssentialApps.ps1 -Full

.NOTES
    Version: 2.2
    Requires Windows PowerShell 5.1 or later.
    WinGet/App Installer is required for WinGet and Store packages.
    Log:      %LOCALAPPDATA%\EssentialApps\setup.log
    Report:   %LOCALAPPDATA%\EssentialApps\results.csv
    Downloads:%LOCALAPPDATA%\EssentialApps\Downloads
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Apps,
    [switch]$ListOnly,
    [switch]$About,
    [switch]$Reinstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:Root = Join-Path $env:LOCALAPPDATA 'EssentialApps'
$Script:DownloadDir = Join-Path $Script:Root 'Downloads'
$Script:LogFile = Join-Path $Script:Root 'setup.log'
$Script:ReportFile = Join-Path $Script:Root 'results.csv'
$Script:Winget = $null

function Get-WinGetPath {
    # First use the Windows App Execution Alias / PATH entry.
    $command = Get-Command 'winget.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($command) {
        if ($command.Source) { return $command.Source }
        if ($command.Path)   { return $command.Path }
    }

    # Fallback: inspect the registered App Installer package rather than recursively
    # scanning the entire WindowsApps directory.
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        $packages = @(
            Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue
        )
        foreach ($package in $packages) {
            if ($package.InstallLocation) {
                $candidate = Join-Path $package.InstallLocation 'winget.exe'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $candidate
                }
            }
        }
    }

    $aliasPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $aliasPath -PathType Leaf) {
        return $aliasPath
    }

    throw "winget.exe was not found. Install or update 'App Installer' from Microsoft Store, then open a new PowerShell window and verify with: winget --version"
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARN'    { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'Gray' }
    }

    Write-Host $line -ForegroundColor $color
    if (Test-Path -LiteralPath $Script:Root -PathType Container) {
        Add-Content -LiteralPath $Script:LogFile -Value $line
    }
}

function Get-AppCatalog {
    # "ms-store" is a catalog label; Get-WinGetSourceName maps it to "msstore".
    @(
        [pscustomobject]@{ Key = 'Veluna';        Name = 'Veluna';                Source = 'web';      Id = 'rry0ku/veluna' }
        [pscustomobject]@{ Key = 'Vivaldi';       Name = 'Vivaldi';               Source = 'winget';   Id = 'Vivaldi.Vivaldi' }
        [pscustomobject]@{ Key = 'VSCodium';      Name = 'VSCodium';              Source = 'winget';   Id = 'VSCodium.VSCodium' }
        [pscustomobject]@{ Key = 'WinoMail';      Name = 'Wino Mail';             Source = 'ms-store'; Id = '9NCRCVJC50WL' }
        [pscustomobject]@{ Key = 'Wintoys';       Name = 'Wintoys';               Source = 'ms-store'; Id = '9P8LTPGCBZXD' }
        [pscustomobject]@{ Key = 'Radiograph';    Name = 'Radiograph';            Source = 'ms-store'; Id = '9NH1P86H06CG' }
        [pscustomobject]@{ Key = 'Screenbox';     Name = 'Screenbox';              Source = 'winget';   Id = 'Starpine.Screenbox' }
        [pscustomobject]@{ Key = 'UniGetUI';      Name = 'UniGetUI';              Source = 'winget';   Id = 'Devolutions.UniGetUI' }
        [pscustomobject]@{ Key = 'Unigram';       Name = 'Unigram';               Source = 'ms-store'; Id = '9N97ZCKPD60Q' }
        [pscustomobject]@{ Key = 'Git';           Name = 'Git';                   Source = 'winget';   Id = 'Git.Git'; Scope = 'user' }
        [pscustomobject]@{ Key = 'Chrome';        Name = 'Google Chrome';         Source = 'winget';   Id = 'Google.Chrome' }
        [pscustomobject]@{ Key = 'AquileReader';  Name = 'Aquile Reader';         Source = 'ms-store'; Id = '9P08T4JLTQNK' }
        [pscustomobject]@{ Key = 'Firefox';       Name = 'Mozilla Firefox';       Source = 'winget';   Id = 'Mozilla.Firefox' }
        [pscustomobject]@{ Key = 'FluentWeather'; Name = 'FluentWeather';         Source = 'ms-store'; Id = '9PFD136M8457' }
        [pscustomobject]@{ Key = 'FDM';           Name = 'Free Download Manager'; Source = 'winget';   Id = 'SoftDeluxe.FreeDownloadManager' }
        [pscustomobject]@{ Key = 'PowerToys';     Name = 'Microsoft PowerToys';   Source = 'winget';   Id = 'Microsoft.PowerToys' }
    )
}

function Get-WinGetSourceName {
    param([Parameter(Mandatory)][ValidateSet('winget', 'ms-store')][string]$Source)

    if ($Source -eq 'ms-store') { return 'msstore' }
    return 'winget'
}

function Test-WinGetSourceAvailable {
    param([Parameter(Mandatory)][string]$SourceName)

    # Avoid relying on flags not supported by all versions of "source list".
    $output = @(& $Script:Winget source list 2>&1)
    $exitCode = $LASTEXITCODE
    $text = $output -join "`n"

    if ($exitCode -ne 0) {
        throw "Unable to list WinGet sources (exit $exitCode). Output: $text"
    }

    $escaped = [regex]::Escape($SourceName)
    if ($text -notmatch "(?im)^\s*$escaped(?:\s|$)") {
        throw "WinGet source '$SourceName' is missing. Inspect 'winget source list'. If appropriate, run 'winget source reset --force' and then 'winget source update'. This script does not reset sources automatically."
    }
}

function Test-WinGetPackageInstalled {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('winget', 'ms-store')][string]$Source
    )

    $sourceName = Get-WinGetSourceName -Source $Source
    $output = @(
        & $Script:Winget list --id $Id --exact --source $sourceName `
            --accept-source-agreements --disable-interactivity 2>&1
    )
    $exitCode = $LASTEXITCODE
    $text = $output -join "`n"

    if ($exitCode -ne 0) {
        if ($text -match '(?i)source.*(not found|does not exist)|0x8A150012') {
            throw "WinGet could not query source '$sourceName'. Output: $text"
        }
        # A failed inventory query is not proof the app is installed.
        return $false
    }

    return ($text -match [regex]::Escape($Id))
}

function Install-WinGetPackage {
    param(
        [Parameter(Mandatory)][pscustomobject]$App,
        [bool]$Preview = $false,
        [bool]$ForceReinstall = $false
    )

    $sourceName = Get-WinGetSourceName -Source $App.Source
    Test-WinGetSourceAvailable -SourceName $sourceName

    $isInstalled = Test-WinGetPackageInstalled -Id $App.Id -Source $App.Source
    if ($isInstalled -and -not $ForceReinstall) {
        Write-Log "$($App.Name) is already detected as installed. Skipping." 'SUCCESS'
        return 'Skipped'
    }
    if ($isInstalled -and $ForceReinstall) {
        Write-Log "$($App.Name) is installed; -Reinstall was specified, so a silent reinstall will be attempted." 'WARN'
    }

    if ($Preview) {
        Write-Log "WhatIf: would install $($App.Name) from '$sourceName'."
        return 'Preview'
    }

    Write-Log "Installing $($App.Name) from source '$sourceName'."
    $arguments = @(
        'install',
        '--id', $App.Id,
        '--exact',
        '--source', $sourceName,
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )

    # Git for Windows may otherwise choose a machine-wide installer and request UAC.
    # The user scope is requested only for Git, where the package supports it.
    if ($App.PSObject.Properties['Scope'] -and $App.Scope) {
        $arguments += @('--scope', $App.Scope)
    }

    if ($ForceReinstall) {
        $arguments += '--force'
    }

    Write-Log ("WinGet command options: --id {0} --exact --source {1} --silent{2}" -f
        $App.Id, $sourceName,
        $(if ($App.PSObject.Properties['Scope'] -and $App.Scope) { " --scope $($App.Scope)" } else { '' }))

    $output = @(& $Script:Winget @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = $output -join "`n"
    if ($text) { Write-Host $text }

    if ($exitCode -ne 0) {
        $unsignedExitCode = [long]$exitCode
        if ($unsignedExitCode -lt 0) { $unsignedExitCode += 4294967296 }
        $hexCode = '0x{0:X8}' -f [uint32]$unsignedExitCode
        if ($exitCode -eq -1978335214) {
            throw "WinGet source error for '$sourceName' (exit $exitCode / $hexCode). Check 'winget source list'."
        }
        if ($exitCode -eq -1978335212) {
            throw "No matching package was found for ID '$($App.Id)' in '$sourceName' (exit $exitCode / $hexCode). Verify the ID and source."
        }
        throw "WinGet failed for $($App.Name), exit $exitCode ($hexCode). Output: $text"
    }

    if (Test-WinGetPackageInstalled -Id $App.Id -Source $App.Source) {
        Write-Log "$($App.Name) installed and detected in WinGet inventory." 'SUCCESS'
        return 'Installed'
    }

    Write-Log "WinGet returned exit code 0, but inventory did not confirm $($App.Name)." 'WARN'
    return 'Unverified'
}

function Test-VelunaInstalled {
    $registryPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($registryPath in $registryPaths) {
        $entries = @(
            Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue |
                Where-Object {
                    $property = $_.PSObject.Properties['DisplayName']
                    $null -ne $property -and
                    -not [string]::IsNullOrWhiteSpace([string]$property.Value) -and
                    [string]$property.Value -match '^Veluna(?:\s|$)'
                }
        )
        if ($entries.Count -gt 0) { return $true }
    }

    return $false
}

function Install-Veluna {
    param(
        [Parameter(Mandatory)][pscustomobject]$App,
        [bool]$Preview = $false
    )

    if (Test-VelunaInstalled) {
        Write-Log 'Veluna is already installed. Skipping.' 'SUCCESS'
        return 'Skipped'
    }

    if ($Preview) {
        Write-Log 'WhatIf: would query GitHub, download Veluna, and run setup with /S.'
        return 'Preview'
    }

    Write-Log "Querying latest release for $($App.Id)."
    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$($App.Id)/releases/latest" `
        -Headers @{
            'User-Agent' = 'Install-EssentialApps-PowerShell'
            'Accept'     = 'application/vnd.github+json'
        } `
        -ErrorAction Stop

    if (-not $release -or -not $release.assets) {
        throw 'GitHub returned no release assets.'
    }

    # The actual release filename uses underscores, e.g. veluna_0.1.7_x64-setup.exe.
    $asset = $release.assets |
        Where-Object {
            $_.name -match '^veluna_[0-9][^/]*_x64-setup\.exe$' -and
            -not [string]::IsNullOrWhiteSpace([string]$_.browser_download_url)
        } |
        Select-Object -First 1

    if (-not $asset) {
        $names = ($release.assets | ForEach-Object { $_.name }) -join ', '
        throw "No matching Veluna Windows x64 setup found in release '$($release.tag_name)'. Assets: $names"
    }

    # Only download from the official repository's HTTPS release-asset path.
    [uri]$downloadUri = $null
    if (-not [uri]::TryCreate([string]$asset.browser_download_url, [UriKind]::Absolute, [ref]$downloadUri)) {
        throw 'GitHub returned an invalid asset download URL.'
    }
    if ($downloadUri.Scheme -ne 'https' -or
        $downloadUri.Host -ne 'github.com' -or
        $downloadUri.AbsolutePath -notlike '/rry0ku/veluna/releases/download/*') {
        throw "Unexpected Veluna asset URL; refusing to download from '$($downloadUri.Host)$($downloadUri.AbsolutePath)'."
    }

    $installerPath = Join-Path $Script:DownloadDir $asset.name
    Write-Log "Latest Veluna release: $($release.tag_name)"
    Write-Log "Selected asset: $($asset.name)"
    Write-Log "Downloading to: $installerPath"

    Invoke-WebRequest -Uri $downloadUri.AbsoluteUri -OutFile $installerPath -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw 'Download completed but installer file is missing.'
    }

    $installerFile = Get-Item -LiteralPath $installerPath
    if ($installerFile.Length -lt 1MB) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        throw 'Downloaded installer is smaller than 1 MB; refusing to run it.'
    }

    Write-Log "Downloaded $([math]::Round($installerFile.Length / 1MB, 2)) MB." 'SUCCESS'

    $signature = Get-AuthenticodeSignature -FilePath $installerPath
    if ($signature.Status -eq 'Valid') {
        Write-Log "Installer signature is valid. Signer: $($signature.SignerCertificate.Subject)" 'SUCCESS'
    }
    elseif ($signature.Status -eq 'NotSigned') {
        Write-Log 'Installer is not Authenticode-signed. Download URL came from the configured official GitHub release API.' 'WARN'
    }
    else {
        throw "Installer signature status is '$($signature.Status)'; refusing to run it."
    }

    # This /S silent switch was tested by the user with Veluna release v0.1.7.
    Write-Log 'Launching Veluna silent setup (/S).'
    $process = Start-Process -FilePath $installerPath -ArgumentList '/S' -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Veluna silent installer exited with code $($process.ExitCode)."
    }

    if (Test-VelunaInstalled) {
        Write-Log 'Veluna installation verified in the uninstall registry.' 'SUCCESS'
        return 'Installed'
    }

    Write-Log 'Veluna installer returned exit code 0, but registry verification did not find Veluna.' 'WARN'
    return 'Unverified'
}

if ($About) {
@'
Install-EssentialApps.ps1 — Version 2.2

Purpose:
  Install the configured essential apps using WinGet, Microsoft Store, or the official
  Veluna GitHub release.

Logic:
  1. Select apps from the catalog.
  2. Check installed state; skip apps already detected.
  3. Route by source:
       winget   -> winget install --id <ID> --exact --source winget --silent
       ms-store -> winget install --id <StoreID> --exact --source msstore --silent
       web      -> latest Veluna GitHub release -> download x64 setup -> run /S
  4. Accept WinGet agreements, suppress installer wizards, and request user scope for Git.
  5. Capture exit codes, verify installed state where practical, and continue after failures.
  6. Write setup.log and results.csv.

Options:
  -Apps <keys>   Install selected catalog keys only.
  -ListOnly      Display catalog.
  -WhatIf        Preview install actions.
  -Reinstall     Force a silent reinstall for selected apps even if already installed.
  -About         Display this information.

Output:
  %LOCALAPPDATA%\EssentialApps\setup.log
  %LOCALAPPDATA%\EssentialApps\results.csv
  %LOCALAPPDATA%\EssentialApps\Downloads

Examples:
  .\Install-EssentialApps.ps1
  .\Install-EssentialApps.ps1 -Apps Git,Vivaldi,Veluna
  .\Install-EssentialApps.ps1 -Apps VSCodium,Chrome,FDM,Git -Reinstall
  .\Install-EssentialApps.ps1 -ListOnly
  .\Install-EssentialApps.ps1 -WhatIf
'@ | Write-Host
    return
}

# ListOnly/About should not require WinGet or create the logging directory.
if ($ListOnly) {
    Get-AppCatalog | Select-Object Key, Name, Source, Id | Format-Table -AutoSize
    return
}

New-Item -ItemType Directory -Path $Script:DownloadDir -Force | Out-Null
$Script:Winget = Get-WinGetPath

$catalog = @(Get-AppCatalog)
if ($Apps) {
    $unknown = @($Apps | Where-Object { $_ -notin $catalog.Key })
    if ($unknown.Count -gt 0) {
        throw "Unknown application key(s): $($unknown -join ', '). Run with -ListOnly to see valid keys."
    }
    $selected = @($catalog | Where-Object { $_.Key -in $Apps })
}
else {
    $selected = $catalog
}

Write-Log "Starting installation for $($selected.Count) app(s)."
Write-Log "Log file: $Script:LogFile"

$results = [System.Collections.Generic.List[object]]::new()

foreach ($app in $selected) {
    try {
        Write-Log "Processing $($app.Name) [source: $($app.Source)]."

        if ($app.Source -in @('winget', 'ms-store')) {
            $status = Install-WinGetPackage -App $app -Preview:$WhatIfPreference -ForceReinstall:$Reinstall
        }
        elseif ($app.Source -eq 'web') {
            $status = Install-Veluna -App $app -Preview:$WhatIfPreference
        }
        else {
            throw "Unsupported source label '$($app.Source)'."
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

$results | Export-Csv -LiteralPath $Script:ReportFile -NoTypeInformation -Encoding UTF8

$installed = @($results | Where-Object Status -eq 'Installed').Count
$skipped = @($results | Where-Object Status -eq 'Skipped').Count
$preview = @($results | Where-Object Status -eq 'Preview').Count
$unverified = @($results | Where-Object Status -eq 'Unverified').Count
$failed = @($results | Where-Object Status -eq 'Failed').Count

Write-Host "Installed: $installed | Skipped: $skipped | Preview: $preview | Unverified: $unverified | Failed: $failed"
Write-Host "Log: $Script:LogFile"
Write-Host "Report: $Script:ReportFile"

if ($failed -gt 0) { exit 1 }
