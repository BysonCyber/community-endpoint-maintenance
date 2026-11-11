#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MainScript = Join-Path $ScriptDir 'Byson-ClientUpdate.ps1'
$BaseDir = 'C:\ProgramData\Byson Cyber\Maintenance'
$RuntimeScript = Join-Path $BaseDir 'Byson-ClientUpdate.ps1'
$TaskName = 'Byson Cyber - Endpoint Maintenance'
$LegacyTaskName = 'Byson Cyber - Client Update'

function Test-StablePwshCandidate {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $versionText = (& $Path -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>$null | Select-Object -First 1)

        if ([string]::IsNullOrWhiteSpace($versionText) -or $versionText -match '-') {
            return $false
        }

        return ([version](($versionText -split '-')[0]) -ge [version]'7.6.0')
    }
    catch {
        return $false
    }
}

function Get-StablePwshPath {
    $candidates = New-Object System.Collections.Generic.List[string]
    [void]$candidates.Add((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'))

    try {
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $appxPath = & $windowsPowerShell -NoProfile -NonInteractive -Command @'
$p = Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($p) {
    Join-Path $p.InstallLocation 'pwsh.exe'
}
'@ 2>$null | Select-Object -First 1

        if ($appxPath) {
            [void]$candidates.Add([string]$appxPath)
        }
    }
    catch { }

    [void]$candidates.Add((Join-Path $PSHOME 'pwsh.exe'))

    try {
        Get-Command pwsh.exe -All -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Source) {
                [void]$candidates.Add($_.Source)
            }
        }
    }
    catch { }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-StablePwshCandidate -Path $candidate) {
            return $candidate
        }
    }

    throw 'A supported non-preview PowerShell 7.6+ runtime could not be found.'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Relaunch-Elevated {
    $pwsh = Get-StablePwshPath

    $elevationArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`""
    )

    Start-Process -FilePath $pwsh -ArgumentList ($elevationArgs -join ' ') -Verb RunAs
    exit
}

function Pause-Installer {
    Write-Host ''
    Read-Host 'Press Enter to continue' | Out-Null
}

function Get-DeployedVersion {
    if (-not (Test-Path $RuntimeScript)) {
        return $null
    }

    try {
        $match = Select-String -Path $RuntimeScript -Pattern '^\s*\$ScriptVersion\s*=\s*[''"]([^''"]+)[''"]' |
            Select-Object -First 1

        if ($match -and $match.Matches.Count -gt 0) {
            return $match.Matches[0].Groups[1].Value
        }
    }
    catch { }

    return $null
}

function Get-InstalledTaskSummary {
    $taskNameUsed = $TaskName
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if (-not $task) {
        $task = Get-ScheduledTask -TaskName $LegacyTaskName -ErrorAction SilentlyContinue
        if ($task) {
            $taskNameUsed = $LegacyTaskName
        }
    }

    if (-not $task) {
        return 'Not installed'
    }

    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskNameUsed -ErrorAction SilentlyContinue
    $profile = 'Unknown'
    $reboot = 'Unknown'

    if ($task.Actions -and $task.Actions.Count -gt 0) {
        $taskActionArguments = $task.Actions[0].Arguments

        if ($taskActionArguments -match '(?i)-Profile\s+(Safe|Client|Aggressive)') {
            $profile = $Matches[1]
        }

        if ($taskActionArguments -match '(?i)-RebootPolicy\s+(Never|IfRequired|EveryRun)') {
            $reboot = $Matches[1]
        }
    }

    $version = Get-DeployedVersion
    $next = if ($taskInfo) { $taskInfo.NextRunTime } else { $null }

    return "v$version | $profile | reboot=$reboot | next=$next"
}

function Show-Header {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '        Byson Cyber Endpoint Maintenance Utility' -ForegroundColor Cyan
    Write-Host '                 Community Beta v0.6.2' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Local-only community edition. No Byson cloud telemetry or remote control.' -ForegroundColor DarkGray
    Write-Host ("Installed: {0}" -f (Get-InstalledTaskSummary)) -ForegroundColor DarkGray
    Write-Host ''
}

function Get-MaintenanceTime {
    param([string]$DefaultTime)

    while ($true) {
        $value = Read-Host "Daily maintenance time in 24-hour HH:mm format [$DefaultTime]"

        if ([string]::IsNullOrWhiteSpace($value)) {
            return $DefaultTime
        }

        if ($value -match '^([0-9]|1[0-9]|2[0-3]):([0-5]\d)$') {
            return ('{0:D2}:{1}' -f [int]$Matches[1], $Matches[2])
        }

        Write-Host 'Invalid time. Examples: 4:30 or 22:00' -ForegroundColor Yellow
    }
}

function Get-RebootPolicy {
    param([string]$Profile)

    if ($Profile -eq 'Safe') {
        return 'Never'
    }

    Write-Host ''
    Write-Host 'Reboot behavior:' -ForegroundColor Cyan
    Write-Host '1. IfRequired  - restart only when maintenance requires it (recommended)'

    if ($Profile -eq 'Aggressive') {
        Write-Host '2. EveryRun    - restart after every scheduled maintenance run'
        Write-Host '3. Never       - never restart automatically'

        $choice = Read-Host 'Choose [1-3]'
        switch ($choice) {
            '2' { return 'EveryRun' }
            '3' { return 'Never' }
            default { return 'IfRequired' }
        }
    }

    Write-Host '2. Never       - never restart automatically'
    $choice = Read-Host 'Choose [1-2]'

    if ($choice -eq '2') {
        return 'Never'
    }

    return 'IfRequired'
}

function Get-RebootDelaySeconds {
    param([string]$RebootPolicy)

    if ($RebootPolicy -eq 'Never') {
        return 300
    }

    while ($true) {
        $value = Read-Host 'Restart countdown in minutes [5]'

        if ([string]::IsNullOrWhiteSpace($value)) {
            return 300
        }

        $minutes = 0
        if ([int]::TryParse($value, [ref]$minutes) -and $minutes -ge 0 -and $minutes -le 1440) {
            return ($minutes * 60)
        }

        Write-Host 'Enter a whole number from 0 to 1440.' -ForegroundColor Yellow
    }
}

function Install-Profile {
    param(
        [ValidateSet('Safe','Client','Aggressive')]
        [string]$Profile
    )

    $defaultTime = if ($Profile -eq 'Safe') { '12:00' } else { '22:00' }
    $dailyTime = Get-MaintenanceTime -DefaultTime $defaultTime
    $rebootPolicy = Get-RebootPolicy -Profile $Profile
    $rebootDelaySeconds = Get-RebootDelaySeconds -RebootPolicy $rebootPolicy

    $firmwareEnabled = $false

    if ($Profile -eq 'Aggressive') {
        Write-Host ''
        $firmware = Read-Host 'Enable guarded BIOS/firmware maintenance on this PC? [y/N]'

        if ($firmware -match '^(?i)y(?:es)?$') {
            Write-Host ''
            Write-Host 'Firmware maintenance can trigger BitLocker recovery and must not be interrupted.' -ForegroundColor Yellow
            Write-Host 'Confirm the BitLocker recovery key is stored somewhere outside this PC.' -ForegroundColor Yellow
            $confirm = Read-Host 'Type Y or YES to confirm'

            if ($confirm -match '^(?i)y(?:es)?$') {
                $firmwareEnabled = $true
            }
            else {
                Write-Host 'Firmware maintenance was NOT enabled.' -ForegroundColor Yellow
            }
        }
    }

    Write-Host ''
    Write-Host 'Selected configuration' -ForegroundColor Cyan
    Write-Host '----------------------'
    Write-Host ("Profile           : {0}" -f $Profile)
    Write-Host ("Daily time        : {0}" -f $dailyTime)
    Write-Host ("Reboot policy     : {0}" -f $rebootPolicy)
    Write-Host ("Restart countdown : {0} minute(s)" -f [math]::Round($rebootDelaySeconds / 60, 0))
    Write-Host ("Firmware          : {0}" -f $(if ($firmwareEnabled) { 'Enabled with guardrails' } else { 'Disabled' }))
    Write-Host 'OEM applications  : Disabled by default'
    Write-Host ''

    $proceed = Read-Host 'Install/update this configuration? [Y/n]'
    if ($proceed -match '^(?i)n(?:o)?$') {
        Write-Host 'Installation canceled.' -ForegroundColor Yellow
        return
    }

    $arguments = @{
        InstallScheduledTask = $true
        ScheduledProfile = $Profile
        ScheduledRebootPolicy = $rebootPolicy
        DailyTime = $dailyTime
        RebootDelaySeconds = $rebootDelaySeconds
    }

    if ($firmwareEnabled) {
        $arguments.ScheduledIncludeFirmware = $true
        $arguments.ScheduledRecoveryKeyEscrowConfirmed = $true
    }

    & $MainScript @arguments
}

function Start-InstalledMaintenance {
    $taskNameUsed = $TaskName
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if (-not $task) {
        $task = Get-ScheduledTask -TaskName $LegacyTaskName -ErrorAction SilentlyContinue
        if ($task) {
            $taskNameUsed = $LegacyTaskName
        }
    }

    if (-not $task) {
        Write-Host 'The Byson maintenance task is not installed.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host 'This starts the installed maintenance profile immediately.' -ForegroundColor Yellow
    Write-Host 'It may install updates and may reboot according to the installed reboot policy.' -ForegroundColor Yellow

    $answer = Read-Host 'Run maintenance now? [y/N]'
    if ($answer -notmatch '^(?i)y(?:es)?$') {
        Write-Host 'Run canceled.'
        return
    }

    Start-ScheduledTask -TaskName $taskNameUsed
    Write-Host 'Maintenance task started.' -ForegroundColor Green
    Write-Host ("Logs: {0}" -f (Join-Path $BaseDir 'Logs'))
}

function Remove-Installation {
    $answer = Read-Host 'Remove the Byson scheduled task and deployed runtime files? [y/N]'
    if ($answer -notmatch '^(?i)y(?:es)?$') {
        Write-Host 'Removal canceled.'
        return
    }

    & $MainScript -RemoveScheduledTask

    foreach ($name in @(
        'Byson-ClientUpdate.ps1',
        'Byson-PwshLauncher.ps1',
        'Byson-RebootPrompt.ps1'
    )) {
        $path = Join-Path $BaseDir $name
        Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
    }

    Write-Host 'Scheduled task and deployed runtime files removed.' -ForegroundColor Green

    $purge = Read-Host 'Also delete local logs and the generated device ID? [y/N]'
    if ($purge -match '^(?i)y(?:es)?$') {
        Remove-Item -Path $BaseDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host 'Local Byson maintenance data removed.' -ForegroundColor Green
    }
    else {
        Write-Host ("Logs/device identity preserved under: {0}" -f $BaseDir)
    }
}

$stablePwsh = Get-StablePwshPath
$currentPwsh = Join-Path $PSHOME 'pwsh.exe'

if (-not (Test-StablePwshCandidate -Path $currentPwsh)) {
    Write-Host 'Installer was started under a PowerShell Preview/RC runtime.' -ForegroundColor Yellow
    Write-Host ("Relaunching under stable PowerShell: {0}" -f $stablePwsh) -ForegroundColor Yellow
    $stableRelaunchArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    Start-Process -FilePath $stablePwsh -ArgumentList ($stableRelaunchArgs -join ' ')
    exit
}

if (-not (Test-IsAdministrator)) {
    Relaunch-Elevated
}

while ($true) {
    Show-Header

    Write-Host '1. Install/update SAFE profile'
    Write-Host '   Defender + normal WinGet updates; Windows/OEM audit; no auto reboot.'
    Write-Host ''
    Write-Host '2. Install/update CLIENT profile'
    Write-Host '   Safe + Windows Update installation; OEM driver audit.'
    Write-Host ''
    Write-Host '3. Install/update AGGRESSIVE profile'
    Write-Host '   Client + OEM driver installs + advanced WinGet behavior.'
    Write-Host ''
    Write-Host '4. Run installed maintenance now'
    Write-Host '5. Show current status'
    Write-Host '6. Cancel pending reboot'
    Write-Host '7. Remove installation'
    Write-Host '8. Exit'
    Write-Host ''

    $choice = Read-Host 'Choose an option [1-8]'

    try {
        switch ($choice) {
            '1' { Install-Profile -Profile Safe; Pause-Installer }
            '2' { Install-Profile -Profile Client; Pause-Installer }
            '3' { Install-Profile -Profile Aggressive; Pause-Installer }
            '4' { Start-InstalledMaintenance; Pause-Installer }
            '5' { & $MainScript -Status; Pause-Installer }
            '6' { & $MainScript -CancelReboot; Pause-Installer }
            '7' { Remove-Installation; Pause-Installer }
            '8' { break }
            default {
                Write-Host 'Invalid selection.' -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
    catch {
        Write-Host ''
        Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Pause-Installer
    }

    if ($choice -eq '8') {
        break
    }
}
