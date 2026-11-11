#requires -Version 7.6
#requires -PSEdition Core
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Byson Cyber client workstation update/maintenance script.

.DESCRIPTION
    Safe default behavior:
      - Logs system/update activity under C:\ProgramData\Byson Cyber\Maintenance\Logs
      - Updates Microsoft Defender signatures when Defender cmdlets are available
      - Updates normal WinGet-managed applications
      - Scans Windows Update and reports pending non-optional software updates
      - Reports whether a reboot is pending

    Profiles:
      - Manual     : no preset; explicit switches control behavior
      - Safe       : Defender + normal WinGet updates; Windows/OEM scan only; no automatic reboot
      - Client     : Safe + installs Windows Updates + 5-minute reboot warning; OEM drivers scan only
      - Aggressive : Client + installs OEM drivers + WinGet include-unknown/include-pinned/force
                     + 5-minute reboot warning
      - No profile automatically enables OEM applications or BIOS/firmware.

    Optional behavior:
      - -InstallWindowsUpdates : installs applicable non-browse-only Windows software updates
      - -InstallOEMUpdates     : installs supported OEM driver updates when an OEM adapter is available
      - -IncludeOEMApplications : also permits OEM vendor application updates; disabled by default
      - -IncludeFirmware       : expands Dell updates to BIOS + firmware. Requires
                                -AcknowledgeFirmwareRisk and, when BitLocker is active,
                                -RecoveryKeyEscrowConfirmed. Firmware preflight also requires
                                AC power and no pending reboot.
      - -AcknowledgeFirmwareRisk: explicit technician acknowledgement required for firmware mode
      - -RecoveryKeyEscrowConfirmed : technician attests that the BitLocker recovery key is
                                available outside the endpoint when BitLocker is active
      - -IncludeUnknown        : tells WinGet to include packages with unknown installed versions
      - -IncludePinned         : tells WinGet to include non-blocking pinned packages
      - -ForceWinget           : tells WinGet to continue through non-security-related issues
      - -AuditOnly             : scans/reports only; installs nothing and never schedules a reboot
      - -Profile               : execution preset. Manual (default), Safe, Client, or Aggressive
      - -InstallScheduledTask  : installs this script to ProgramData and creates a scheduled task
      - -ScheduledProfile      : Safe, Client, or Aggressive profile used by the installed task
      - -ScheduledIncludeFirmware : Aggressive scheduled task may also include BIOS/firmware.
                                    Existing AC/BitLocker/reboot preflight still applies.
      - -ScheduledRecoveryKeyEscrowConfirmed : technician confirms BitLocker recovery material
                                    is available outside the endpoint for scheduled firmware use.
      - -RemoveScheduledTask   : removes the scheduled task
      - -ShowVersion           : prints the running script version and exits
      - -Status                : shows deployed version, scheduled profile/action,
                                reboot policy, task state, next/last run, last task result,
                                and most recent executed version from logs
      - -CancelReboot          : cancels a currently pending Byson/Windows shutdown countdown
      - -RebootPolicy         : Never, IfRequired, or EveryRun
      - -RebootIfRequired      : backward-compatible alias for -RebootPolicy IfRequired
      - -RebootDelaySeconds    : countdown before the restart; default 300 seconds (5 minutes)
      - -ScheduledRebootPolicy : ProfileDefault, Never, IfRequired, or EveryRun
                                EveryRun is allowed only with the Aggressive scheduled profile
      - -MinFreeDiskGB         : minimum free space on the Windows system drive before installs;
                                default 10 GB. Scans still run when installs are deferred.
      - -IgnoreDiskSpaceGuard  : technician override for the free-space installation guard
      - -LogRetentionDays      : local Byson log/JSON retention; default 30 days

.NOTES
    Version: 0.6.2
    Requires PowerShell 7.6+ (current LTS baseline).
    Reboot behavior is controlled by -RebootPolicy. A cancelable five-minute restart prompt is used by default when an automatic restart is scheduled.
    Community edition: local execution only. No Byson cloud service, telemetry, or remote command channel is included.
    Copyright (c) 2026 Byson Cyber LLC. Licensed under the MIT License; see LICENSE.
#>

[CmdletBinding()]
param(
    [ValidateSet('Manual','Safe','Client','Aggressive')]
    [string]$Profile = 'Manual',
    [switch]$AuditOnly,
    [switch]$InstallWindowsUpdates,
    [switch]$InstallOEMUpdates,
    [switch]$IncludeOEMApplications,
    [switch]$IncludeFirmware,
    [switch]$AcknowledgeFirmwareRisk,
    [switch]$RecoveryKeyEscrowConfirmed,
    [switch]$IncludeUnknown,
    [switch]$IncludePinned,
    [switch]$ForceWinget,
    [switch]$InstallScheduledTask,
    [ValidateSet('Safe','Client','Aggressive')]
    [string]$ScheduledProfile = 'Safe',
    [switch]$ScheduledIncludeFirmware,
    [switch]$ScheduledRecoveryKeyEscrowConfirmed,
    [switch]$RemoveScheduledTask,
    [switch]$ShowVersion,
    [switch]$Status,
    [switch]$CancelReboot,
    [ValidateSet('Never','IfRequired','EveryRun')]
    [string]$RebootPolicy = 'Never',
    [switch]$RebootIfRequired,
    [ValidateSet('ProfileDefault','Never','IfRequired','EveryRun')]
    [string]$ScheduledRebootPolicy = 'ProfileDefault',
    [ValidateRange(0,86400)]
    [int]$RebootDelaySeconds = 300,
    [ValidateRange(1,1024)]
    [int]$MinFreeDiskGB = 10,
    [switch]$IgnoreDiskSpaceGuard,
    [ValidateRange(1,3650)]
    [int]$LogRetentionDays = 30,
    [ValidatePattern('^(?:[01]\d|2[0-3]):[0-5]\d$')]
    [string]$DailyTime = '12:00'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:DailyTimeExplicitlySet = $PSBoundParameters.ContainsKey('DailyTime')
$script:RebootPolicyExplicitlySet = $PSBoundParameters.ContainsKey('RebootPolicy')

# Backward compatibility for existing commands.
if ($RebootIfRequired -and -not $script:RebootPolicyExplicitlySet) {
    $RebootPolicy = 'IfRequired'
    $script:RebootPolicyExplicitlySet = $true
}

# Profiles intentionally never enable OEM applications or firmware.
# Explicit switches remain available for technician-controlled maintenance.
switch ($Profile) {
    'Safe' {
        if (-not $script:RebootPolicyExplicitlySet) {
            $RebootPolicy = 'Never'
        }
    }
    'Client' {
        $InstallWindowsUpdates = $true
        if (-not $script:RebootPolicyExplicitlySet) {
            $RebootPolicy = 'IfRequired'
        }
    }
    'Aggressive' {
        $InstallWindowsUpdates = $true
        $InstallOEMUpdates = $true
        $IncludeUnknown = $true
        $IncludePinned = $true
        $ForceWinget = $true
        if (-not $script:RebootPolicyExplicitlySet) {
            $RebootPolicy = 'IfRequired'
        }
    }
    default {
        # Manual: explicit command-line switches control behavior.
    }
}

# AuditOnly is a hard safety override. It may inventory every requested scope,
# but it must never schedule a restart or perform remediation.
if ($AuditOnly) {
    $RebootPolicy = 'Never'
}

$script:OperationMode = if ($InstallScheduledTask) {
    'InstallScheduledTask'
}
elseif ($RemoveScheduledTask) {
    'RemoveScheduledTask'
}
else {
    'Maintenance'
}

$script:IsManagementOperation = ($script:OperationMode -ne 'Maintenance')

$ScriptVersion = '0.6.2'
$SchemaVersion = '1.0'
$BaseDir       = 'C:\ProgramData\Byson Cyber\Maintenance'
$LogDir        = Join-Path $BaseDir 'Logs'
$InstallPath   = Join-Path $BaseDir 'Byson-ClientUpdate.ps1'
$TaskName      = 'Byson Cyber - Endpoint Maintenance'
$LegacyTaskName = 'Byson Cyber - Client Update'
$RebootPromptPath = Join-Path $BaseDir 'Byson-RebootPrompt.ps1'
$PwshLauncherPath = Join-Path $BaseDir 'Byson-PwshLauncher.ps1'
$DeviceIdPath  = Join-Path $BaseDir 'DeviceId.txt'

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

if (-not (Test-Path $DeviceIdPath)) {
    ([guid]::NewGuid().Guid) | Set-Content -Path $DeviceIdPath -Encoding utf8
}

$DeviceId = (Get-Content -Path $DeviceIdPath -Raw).Trim()
$RunId = [guid]::NewGuid().Guid
$RunStartedAt = Get-Date

$RunStamp    = $RunStartedAt.ToString('yyyy-MM-dd_HH-mm-ss')
$LogFile     = Join-Path $LogDir "Byson-Update_$RunStamp.log"
$SummaryFile = Join-Path $LogDir "Byson-Update_$RunStamp.json"

$script:HadErrors = $false
$script:RunLockAcquired = $false
$script:RunMutex = $null
$script:InstallGuardBlocked = $false

$script:Summary = [ordered]@{
    SchemaVersion          = $SchemaVersion
    ScriptVersion          = $ScriptVersion
    RunId                  = $RunId
    DeviceId               = $DeviceId
    Operation              = $script:OperationMode
    Profile                = $Profile
    ScheduledProfileRequested = if ($InstallScheduledTask) { $ScheduledProfile } else { $null }
    ScheduledRebootPolicyRequested = if ($InstallScheduledTask) { $ScheduledRebootPolicy } else { $null }
    Started                = $RunStartedAt.ToString('o')
    Completed              = $null
    DurationSeconds        = $null
    OverallStatus          = 'Unknown'
    WarningCount           = 0
    ErrorCount             = 0
    RunSkippedReason       = $null
    Computer               = $env:COMPUTERNAME
    Manufacturer           = $null
    Model                  = $null
    OSCaption              = $null
    OSVersion              = $null
    OSBuild                = $null
    BIOSVersion            = $null
    SystemDrive            = $env:SystemDrive
    SystemDriveFreeGB      = $null
    MinFreeDiskGB          = $MinFreeDiskGB
    DiskSpaceGuardPassed   = $null
    SecureBootEnabled      = $null
    TPMPresent             = $null
    TPMEnabled             = $null
    TPMActivated           = $null
    TPMSpecVersion         = $null
    PowerShellVersion      = $PSVersionTable.PSVersion.ToString()
    AuditOnly              = [bool]$AuditOnly
    DefenderUpdated        = $false
    DefenderSignatureAge   = $null
    WingetFound            = $false
    WingetExitCode         = $null
    WindowsUpdatesPending  = 0
    WindowsUpdatesInstalled= 0
    WindowsUpdateResult    = $null
    OEMManufacturer        = $null
    OEMAdapter             = $null
    OEMApplicationsRequested = [bool]$IncludeOEMApplications
    DellCommandFound       = $false
    DellExitCode           = $null
    DellDeferred           = $false
    DellDeferredReason     = $null
    DellRetryable          = $false
    DellDurationSeconds    = $null
    DellLastProgress       = $null
    DellScanUpdatesDetected = $false
    FirmwareRequested      = [bool]$IncludeFirmware
    FirmwarePreflightPassed= $null
    FirmwarePreflightNotes = @()
    BitLockerProtection    = $null
    BitLockerRecoveryProtector = $null
    ACLineStatus           = $null
    RebootPendingAtStart   = $false
    RebootPendingReasons   = @()
    RebootAdvisories       = @()
    RebootRequired         = $false
    RebootPolicy           = $RebootPolicy
    ForcedRebootScheduled  = $false
    RebootPromptStarted    = $false
    RebootDelaySeconds     = $null
    LogRetentionDays       = $LogRetentionDays
    LogFile                = $LogFile
    SummaryFile            = $SummaryFile
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OUT')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line

    if ($Level -eq 'WARN') {
        $script:Summary.WarningCount++
    }
    elseif ($Level -eq 'ERROR') {
        $script:Summary.ErrorCount++
        $script:HadErrors = $true
    }

    switch ($Level) {
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
}


function Remove-BysonExpiredLogs {
    if ($LogRetentionDays -le 0 -or -not (Test-Path $LogDir)) {
        return
    }

    $cutoff = (Get-Date).AddDays(-$LogRetentionDays)

    try {
        $expired = @(Get-ChildItem -Path $LogDir -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -lt $cutoff -and
                $_.FullName -ne $LogFile -and
                $_.FullName -ne $SummaryFile
            })

        foreach ($file in $expired) {
            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
        }

        if ($expired.Count -gt 0) {
            Write-Log ("Log retention cleanup removed {0} file(s) older than {1} day(s)." -f $expired.Count, $LogRetentionDays)
        }
    }
    catch {
        Write-Log ("Log retention cleanup failed: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Enter-BysonRunLock {
    try {
        $createdNew = $false
        $script:RunMutex = [System.Threading.Mutex]::new(
            $false,
            'Global\BysonCyberEndpointMaintenance',
            [ref]$createdNew
        )

        try {
            $script:RunLockAcquired = $script:RunMutex.WaitOne(0)
        }
        catch [System.Threading.AbandonedMutexException] {
            $script:RunLockAcquired = $true
        }

        return $script:RunLockAcquired
    }
    catch {
        Write-Log ("Unable to create maintenance run lock: {0}" -f $_.Exception.Message) 'WARN'
        # Fail open if the mutex itself is unavailable; Task Scheduler still uses IgnoreNew.
        return $true
    }
}

function Exit-BysonRunLock {
    if ($script:RunMutex) {
        if ($script:RunLockAcquired) {
            try { $script:RunMutex.ReleaseMutex() } catch { }
        }

        try { $script:RunMutex.Dispose() } catch { }
        $script:RunMutex = $null
        $script:RunLockAcquired = $false
    }
}

function Get-BysonSystemHealth {
    try {
        $computer = Get-CimInstance Win32_ComputerSystem
        $os       = Get-CimInstance Win32_OperatingSystem
        $bios     = Get-CimInstance Win32_BIOS
        $ntVersion = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

        $fullBuild = '{0}.{1}' -f $ntVersion.CurrentBuild, $ntVersion.UBR

        $script:Summary.Manufacturer = [string]$computer.Manufacturer
        $script:Summary.Model = [string]$computer.Model
        $script:Summary.OSCaption = [string]$os.Caption
        $script:Summary.OSVersion = [string]$ntVersion.DisplayVersion
        $script:Summary.OSBuild = $fullBuild
        $script:Summary.BIOSVersion = [string]($bios.SMBIOSBIOSVersion -join ', ')

        Write-Log ("Manufacturer/Model: {0} {1}" -f $script:Summary.Manufacturer, $script:Summary.Model)
        Write-Log ("OS: {0} version {1} build {2}" -f $script:Summary.OSCaption, $script:Summary.OSVersion, $script:Summary.OSBuild)
        Write-Log ("BIOS version: {0}" -f $script:Summary.BIOSVersion)
    }
    catch {
        Write-Log ("System inventory collection failed: {0}" -f $_.Exception.Message) 'WARN'
    }

    try {
        $drive = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $env:SystemDrive)
        if ($drive) {
            $freeGB = [math]::Round(($drive.FreeSpace / 1GB), 2)
            $script:Summary.SystemDriveFreeGB = $freeGB
            Write-Log ("System drive free space: {0} GB." -f $freeGB)
        }
    }
    catch {
        Write-Log ("Unable to determine free disk space: {0}" -f $_.Exception.Message) 'WARN'
    }

    try {
        $script:Summary.SecureBootEnabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
    }
    catch {
        $script:Summary.SecureBootEnabled = $null
    }

    try {
        $tpm = Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($tpm) {
            $script:Summary.TPMPresent = $true
            $script:Summary.TPMEnabled = [bool]$tpm.IsEnabled_InitialValue
            $script:Summary.TPMActivated = [bool]$tpm.IsActivated_InitialValue
            $script:Summary.TPMSpecVersion = [string]$tpm.SpecVersion
        }
    }
    catch {
        $script:Summary.TPMPresent = $false
    }

    try {
        $bl = Get-BitLockerPreflightStatus
        if ($bl.Available) {
            $script:Summary.BitLockerProtection = $bl.ProtectionStatus
            $script:Summary.BitLockerRecoveryProtector = $bl.RecoveryPasswordExists
        }
    }
    catch { }

    $secureBootText = if ($null -eq $script:Summary.SecureBootEnabled) { 'Unknown/unsupported' } elseif ($script:Summary.SecureBootEnabled) { 'Enabled' } else { 'Disabled' }
    $tpmText = if ($script:Summary.TPMPresent) { "Present (Enabled=$($script:Summary.TPMEnabled), Activated=$($script:Summary.TPMActivated))" } else { 'Not detected/unknown' }
    Write-Log ("Secure Boot: {0}; TPM: {1}." -f $secureBootText, $tpmText)
}

function Test-BysonInstallationGuardrails {
    if ($script:IsManagementOperation -or $AuditOnly) {
        $script:Summary.DiskSpaceGuardPassed = $true
        return $true
    }

    if ($IgnoreDiskSpaceGuard) {
        $script:Summary.DiskSpaceGuardPassed = $true
        Write-Log 'Disk-space installation guard explicitly overridden by technician.' 'WARN'
        return $true
    }

    if ($null -eq $script:Summary.SystemDriveFreeGB) {
        $script:Summary.DiskSpaceGuardPassed = $false
        Write-Log 'Free disk space could not be verified. Install actions are deferred; scans will continue. Use -IgnoreDiskSpaceGuard only after manual verification.' 'WARN'
        return $false
    }

    if ([double]$script:Summary.SystemDriveFreeGB -lt $MinFreeDiskGB) {
        $script:Summary.DiskSpaceGuardPassed = $false
        Write-Log ("Only {0} GB free on {1}; minimum is {2} GB. Install actions are deferred, but audits/scans will continue." -f $script:Summary.SystemDriveFreeGB, $env:SystemDrive, $MinFreeDiskGB) 'WARN'
        return $false
    }

    $script:Summary.DiskSpaceGuardPassed = $true
    return $true
}

function Write-BysonRunSummary {
    Write-Log '--- Run Summary ---'
    Write-Log ("Overall status: {0}" -f $script:Summary.OverallStatus)
    Write-Log ("Device ID: {0}; Run ID: {1}" -f $script:Summary.DeviceId, $script:Summary.RunId)

    if (-not $script:IsManagementOperation) {
        Write-Log ("Windows updates pending/installed: {0}/{1}" -f $script:Summary.WindowsUpdatesPending, $script:Summary.WindowsUpdatesInstalled)

        if ($null -ne $script:Summary.DefenderSignatureAge) {
            Write-Log ("Defender signature age: {0} day(s)." -f $script:Summary.DefenderSignatureAge)
        }

        Write-Log ("OEM adapter: {0}; reboot required: {1}; restart scheduled: {2}" -f $script:Summary.OEMAdapter, $script:Summary.RebootRequired, $script:Summary.ForcedRebootScheduled)
    }

    Write-Log ("Warnings: {0}; Errors: {1}; Duration: {2} second(s)." -f $script:Summary.WarningCount, $script:Summary.ErrorCount, $script:Summary.DurationSeconds)
}

function Invoke-LoggedExternal {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$false)][string[]]$ArgumentList = @()
    )

    Write-Log ("Executing: {0} {1}" -f $FilePath, ($ArgumentList -join ' '))

    try {
        & $FilePath @ArgumentList 2>&1 | ForEach-Object {
            $outputLine = [string]$_

            if ([string]::IsNullOrWhiteSpace($outputLine)) {
                # Some vendor CLIs emit blank lines. Preserve readability without
                # passing an empty mandatory argument into Write-Log.
                Add-Content -Path $LogFile -Value ''
            }
            else {
                Write-Log $outputLine 'OUT'
            }
        }
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Log ("Failed to launch external command: {0}" -f $_.Exception.Message) 'ERROR'
        return 99999
    }

    Write-Log ("Exit code: {0}" -f $exitCode)
    return $exitCode
}

function Test-BysonStablePwshCandidate {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $versionText = (& $Path -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>$null | Select-Object -First 1)

        if ([string]::IsNullOrWhiteSpace($versionText)) {
            return $false
        }

        # Preview/RC builds contain a prerelease suffix such as 7.7.0-rc.1.
        if ($versionText -match '-') {
            return $false
        }

        $baseVersionText = ($versionText -split '-')[0]
        $baseVersion = [version]$baseVersionText
        return ($baseVersion -ge [version]'7.6.0')
    }
    catch {
        return $false
    }
}

function Get-BysonStableAppxPwshPath {
    # Query the non-preview MSIX package by its package name. Use Windows
    # PowerShell because Get-AppxPackage is most consistently available there.
    try {
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

        if (Test-Path $windowsPowerShell) {
            $candidate = & $windowsPowerShell -NoProfile -NonInteractive -Command @'
$p = Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($p) {
    Join-Path $p.InstallLocation 'pwsh.exe'
}
'@ 2>$null | Select-Object -First 1

            if ($candidate) {
                return [string]$candidate
            }
        }
    }
    catch { }

    return $null
}

function Get-BysonPwshPath {
    $candidates = New-Object System.Collections.Generic.List[string]

    # Prefer the traditional stable MSI location when present.
    [void]$candidates.Add((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'))

    # Prefer the stable Microsoft.PowerShell MSIX package over Preview.
    $stableAppx = Get-BysonStableAppxPwshPath
    if ($stableAppx) {
        [void]$candidates.Add($stableAppx)
    }

    # If the current host itself is a supported non-preview release, it is safe.
    $currentPwsh = Join-Path $PSHOME 'pwsh.exe'
    if ($currentPwsh) {
        [void]$candidates.Add($currentPwsh)
    }

    # Finally consider any PATH-resolved pwsh executables, but validate every
    # candidate so Microsoft.PowerShell.Preview cannot silently win.
    try {
        Get-Command 'pwsh.exe' -All -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Source) {
                [void]$candidates.Add($_.Source)
            }
        }
    }
    catch { }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-BysonStablePwshCandidate -Path $candidate) {
            return $candidate
        }
    }

    throw 'A supported non-preview PowerShell 7.6+ runtime was not found. Install the stable Microsoft.PowerShell package; Preview/RC builds are intentionally not used for scheduled maintenance.'
}

function Get-BysonRebootStatus {
    $blockingReasons = New-Object System.Collections.Generic.List[string]
    $advisoryReasons = New-Object System.Collections.Generic.List[string]

    # Windows Update Agent's own system-level reboot state. This is the most
    # directly relevant signal for deciding whether another Windows Update
    # installation should be attempted.
    try {
        $wuSystemInfo = New-Object -ComObject 'Microsoft.Update.SystemInfo'
        if ($wuSystemInfo.RebootRequired) {
            [void]$blockingReasons.Add('Windows Update Agent reports reboot required')
        }
    }
    catch {
        [void]$advisoryReasons.Add("Unable to query Microsoft.Update.SystemInfo: $($_.Exception.Message)")
    }

    # Component Based Servicing reboot state.
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        [void]$blockingReasons.Add('Component Based Servicing RebootPending')
    }

    # Windows Update's explicit reboot-required state.
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        [void]$blockingReasons.Add('Windows Update RebootRequired registry state')
    }

    # Pending file rename operations are intentionally advisory-only.
    # Applications such as browsers/updaters can leave these populated without
    # requiring an immediate servicing reboot, which otherwise creates false
    # positives for patch automation.
    try {
        $sessionManager = Get-ItemProperty `
            -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name 'PendingFileRenameOperations' `
            -ErrorAction SilentlyContinue

        $pfro = $sessionManager.PendingFileRenameOperations

        if ($null -ne $pfro -and @($pfro).Count -gt 0) {
            [void]$advisoryReasons.Add(
                ('PendingFileRenameOperations contains {0} value(s); advisory only' -f @($pfro).Count)
            )
        }
    }
    catch { }

    return [PSCustomObject]@{
        Blocking          = ($blockingReasons.Count -gt 0)
        BlockingReasons   = @($blockingReasons)
        AdvisoryReasons   = @($advisoryReasons)
    }
}

function Test-PendingReboot {
    return (Get-BysonRebootStatus).Blocking
}

# Capture reboot state once at startup. Only authoritative servicing/update
# signals block Windows Update installation; advisory signals are retained
# for visibility but do not stop patching.
$script:RebootStatusAtStart = Get-BysonRebootStatus
$script:RebootPendingAtStart = [bool]$script:RebootStatusAtStart.Blocking
$script:Summary.RebootPendingAtStart = $script:RebootPendingAtStart
$script:Summary.RebootPendingReasons = @($script:RebootStatusAtStart.BlockingReasons)
$script:Summary.RebootAdvisories = @($script:RebootStatusAtStart.AdvisoryReasons)

function Get-WingetPath {
    $cmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $userCandidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $userCandidate) {
        return $userCandidate
    }

    return $null
}

function Invoke-DefenderMaintenance {
    Write-Log '--- Microsoft Defender ---'

    $updateCmd = Get-Command 'Update-MpSignature' -ErrorAction SilentlyContinue
    $statusCmd = Get-Command 'Get-MpComputerStatus' -ErrorAction SilentlyContinue

    if (-not $updateCmd -or -not $statusCmd) {
        Write-Log 'Microsoft Defender PowerShell cmdlets are not available; skipping.' 'WARN'
        return
    }

    try {
        if (-not $AuditOnly) {
            Write-Log 'Updating Microsoft Defender security intelligence.'
            Update-MpSignature | Out-Null
            $script:Summary.DefenderUpdated = $true
        }
        else {
            Write-Log 'Audit-only mode: Defender signature update skipped.'
        }

        $status = Get-MpComputerStatus
        $script:Summary.DefenderSignatureAge = $status.AntivirusSignatureAge
        Write-Log ("Defender signature age: {0} day(s)." -f $status.AntivirusSignatureAge)

        if ($null -ne $status.AntivirusSignatureAge -and $status.AntivirusSignatureAge -gt 2) {
            Write-Log ("Defender security intelligence is {0} days old; review Defender/update health." -f $status.AntivirusSignatureAge) 'WARN'
        }
    }
    catch {
        Write-Log ("Defender maintenance failed or Defender is not active: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Invoke-WingetMaintenance {
    Write-Log '--- WinGet Applications ---'

    $winget = Get-WingetPath
    if (-not $winget) {
        Write-Log 'WinGet was not found for the current user; skipping application updates.' 'WARN'
        return
    }

    $script:Summary.WingetFound = $true
    Write-Log ("WinGet path: {0}" -f $winget)

    $commonArgs = @(
        '--accept-source-agreements',
        '--disable-interactivity'
    )

    if ($AuditOnly -or $script:InstallGuardBlocked) {
        if ($script:InstallGuardBlocked -and -not $AuditOnly) {
            Write-Log 'WinGet installation deferred by endpoint installation guard; audit will continue.' 'WARN'
        }

        $auditArgs = @('upgrade') + $commonArgs
        $script:Summary.WingetExitCode = Invoke-LoggedExternal -FilePath $winget -ArgumentList $auditArgs
        return
    }

    [void](Invoke-LoggedExternal -FilePath $winget -ArgumentList @(
        'source', 'update', '--disable-interactivity'
    ))

    $upgradeArgs = @(
        'upgrade',
        '--all',
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )

    if ($IncludeUnknown) {
        $upgradeArgs += '--include-unknown'
    }

    if ($IncludePinned) {
        $upgradeArgs += '--include-pinned'
    }

    if ($ForceWinget) {
        $upgradeArgs += '--force'
    }

    $script:Summary.WingetExitCode = Invoke-LoggedExternal -FilePath $winget -ArgumentList $upgradeArgs
}

function Get-WindowsUpdateCollection {
    Write-Log 'Scanning Windows Update for applicable, non-browse-only software updates.'

    $session = New-Object -ComObject 'Microsoft.Update.Session'
    $session.ClientApplicationID = 'Byson Cyber Endpoint Maintenance'

    $searcher = $session.CreateUpdateSearcher()

    # BrowseOnly=0 avoids updates that are not recommended for automatic processing,
    # such as many optional/preview updates.
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0")

    $collection = New-Object -ComObject 'Microsoft.Update.UpdateColl'

    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)

        if ($update.InstallationBehavior.CanRequestUserInput) {
            Write-Log ("Skipping update requiring user input: {0}" -f $update.Title) 'WARN'
            continue
        }

        [void]$collection.Add($update)
        Write-Log ("Pending Windows update: {0}" -f $update.Title)
    }

    return @{
        Session    = $session
        Collection = $collection
    }
}

function Get-WuaOperationResultName {
    param(
        [Parameter(Mandatory=$true)][int]$ResultCode
    )

    switch ($ResultCode) {
        0 { return 'NotStarted' }
        1 { return 'InProgress' }
        2 { return 'Succeeded' }
        3 { return 'SucceededWithErrors' }
        4 { return 'Failed' }
        5 { return 'Aborted' }
        default { return 'Unknown' }
    }
}

function Invoke-WindowsUpdateMaintenance {
    Write-Log '--- Windows Update ---'

    try {
        $wu = Get-WindowsUpdateCollection
        $updates = $wu.Collection
        $script:Summary.WindowsUpdatesPending = $updates.Count

        Write-Log ("Applicable Windows updates found: {0}" -f $updates.Count)

        if ($updates.Count -eq 0) {
            return
        }

        if ($AuditOnly -or -not $InstallWindowsUpdates -or $script:InstallGuardBlocked) {
            if ($AuditOnly) {
                Write-Log ("Audit-only mode: {0} Windows update(s) remain pending." -f $updates.Count) 'WARN'
            }
            elseif ($script:InstallGuardBlocked) {
                Write-Log 'Windows Update installation deferred by endpoint installation guard; scan results are retained.' 'WARN'
            }
            else {
                Write-Log ("Windows Update install not enabled; {0} update(s) remain pending." -f $updates.Count) 'WARN'
            }
            return
        }

        if ($script:RebootPendingAtStart) {
            Write-Log ('A blocking servicing/update reboot was already pending when this run started ({0}). Windows Update installation is deferred until that state clears.' -f ($script:RebootStatusAtStart.BlockingReasons -join '; ')) 'WARN'
            $script:Summary.RebootRequired = $true
            return
        }

        for ($i = 0; $i -lt $updates.Count; $i++) {
            $update = $updates.Item($i)
            if (-not $update.EulaAccepted) {
                $update.AcceptEula()
            }
        }

        Write-Log 'Downloading Windows updates.'
        $downloader = $wu.Session.CreateUpdateDownloader()
        $downloader.Updates = $updates
        $downloadResult = $downloader.Download()
        $downloadResultName = Get-WuaOperationResultName -ResultCode $downloadResult.ResultCode
        Write-Log ("Windows Update download result: {0} ({1})" -f $downloadResult.ResultCode, $downloadResultName)

        $installable = New-Object -ComObject 'Microsoft.Update.UpdateColl'
        for ($i = 0; $i -lt $updates.Count; $i++) {
            $update = $updates.Item($i)
            if ($update.IsDownloaded) {
                [void]$installable.Add($update)
            }
            else {
                Write-Log ("Update was not downloaded and will not be installed: {0}" -f $update.Title) 'WARN'
            }
        }

        if ($installable.Count -eq 0) {
            Write-Log 'No Windows updates were successfully downloaded.' 'WARN'
            return
        }

        Write-Log ("Installing {0} Windows update(s)." -f $installable.Count)
        $installer = $wu.Session.CreateUpdateInstaller()
        $installer.Updates = $installable
        $installer.ForceQuiet = $true

        $installResult = $installer.Install()
        $script:Summary.WindowsUpdateResult = $installResult.ResultCode
        $script:Summary.WindowsUpdatesInstalled = $installable.Count

        $installResultName = Get-WuaOperationResultName -ResultCode $installResult.ResultCode
        Write-Log ("Windows Update install result: {0} ({1})" -f $installResult.ResultCode, $installResultName)

        for ($i = 0; $i -lt $installable.Count; $i++) {
            $updateResult = $installResult.GetUpdateResult($i)
            $updateResultName = Get-WuaOperationResultName -ResultCode $updateResult.ResultCode
            $updateTitle = $installable.Item($i).Title

            if ($updateResult.ResultCode -eq 2) {
                Write-Log ("Windows update result: {0} -- {1} ({2})" -f $updateTitle, $updateResult.ResultCode, $updateResultName)
            }
            else {
                $hresultHex = ('0x{0:X8}' -f ([uint32]$updateResult.HResult))
                Write-Log ("Windows update result: {0} -- {1} ({2}), HRESULT {3}" -f $updateTitle, $updateResult.ResultCode, $updateResultName, $hresultHex) 'WARN'
            }
        }

        if ($installResult.RebootRequired) {
            Write-Log 'Windows Update reports that a reboot is required.' 'WARN'
            $script:Summary.RebootRequired = $true
        }
    }
    catch {
        Write-Log ("Windows Update scan/install failed: {0}" -f $_.Exception.Message) 'ERROR'
    }
}


function Get-PowerPreflightStatus {
    $result = [ordered]@{
        HasBattery      = $false
        ACLineStatus    = 'Unknown'
        BatteryPercent  = $null
        OnACPower       = $false
    }

    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        $result.HasBattery = ($null -ne $battery)

        # Desktop/workstation with no battery: AC is implicit.
        if (-not $result.HasBattery) {
            $result.ACLineStatus = 'NoBatteryDetected'
            $result.OnACPower = $true
            return [pscustomobject]$result
        }

        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $power = [System.Windows.Forms.SystemInformation]::PowerStatus
        $result.ACLineStatus = [string]$power.PowerLineStatus
        if ($power.BatteryLifePercent -ge 0) {
            $result.BatteryPercent = [math]::Round(($power.BatteryLifePercent * 100), 0)
        }
        $result.OnACPower = ($power.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)
    }
    catch {
        $result.ACLineStatus = 'Unknown'
        $result.OnACPower = $false
    }

    return [pscustomobject]$result
}

function Get-BitLockerPreflightStatus {
    $result = [ordered]@{
        Available              = $false
        Encrypted              = $false
        ProtectionStatus       = 'Unknown'
        VolumeStatus           = 'Unknown'
        RecoveryPasswordExists = $false
        MountPoint             = $env:SystemDrive
    }

    $cmd = Get-Command 'Get-BitLockerVolume' -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [pscustomobject]$result
    }

    try {
        $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        $result.Available = $true
        $result.ProtectionStatus = [string]$volume.ProtectionStatus
        $result.VolumeStatus = [string]$volume.VolumeStatus

        # Treat anything other than a fully decrypted OS volume as BitLocker-encrypted.
        $result.Encrypted = ($volume.VolumeStatus -ne 'FullyDecrypted')

        if ($volume.KeyProtector) {
            $recovery = @($volume.KeyProtector | Where-Object {
                ([string]$_.KeyProtectorType) -eq 'RecoveryPassword'
            })
            $result.RecoveryPasswordExists = ($recovery.Count -gt 0)
        }
    }
    catch {
        # Leave Available=False/Unknown so firmware mode fails closed.
    }

    return [pscustomobject]$result
}

function Test-FirmwarePreflight {
    Write-Log '--- Firmware Safety Preflight ---'

    $notes = New-Object System.Collections.Generic.List[string]
    $passed = $true

    if (-not $InstallOEMUpdates) {
        $notes.Add('Firmware mode requires -InstallOEMUpdates.')
        $passed = $false
    }

    if (-not $AcknowledgeFirmwareRisk) {
        $notes.Add('Firmware mode requires explicit -AcknowledgeFirmwareRisk.')
        $passed = $false
    }

    if (Test-PendingReboot) {
        $notes.Add('A reboot is already pending. Reboot before attempting firmware maintenance.')
        $passed = $false
    }

    $power = Get-PowerPreflightStatus
    $script:Summary.ACLineStatus = $power.ACLineStatus

    if (-not $power.OnACPower) {
        $batteryNote = if ($null -ne $power.BatteryPercent) {
            " (battery: $($power.BatteryPercent)%)"
        } else { '' }
        $notes.Add("AC power could not be confirmed$($batteryNote).")
        $passed = $false
    }
    else {
        $notes.Add("AC power check passed: $($power.ACLineStatus).")
    }

    $bl = Get-BitLockerPreflightStatus
    $script:Summary.BitLockerProtection = $bl.ProtectionStatus
    $script:Summary.BitLockerRecoveryProtector = $bl.RecoveryPasswordExists

    if (-not $bl.Available) {
        $notes.Add('BitLocker state could not be verified. Firmware update blocked (fail closed).')
        $passed = $false
    }
    elseif ($bl.Encrypted) {
        if (-not $bl.RecoveryPasswordExists) {
            $notes.Add('BitLocker is active/encrypted but no RecoveryPassword protector was detected.')
            $passed = $false
        }
        else {
            $notes.Add('BitLocker recovery-password protector detected.')
        }

        if (-not $RecoveryKeyEscrowConfirmed) {
            $notes.Add('BitLocker is active. Technician must confirm external recovery-key availability with -RecoveryKeyEscrowConfirmed.')
            $passed = $false
        }
        else {
            $notes.Add('Technician attested that the recovery key is escrowed/available outside this endpoint.')
        }
    }
    else {
        $notes.Add('OS volume is fully decrypted; BitLocker recovery-key acknowledgement is not required.')
    }

    $script:Summary.FirmwarePreflightPassed = $passed
    $script:Summary.FirmwarePreflightNotes = @($notes)

    foreach ($note in $notes) {
        if ($passed) {
            Write-Log $note
        }
        else {
            Write-Log $note 'WARN'
        }
    }

    if ($passed) {
        Write-Log 'Firmware safety preflight PASSED.'
    }
    else {
        Write-Log 'Firmware safety preflight BLOCKED. BIOS/firmware updates will not be applied.' 'WARN'
    }

    return $passed
}

function Get-DellCommandPath {
    $candidates = @(
        'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe',
        'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Invoke-DellCommandWithProgress {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$false)][string[]]$ArgumentList = @(),
        [Parameter(Mandatory=$true)][string]$DellLogPath,
        [ValidateRange(5,300)][int]$ProgressIntervalSeconds = 15,
        [ValidateRange(1,60)][int]$HeartbeatMinutes = 5
    )

    Write-Log ("Executing: {0} {1}" -f $FilePath, ($ArgumentList -join ' '))

    $isScanOperation = ($ArgumentList -contains '/scan')

    $stdoutPath = Join-Path $env:TEMP ("Byson-DCU-stdout-{0}.log" -f ([guid]::NewGuid().ToString('N')))
    $stderrPath = Join-Path $env:TEMP ("Byson-DCU-stderr-{0}.log" -f ([guid]::NewGuid().ToString('N')))

    $started = Get-Date
    $lastHeartbeat = $started
    $lastProgressEmit = $started.AddSeconds(-$ProgressIntervalSeconds)
    $lastObservedDellLine = $null
    $lastEmittedDellLine = $null
    $capturedDellOutput = New-Object System.Collections.Generic.List[string]

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        while (-not $process.HasExited) {
            Start-Sleep -Seconds 2
            $process.Refresh()

            $now = Get-Date

            if (Test-Path $DellLogPath) {
                try {
                    $latestLine = Get-Content -Path $DellLogPath -Tail 1 -ErrorAction Stop

                    if (-not [string]::IsNullOrWhiteSpace($latestLine)) {
                        $lastObservedDellLine = [string]$latestLine
                        $script:Summary.DellLastProgress = $lastObservedDellLine
                    }
                }
                catch { }
            }

            # Surface Dell's latest native status periodically without mirroring
            # every high-frequency percentage update into the Byson log.
            if (
                $lastObservedDellLine -and
                $lastObservedDellLine -ne $lastEmittedDellLine -and
                (($now - $lastProgressEmit).TotalSeconds -ge $ProgressIntervalSeconds)
            ) {
                Write-Log ("Dell progress: {0}" -f $lastObservedDellLine) 'OUT'
                $lastEmittedDellLine = $lastObservedDellLine
                $lastProgressEmit = $now
            }

            # Stronger heartbeat every N minutes so a long silent vendor process
            # is visibly alive in both the console and Byson log.
            if (($now - $lastHeartbeat).TotalMinutes -ge $HeartbeatMinutes) {
                $elapsedMinutes = [math]::Round(($now - $started).TotalMinutes, 1)

                if ($lastObservedDellLine) {
                    Write-Log ("Dell updates still running -- {0} minute(s) elapsed. Latest: {1}" -f $elapsedMinutes, $lastObservedDellLine)
                }
                else {
                    Write-Log ("Dell updates still running -- {0} minute(s) elapsed. Waiting for Dell progress output..." -f $elapsedMinutes)
                }

                $lastHeartbeat = $now
            }
        }

        # Ensures redirected stdout/stderr streams are fully flushed before readback.
        $process.WaitForExit()
        $process.Refresh()

        try {
            $exitCode = $process.ExitCode
        }
        catch {
            $exitCode = $null
        }
    }
    catch {
        Write-Log ("Failed to launch/monitor Dell Command | Update: {0}" -f $_.Exception.Message) 'ERROR'
        $exitCode = 99999
    }

    $durationSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds)
    $script:Summary.DellDurationSeconds = $durationSeconds

    # DCU is usually quiet when -silent is used, but retain any CLI output/errors.
    foreach ($capturePath in @($stdoutPath, $stderrPath)) {
        if (Test-Path $capturePath) {
            Get-Content -Path $capturePath -ErrorAction SilentlyContinue | ForEach-Object {
                $line = [string]$_
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    [void]$capturedDellOutput.Add($line)
                    Write-Log $line 'OUT'
                }
            }

            Remove-Item -Path $capturePath -Force -ErrorAction SilentlyContinue
        }
    }

    # Dell self-update/service-busy conditions sometimes return before a useful
    # numeric ExitCode is exposed by the launched CLI process. Normalize those
    # well-known states from Dell's own console output so they remain actionable.
    if ($null -eq $exitCode -or [string]::IsNullOrWhiteSpace([string]$exitCode)) {
        $nativeDellTail = @()
        if (Test-Path $DellLogPath) {
            try {
                $nativeDellTail = @(Get-Content -Path $DellLogPath -Tail 250 -ErrorAction SilentlyContinue)
            }
            catch { }
        }

        $joinedDellOutput = (@($capturedDellOutput) + @($nativeDellTail)) -join "`n"

        if (
            $isScanOperation -and
            $joinedDellOutput -match '(?im)^.+:\s+.+\s+-\s+(Application|Driver|BIOS|Firmware)\s+--\s+.+'
        ) {
            $exitCode = 0
            $script:Summary.DellScanUpdatesDetected = $true
            Write-Log 'Dell CLI did not expose a numeric exit code; scan output contains applicable update inventory. Normalizing scan result to success (0).'
        }
        elseif ($joinedDellOutput -match '(?i)NO_INVENTORIED_UPDATES_FOUND|no update information found|no updates? (were )?found|system is up[- ]to[- ]date') {
            $exitCode = 500
            Write-Log 'Dell CLI did not expose a numeric exit code; output indicates no applicable updates were found for the selected filters. Normalizing to return code 500.'
        }
        elseif ($joinedDellOutput -match '(?i)self update|self-update') {
            $exitCode = 3004
            Write-Log 'Dell CLI did not expose a numeric exit code; output indicates a Dell Client Management Service self-update. Normalizing to return code 3004.' 'WARN'
        }
        elseif ($joinedDellOutput -match '(?i)installing pending updates') {
            $exitCode = 3005
            Write-Log 'Dell CLI did not expose a numeric exit code; output indicates Dell Client Management Service is installing pending updates. Normalizing to return code 3005.' 'WARN'
        }
        elseif ($joinedDellOutput -match '(?i)operation is in progress|service is busy|currently busy') {
            $exitCode = 3003
            Write-Log 'Dell CLI did not expose a numeric exit code; output indicates Dell Client Management Service is busy. Normalizing to return code 3003.' 'WARN'
        }
        else {
            $exitCode = 99998
            Write-Log 'Dell CLI process ended without an accessible numeric exit code and no known state was detected.' 'WARN'
        }
    }

    # Capture the final native Dell status even if it occurred inside the
    # progress throttle interval.
    if (Test-Path $DellLogPath) {
        try {
            $finalDellLine = Get-Content -Path $DellLogPath -Tail 1 -ErrorAction Stop

            if (
                -not [string]::IsNullOrWhiteSpace($finalDellLine) -and
                $finalDellLine -ne $lastEmittedDellLine
            ) {
                $script:Summary.DellLastProgress = [string]$finalDellLine
                Write-Log ("Dell final status: {0}" -f $finalDellLine) 'OUT'
            }
        }
        catch { }
    }

    Write-Log ("Dell Command | Update completed after {0} second(s). Exit code: {1}" -f $durationSeconds, $exitCode)
    return $exitCode
}

function Invoke-OEMMaintenance {
    Write-Log '--- OEM Update Provider ---'

    try {
        $manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    }
    catch {
        Write-Log ("Unable to determine system manufacturer: {0}" -f $_.Exception.Message) 'WARN'
        return
    }

    $script:Summary.OEMManufacturer = $manufacturer

    switch -Regex ($manufacturer) {
        'Dell' {
            $script:Summary.OEMAdapter = 'Dell Command Update'
            Write-Log ("OEM detected: {0}. Using Dell Command | Update adapter." -f $manufacturer)
            Invoke-DellMaintenance
            return
        }

        'HP|Hewlett-Packard' {
            $script:Summary.OEMAdapter = 'NotImplemented-HP'
            Write-Log ("OEM detected: {0}. HP update adapter is not implemented yet; no HP OEM updates will be installed." -f $manufacturer)
            return
        }

        'Lenovo' {
            $script:Summary.OEMAdapter = 'NotImplemented-Lenovo'
            Write-Log ("OEM detected: {0}. Lenovo update adapter is not implemented yet; no Lenovo OEM updates will be installed." -f $manufacturer)
            return
        }

        default {
            $script:Summary.OEMAdapter = 'Unsupported'
            Write-Log ("OEM detected: {0}. No supported OEM update adapter is configured." -f $manufacturer)
            return
        }
    }
}

function Invoke-DellMaintenance {
    Write-Log '--- Dell Command | Update ---'

    try {
        $manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    }
    catch {
        Write-Log ("Unable to determine system manufacturer: {0}" -f $_.Exception.Message) 'WARN'
        return
    }

    if ($manufacturer -notmatch 'Dell') {
        Write-Log ("Manufacturer is '{0}'; Dell maintenance not applicable." -f $manufacturer)
        return
    }

    $dcu = Get-DellCommandPath
    if (-not $dcu) {
        Write-Log 'Dell system detected, but Dell Command | Update CLI was not found.' 'WARN'
        return
    }

    $script:Summary.DellCommandFound = $true
    Write-Log ("Dell Command | Update path: {0}" -f $dcu)

    # Do not layer OEM driver/application servicing on top of a Windows
    # servicing reboot. This is especially important after a cumulative update:
    # complete the Windows reboot first, then let the next maintenance run
    # evaluate OEM updates against the settled OS state.
    $currentRebootStatus = Get-BysonRebootStatus
    if ($script:Summary.RebootRequired -or $currentRebootStatus.Blocking) {
        $reasonParts = New-Object System.Collections.Generic.List[string]

        if ($script:Summary.RebootRequired) {
            [void]$reasonParts.Add('this maintenance run already requires a reboot')
        }

        foreach ($reason in $currentRebootStatus.BlockingReasons) {
            if (-not $reasonParts.Contains($reason)) {
                [void]$reasonParts.Add($reason)
            }
        }

        $reasonText = ($reasonParts -join '; ')
        $script:Summary.DellDeferred = $true
        $script:Summary.DellDeferredReason = $reasonText

        Write-Log ("Dell/OEM updates deferred until after a full Windows restart: {0}" -f $reasonText) 'WARN'
        return
    }

    $effectiveAuditOnly = ($AuditOnly -or $script:InstallGuardBlocked)

    if ($script:InstallGuardBlocked -and -not $AuditOnly) {
        Write-Log 'OEM installation deferred by endpoint installation guard; Dell scan will continue.' 'WARN'
    }

    $typeList = New-Object System.Collections.Generic.List[string]
    [void]$typeList.Add('driver')

    if ($IncludeOEMApplications) {
        [void]$typeList.Add('application')
        Write-Log 'OEM application updates explicitly enabled.'
    }
    else {
        Write-Log 'OEM application updates are excluded by default.'
    }

    $firmwareAllowed = $false

    if ($IncludeFirmware) {
        Write-Log 'Firmware mode requested. Running safety preflight before BIOS/firmware installation can be allowed.'
        $firmwareAllowed = Test-FirmwarePreflight

        if ($firmwareAllowed) {
            [void]$typeList.Add('bios')
            [void]$typeList.Add('firmware')
            Write-Log 'Firmware preflight passed: BIOS and firmware are included for this run.'
        }
        elseif ($effectiveAuditOnly) {
            # Scanning firmware is non-destructive. Preserve the failed preflight
            # as the installation decision, but still inventory available BIOS/
            # firmware updates so audit reports are complete.
            [void]$typeList.Add('bios')
            [void]$typeList.Add('firmware')
            Write-Log 'Firmware installation preflight failed, but AuditOnly mode will still scan/report BIOS and firmware availability. Installation remains blocked.' 'WARN'
        }
        else {
            Write-Log 'Firmware request denied by preflight. Continuing without BIOS/firmware.' 'WARN'
        }
    }

    $types = ($typeList | Select-Object -Unique) -join ','
    Write-Log ("Dell update categories selected: {0}" -f $types)

    $dellNativeLogDir = 'C:\ProgramData\Dell'
    New-Item -ItemType Directory -Path $dellNativeLogDir -Force | Out-Null

    # Dell Command | Update 5.x restricts -outputLog paths. C:\ProgramData\Dell
    # is explicitly supported by Dell, so write there first and copy the finished
    # log into the Byson log directory afterward.
    $dellLog = Join-Path $dellNativeLogDir "BysonCyber-Dell-Command-Update_$RunStamp.log"
    $dellArchivedLog = Join-Path $LogDir "Dell-Command-Update_$RunStamp.log"

    if ($effectiveAuditOnly -or -not $InstallOEMUpdates) {
        $scanArgs = @(
            '/scan',
            '-silent',
            '-updateSeverity=critical,recommended',
            "-updateType=$types",
            "-outputLog=$dellLog"
        )

        $script:Summary.DellExitCode = Invoke-DellCommandWithProgress `
            -FilePath $dcu `
            -ArgumentList $scanArgs `
            -DellLogPath $dellLog

        if ($script:Summary.DellScanUpdatesDetected) {
            Write-Log 'Applicable Dell updates were detected during audit/scan.' 'WARN'
        }

        if (Test-Path $dellLog) {
            Copy-Item -Path $dellLog -Destination $dellArchivedLog -Force
            Write-Log ("Archived Dell log: {0}" -f $dellArchivedLog)
            Remove-Item -Path $dellLog -Force -ErrorAction SilentlyContinue
        }

        if (-not $AuditOnly) {
            if ($script:InstallGuardBlocked) {
                Write-Log 'Dell updates were scanned only because endpoint installation guardrails blocked changes.'
            }
            else {
                Write-Log 'Dell updates were scanned only. Use -InstallOEMUpdates to apply the selected OEM categories.'
            }
        }
        return
    }

    $applyArgs = @(
        '/applyUpdates',
        '-silent',
        '-updateSeverity=critical,recommended',
        "-updateType=$types",
        '-reboot=disable',
        "-outputLog=$dellLog"
    )

    if ($firmwareAllowed) {
        $applyArgs += '-autoSuspendBitLocker=enable'
    }

    $code = Invoke-DellCommandWithProgress `
        -FilePath $dcu `
        -ArgumentList $applyArgs `
        -DellLogPath $dellLog

    $script:Summary.DellExitCode = $code

    if (Test-Path $dellLog) {
        Copy-Item -Path $dellLog -Destination $dellArchivedLog -Force
        Write-Log ("Archived Dell log: {0}" -f $dellArchivedLog)
        Remove-Item -Path $dellLog -Force -ErrorAction SilentlyContinue
    }

    switch ($code) {
        0 { Write-Log 'Dell Command | Update completed successfully.' }
        1 {
            Write-Log 'Dell Command | Update reports a reboot is required.' 'WARN'
            $script:Summary.RebootRequired = $true
        }
        5 {
            Write-Log 'Dell Command | Update reports a reboot was already pending.' 'WARN'
            $script:Summary.RebootRequired = $true
        }
        107 {
            Write-Log 'Dell Command | Update rejected one or more option values (return code 107). Review the generated command and Dell CLI version.' 'WARN'
        }
        500 {
            Write-Log 'No applicable Dell updates were found for the selected OEM filters. System is up to date for this Dell update scope.'
        }
        3003 {
            $script:Summary.DellDeferred = $true
            $script:Summary.DellRetryable = $true
            $script:Summary.DellDeferredReason = 'Dell Client Management Service is busy.'
            Write-Log 'Dell Client Management Service is busy (3003). OEM updates deferred; retry on the next maintenance run.' 'WARN'
        }
        3004 {
            $script:Summary.DellDeferred = $true
            $script:Summary.DellRetryable = $true
            $script:Summary.DellDeferredReason = 'Dell Client Management Service initiated a self-update.'
            Write-Log 'Dell Command | Update is self-updating (3004). OEM updates deferred; retry after the Dell self-update completes.' 'WARN'
        }
        3005 {
            $script:Summary.DellDeferred = $true
            $script:Summary.DellRetryable = $true
            $script:Summary.DellDeferredReason = 'Dell Client Management Service is installing pending updates.'
            Write-Log 'Dell Client Management Service is installing pending updates (3005). OEM updates deferred; retry on the next maintenance run.' 'WARN'
        }
        default {
            Write-Log ("Dell Command | Update returned code {0}; review the Dell log." -f $code) 'WARN'
        }
    }
}

function Get-BysonScriptVersionFromFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        $match = Select-String `
            -Path $Path `
            -Pattern '^\s*\$ScriptVersion\s*=\s*[''"]([^''"]+)[''"]' `
            -ErrorAction Stop |
            Select-Object -First 1

        if ($match -and $match.Matches.Count -gt 0) {
            return $match.Matches[0].Groups[1].Value
        }
    }
    catch { }

    return $null
}

function Get-BysonMostRecentExecutedVersion {
    if (-not (Test-Path $LogDir)) {
        return $null
    }

    try {
        $latestLog = Get-ChildItem `
            -Path $LogDir `
            -Filter 'Byson-Update_*.log' `
            -File `
            -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if (-not $latestLog) {
            return $null
        }

        $versionLine = Select-String `
            -Path $latestLog.FullName `
            -Pattern 'Byson Cyber (?:Endpoint Maintenance|Client Update) v([0-9]+\.[0-9]+\.[0-9]+)' `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($versionLine -and $versionLine.Matches.Count -gt 0) {
            return [PSCustomObject]@{
                Version = $versionLine.Matches[0].Groups[1].Value
                LogPath = $latestLog.FullName
                LogTime = $latestLog.LastWriteTime
            }
        }
    }
    catch { }

    return $null
}


function Get-BysonTaskResultDisplay {
    param(
        [Parameter(Mandatory=$false)]$TaskInfo
    )

    if ($null -eq $TaskInfo) {
        return $null
    }

    $result = [int64]$TaskInfo.LastTaskResult

    switch ($result) {
        0      { return '0 (Success)' }
        267008 { return 'Ready / no recent execution result (0x41300)' }
        267009 { return 'Running (0x41301)' }
        267010 { return 'Task disabled (0x41302)' }
        267011 { return 'Not yet run (0x41303)' }
        267012 { return 'No more scheduled runs (0x41304)' }
        267013 { return 'Task not scheduled (0x41305)' }
        267014 { return 'Last run terminated (0x41306)' }
        267015 { return 'No valid triggers (0x41307)' }
        default {
            return ('{0} (0x{1:X8})' -f $result, $result)
        }
    }
}

function Get-BysonMostRecentSummary {
    if (-not (Test-Path $LogDir)) {
        return $null
    }

    try {
        $files = @(Get-ChildItem `
            -Path $LogDir `
            -Filter 'Byson-Update_*.json' `
            -File `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)

        foreach ($file in $files) {
            try {
                $data = Get-Content -Path $file.FullName -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop

                return [PSCustomObject]@{
                    Data = $data
                    Path = $file.FullName
                    Time = $file.LastWriteTime
                }
            }
            catch { }
        }
    }
    catch { }

    return $null
}

function Test-BysonLegacySummaryLooksLikeMaintenance {
    param(
        [Parameter(Mandatory=$true)][string]$JsonPath
    )

    $logPath = [System.IO.Path]::ChangeExtension($JsonPath, '.log')

    if (-not (Test-Path $logPath)) {
        return $false
    }

    try {
        $logText = Get-Content -Path $logPath -Raw -ErrorAction Stop

        # Legacy configuration/removal runs should never be surfaced as
        # "Last Maintenance" just because their old JSON lacked Operation.
        if ($logText -match '(?im)^.+--- Scheduled Task (Installation|Removal) ---') {
            return $false
        }

        # These section headers are strong evidence that the endpoint actually
        # performed maintenance/audit work.
        if (
            $logText -match '(?im)^.+--- Microsoft Defender ---' -or
            $logText -match '(?im)^.+--- WinGet Applications ---' -or
            $logText -match '(?im)^.+--- Windows Update ---' -or
            $logText -match '(?im)^.+--- OEM Update Provider ---'
        ) {
            return $true
        }
    }
    catch { }

    return $false
}

function Get-BysonMostRecentMaintenanceSummary {
    if (-not (Test-Path $LogDir)) {
        return $null
    }

    try {
        $files = @(Get-ChildItem `
            -Path $LogDir `
            -Filter 'Byson-Update_*.json' `
            -File `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)

        foreach ($file in $files) {
            try {
                $data = Get-Content -Path $file.FullName -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop

                $operation = Get-BysonObjectPropertyValue -Object $data -Name 'Operation'

                if ($operation -eq 'Maintenance') {
                    return [PSCustomObject]@{
                        Data = $data
                        Path = $file.FullName
                        Time = $file.LastWriteTime
                        LegacyInferred = $false
                    }
                }

                # v0.4.x and earlier summaries may not contain Operation.
                # For those, inspect the matching human-readable log and only
                # accept runs that contain real maintenance section markers.
                if (
                    [string]::IsNullOrWhiteSpace([string]$operation) -and
                    (Test-BysonLegacySummaryLooksLikeMaintenance -JsonPath $file.FullName)
                ) {
                    return [PSCustomObject]@{
                        Data = $data
                        Path = $file.FullName
                        Time = $file.LastWriteTime
                        LegacyInferred = $true
                    }
                }
            }
            catch { }
        }
    }
    catch { }

    return $null
}

function Get-BysonObjectPropertyValue {
    param(
        [Parameter(Mandatory=$false)]$Object,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function Show-BysonStatus {
    $deployedVersion = Get-BysonScriptVersionFromFile -Path $InstallPath
    $recentExecution = Get-BysonMostRecentExecutedVersion
    $recentActivity = Get-BysonMostRecentSummary
    $recentMaintenance = Get-BysonMostRecentMaintenanceSummary

    $taskNameUsed = $TaskName
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if (-not $task) {
        $task = Get-ScheduledTask -TaskName $LegacyTaskName -ErrorAction SilentlyContinue
        if ($task) {
            $taskNameUsed = $LegacyTaskName
        }
    }

    $taskInfo = $null
    if ($task) {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskNameUsed -ErrorAction SilentlyContinue
    }

    $taskProfile = $null
    $taskRebootPolicy = $null
    $taskActionPath = $null
    $taskArguments = $null

    if ($task -and $task.Actions -and $task.Actions.Count -gt 0) {
        $taskActionPath = $task.Actions[0].Execute
        $taskArguments = $task.Actions[0].Arguments

        if ($taskArguments -match '(?i)-Profile\s+(Safe|Client|Aggressive|Manual)') {
            $taskProfile = $Matches[1]
        }

        if ($taskArguments -match '(?i)-RebootPolicy\s+(Never|IfRequired|EveryRun)') {
            $taskRebootPolicy = $Matches[1]
        }
    }

    $lastRunDisplay = $null
    $lastResultDisplay = $null

    if ($taskInfo) {
        $lastResultDisplay = Get-BysonTaskResultDisplay -TaskInfo $taskInfo

        if (
            [int64]$taskInfo.LastTaskResult -eq 267011 -or
            $taskInfo.LastRunTime.Year -lt 2000
        ) {
            $lastRunDisplay = 'Never'
        }
        else {
            $lastRunDisplay = $taskInfo.LastRunTime
        }
    }

    $latestActivityOperation = $null
    $latestActivityStatus = $null
    $latestActivityVersion = $null

    if ($recentActivity) {
        $latestActivityOperation = Get-BysonObjectPropertyValue -Object $recentActivity.Data -Name 'Operation'
        $latestActivityStatus = Get-BysonObjectPropertyValue -Object $recentActivity.Data -Name 'OverallStatus'
        $latestActivityVersion = Get-BysonObjectPropertyValue -Object $recentActivity.Data -Name 'ScriptVersion'

        if ([string]::IsNullOrWhiteSpace([string]$latestActivityOperation)) {
            $latestActivityOperation = 'Legacy / unspecified'
        }
    }

    $lastMaintenanceOperationNote = $null
    if ($recentMaintenance -and $recentMaintenance.LegacyInferred) {
        $lastMaintenanceOperationNote = 'Legacy maintenance run inferred from log markers'
    }

    $taskStatusObject = [PSCustomObject]@{
        RunningScriptVersion      = $ScriptVersion
        RunningPowerShellVersion  = $PSVersionTable.PSVersion.ToString()
        DeployedScriptPath        = $InstallPath
        DeployedScriptVersion     = if ($deployedVersion) { $deployedVersion } else { 'Not installed' }
        TaskInstalled             = [bool]$task
        TaskName                  = if ($task) { $taskNameUsed } else { $TaskName }
        TaskEnabled               = if ($task) { $task.State -ne 'Disabled' } else { $false }
        TaskState                 = if ($task) { [string]$task.State } else { 'Not installed' }
        TaskProfile               = if ($taskProfile) { $taskProfile } else { 'Unknown' }
        TaskRebootPolicy          = if ($taskRebootPolicy) { $taskRebootPolicy } else { 'Unknown' }
        LastRunTime               = $lastRunDisplay
        LastTaskResult            = $lastResultDisplay
        NextRunTime               = if ($taskInfo) { $taskInfo.NextRunTime } else { $null }
        MaintenanceRuntime        = 'Stable PowerShell 7.6+ resolved at task runtime'
    }

    $activityObject = [PSCustomObject]@{
        LatestActivityTime        = if ($recentActivity) { $recentActivity.Time } else { $null }
        LatestActivityOperation   = $latestActivityOperation
        LatestActivityStatus      = $latestActivityStatus
        LatestActivityVersion     = $latestActivityVersion
        LatestActivitySummary     = if ($recentActivity) { $recentActivity.Path } else { $null }
        MostRecentLogPath         = if ($recentExecution) { $recentExecution.LogPath } else { $null }
    }

    $maintenanceObject = [PSCustomObject]@{
        DeviceId                  = $DeviceId
        LastMaintenanceTime       = if ($recentMaintenance) { $recentMaintenance.Time } else { 'No maintenance run found' }
        LastMaintenanceStatus     = if ($recentMaintenance) { Get-BysonObjectPropertyValue -Object $recentMaintenance.Data -Name 'OverallStatus' } else { $null }
        LastMaintenanceProfile    = if ($recentMaintenance) { Get-BysonObjectPropertyValue -Object $recentMaintenance.Data -Name 'Profile' } else { $null }
        LastMaintenanceVersion    = if ($recentMaintenance) { Get-BysonObjectPropertyValue -Object $recentMaintenance.Data -Name 'ScriptVersion' } else { $null }
        WindowsUpdatesPending     = if ($recentMaintenance) { Get-BysonObjectPropertyValue -Object $recentMaintenance.Data -Name 'WindowsUpdatesPending' } else { $null }
        RebootRequired            = if ($recentMaintenance) { Get-BysonObjectPropertyValue -Object $recentMaintenance.Data -Name 'RebootRequired' } else { $null }
        SystemDriveFreeGB         = if ($recentMaintenance) { Get-BysonObjectPropertyValue -Object $recentMaintenance.Data -Name 'SystemDriveFreeGB' } else { $null }
        MaintenanceSummaryPath    = if ($recentMaintenance) { $recentMaintenance.Path } else { $null }
        CompatibilityNote         = $lastMaintenanceOperationNote
    }

    Write-Host ''
    Write-Host 'Byson Cyber Endpoint Maintenance Status'
    Write-Host '======================================='

    Write-Host ''
    Write-Host 'Installation / Schedule' -ForegroundColor Cyan
    Write-Host '-----------------------' -ForegroundColor Cyan
    $taskStatusObject | Format-List

    Write-Host 'Latest Activity' -ForegroundColor Cyan
    Write-Host '---------------' -ForegroundColor Cyan
    $activityObject | Format-List

    Write-Host 'Latest Maintenance' -ForegroundColor Cyan
    Write-Host '------------------' -ForegroundColor Cyan
    $maintenanceObject | Format-List

    if (
        $deployedVersion -and
        $recentExecution -and
        $deployedVersion -ne $recentExecution.Version
    ) {
        Write-Host ("WARNING: deployed version {0} differs from most recently executed version {1}." -f $deployedVersion, $recentExecution.Version) -ForegroundColor Yellow
    }

    if ($deployedVersion -and $deployedVersion -ne $ScriptVersion) {
        Write-Host ("NOTE: this source script is v{0}, while the deployed runtime copy is v{1}." -f $ScriptVersion, $deployedVersion) -ForegroundColor Yellow
    }

    Write-Host ''
}

function Install-BysonPwshLauncher {
    $launcherContent = @'
#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Manual','Safe','Client','Aggressive')]
    [string]$Profile = 'Safe',

    [ValidateSet('Never','IfRequired','EveryRun')]
    [string]$RebootPolicy = 'Never',

    [ValidateRange(0,86400)]
    [int]$RebootDelaySeconds = 300,

    [switch]$IncludeFirmware,
    [switch]$AcknowledgeFirmwareRisk,
    [switch]$RecoveryKeyEscrowConfirmed
)

$ErrorActionPreference = 'Stop'
$MainScript = Join-Path $PSScriptRoot 'Byson-ClientUpdate.ps1'

function Test-StablePwshCandidate {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $versionText = (& $Path -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>$null | Select-Object -First 1)

        if ([string]::IsNullOrWhiteSpace($versionText)) {
            return $false
        }

        if ($versionText -match '-') {
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

    # Stable MSI install.
    [void]$candidates.Add((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'))

    # Stable Microsoft.PowerShell MSIX/Store package.
    try {
        $package = Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($package) {
            [void]$candidates.Add((Join-Path $package.InstallLocation 'pwsh.exe'))
        }
    }
    catch { }

    # Other PATH candidates are considered only after validation, so Preview
    # cannot silently win.
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

    throw 'A supported stable PowerShell 7.6+ runtime could not be located.'
}

if (-not (Test-Path $MainScript)) {
    throw "Byson maintenance runtime not found: $MainScript"
}

$pwsh = Get-StablePwshPath

$arguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', $MainScript,
    '-Profile', $Profile,
    '-RebootPolicy', $RebootPolicy,
    '-RebootDelaySeconds', [string]$RebootDelaySeconds
)

if ($IncludeFirmware) {
    $arguments += '-IncludeFirmware'
}

if ($AcknowledgeFirmwareRisk) {
    $arguments += '-AcknowledgeFirmwareRisk'
}

if ($RecoveryKeyEscrowConfirmed) {
    $arguments += '-RecoveryKeyEscrowConfirmed'
}

& $pwsh @arguments
$exitCode = $LASTEXITCODE

if ($null -eq $exitCode) {
    $exitCode = 0
}

exit $exitCode
'@

    Set-Content -Path $PwshLauncherPath -Value $launcherContent -Encoding utf8 -Force
    Write-Log ("Installed stable PowerShell runtime launcher to: {0}" -f $PwshLauncherPath)
}

function Install-BysonScheduledTask {
    Write-Log '--- Scheduled Task Installation ---'

    if ($ScheduledIncludeFirmware -and $ScheduledProfile -ne 'Aggressive') {
        throw '-ScheduledIncludeFirmware is only permitted with -ScheduledProfile Aggressive.'
    }

    if ($ScheduledIncludeFirmware) {
        Write-Log 'Scheduled BIOS/firmware maintenance explicitly requested for Aggressive profile.'

        try {
            $osVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
            $bitLockerActive = (
                $osVolume.ProtectionStatus -eq 'On' -or
                $osVolume.VolumeStatus -match 'Encryption'
            )

            if ($bitLockerActive -and -not $ScheduledRecoveryKeyEscrowConfirmed) {
                throw 'BitLocker is active. Scheduled firmware requires -ScheduledRecoveryKeyEscrowConfirmed.'
            }
        }
        catch {
            if ($_.Exception.Message -like '*Scheduled firmware requires*') {
                throw
            }

            Write-Log ("Unable to fully validate BitLocker during task installation: {0}" -f $_.Exception.Message) 'WARN'
            if (-not $ScheduledRecoveryKeyEscrowConfirmed) {
                throw 'Scheduled firmware requested, but BitLocker state could not be confidently verified. Re-run with -ScheduledRecoveryKeyEscrowConfirmed only after confirming recovery material is available outside this endpoint.'
            }
        }
    }

    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Unable to determine the source script path.'
    }

    if ($PSCommandPath -ne $InstallPath) {
        Copy-Item -Path $PSCommandPath -Destination $InstallPath -Force
        Write-Log ("Installed script to: {0}" -f $InstallPath)
    }

    # Resolve the scheduled reboot policy.
    $resolvedRebootPolicy = $ScheduledRebootPolicy
    if ($resolvedRebootPolicy -eq 'ProfileDefault') {
        $resolvedRebootPolicy = switch ($ScheduledProfile) {
            'Safe'       { 'Never' }
            'Client'     { 'IfRequired' }
            'Aggressive' { 'IfRequired' }
        }
    }

    if ($ScheduledProfile -eq 'Safe' -and $resolvedRebootPolicy -ne 'Never') {
        throw 'Safe scheduled profile only supports -ScheduledRebootPolicy Never.'
    }

    if ($ScheduledProfile -eq 'Client' -and $resolvedRebootPolicy -eq 'EveryRun') {
        throw 'EveryRun reboot policy is reserved for the Aggressive scheduled profile.'
    }

    # Profiles with automatic reboot capability default to an after-hours
    # maintenance window unless the technician explicitly supplies -DailyTime.
    $resolvedDailyTime = $DailyTime
    if (
        -not $script:DailyTimeExplicitlySet -and
        $ScheduledProfile -in @('Client','Aggressive')
    ) {
        $resolvedDailyTime = '22:00'
    }

    # The task points to a stable, non-versioned launcher rather than directly
    # at an MSI/MSIX pwsh.exe path. The launcher resolves the current supported
    # stable PowerShell 7 runtime each time the task runs, so PowerShell package
    # updates do not orphan the task.
    Install-BysonPwshLauncher

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Profile {1} -RebootPolicy {2} -RebootDelaySeconds {3}' -f $PwshLauncherPath, $ScheduledProfile, $resolvedRebootPolicy, $RebootDelaySeconds

    if ($ScheduledIncludeFirmware) {
        $taskArgs += ' -IncludeFirmware -AcknowledgeFirmwareRisk'

        if ($ScheduledRecoveryKeyEscrowConfirmed) {
            $taskArgs += ' -RecoveryKeyEscrowConfirmed'
        }
    }

    $action = New-ScheduledTaskAction -Execute $powershell -Argument $taskArgs

    $userId = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME

    $dailyAt = [datetime]::Today.Add([TimeSpan]::Parse($resolvedDailyTime))
    $dailyTrigger = New-ScheduledTaskTrigger -Daily -At $dailyAt

    $triggers = @($dailyTrigger)

    # Safe never automatically restarts, so a logon fallback is low-risk and
    # useful for laptops that sleep through the daily maintenance window.
    # Client/Aggressive can restart after patching, so never surprise a user
    # with a reboot shortly after sign-in.
    if ($ScheduledProfile -eq 'Safe') {
        $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
        $logonTrigger.Delay = 'PT2M'
        $triggers = @($logonTrigger, $dailyTrigger)
    }

    $principal = New-ScheduledTaskPrincipal `
        -UserId $userId `
        -LogonType Interactive `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -WakeToRun `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    $description = switch ($ScheduledProfile) {
        'Safe' {
            'Byson Cyber Safe maintenance: Defender + normal WinGet updates; Windows/OEM audit; no automatic reboot.'
        }
        'Client' {
            'Byson Cyber Client maintenance: Defender + normal WinGet + Windows Updates; OEM audit; configurable reboot policy.'
        }
        'Aggressive' {
            if ($ScheduledIncludeFirmware) {
                'Byson Cyber Aggressive maintenance: Windows Updates + OEM drivers + guarded BIOS/firmware + aggressive WinGet; configurable reboot policy.'
            }
            else {
                'Byson Cyber Aggressive maintenance: Windows Updates + OEM drivers + aggressive WinGet; configurable reboot policy.'
            }
        }
    }

    if ($LegacyTaskName -ne $TaskName) {
        $legacyTask = Get-ScheduledTask -TaskName $LegacyTaskName -ErrorAction SilentlyContinue
        if ($legacyTask) {
            Unregister-ScheduledTask -TaskName $LegacyTaskName -Confirm:$false
            Write-Log ("Migrated legacy scheduled task name '{0}' to '{1}'." -f $LegacyTaskName, $TaskName)
        }
    }

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $triggers `
        -Principal $principal `
        -Settings $settings `
        -Description $description `
        -Force | Out-Null

    if ($ScheduledProfile -eq 'Safe') {
        Write-Log ("Scheduled task '{0}' created using Safe profile: At Logon (+2 min) + daily at {1}." -f $TaskName, $resolvedDailyTime)
    }
    else {
        Write-Log ("Scheduled task '{0}' created using {1} profile: daily at {2}; no logon trigger. Reboot policy: {3}." -f $TaskName, $ScheduledProfile, $resolvedDailyTime, $resolvedRebootPolicy)
    }

    switch ($ScheduledProfile) {
        'Safe' {
            Write-Log 'Safe profile: Defender updates + normal WinGet updates + Windows/OEM audit. No automatic reboot.'
        }
        'Client' {
            Write-Log ("Client profile: Defender + normal WinGet + Windows Update installation. OEM drivers remain audit-only. Reboot policy: {0}." -f $resolvedRebootPolicy)
        }
        'Aggressive' {
            if ($ScheduledIncludeFirmware) {
                Write-Log ("Aggressive profile: Windows Update installation + OEM drivers + guarded BIOS/firmware + WinGet include-unknown/include-pinned/force. Reboot policy: {0}." -f $resolvedRebootPolicy)
            }
            else {
                Write-Log ("Aggressive profile: Windows Update installation + OEM driver installation + WinGet include-unknown/include-pinned/force. Reboot policy: {0}." -f $resolvedRebootPolicy)
            }
        }
    }

    if ($ScheduledIncludeFirmware) {
        Write-Log 'Scheduled firmware is explicitly enabled. OEM applications remain disabled. Firmware still requires AC power, clean reboot state, and successful BitLocker/recovery preflight at runtime.'
    }
    else {
        Write-Log 'OEM applications and BIOS/firmware are not enabled automatically by this scheduled profile.'
    }
}

function Remove-BysonScheduledTask {
    Write-Log '--- Scheduled Task Removal ---'

    $removed = $false

    foreach ($name in @($TaskName, $LegacyTaskName) | Select-Object -Unique) {
        $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Log ("Scheduled task removed: {0}" -f $name)
            $removed = $true
        }
    }

    if (-not $removed) {
        Write-Log 'No Byson endpoint maintenance scheduled task was installed.'
    }
}

function Install-BysonRebootPromptHelper {
    $helperContent = @'
#requires -Version 7.6
param(
    [Parameter(Mandatory=$true)][int]$Seconds,
    [Parameter(Mandatory=$true)][string]$LogPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'
$script:Remaining = [Math]::Max(0, $Seconds)

function Write-RebootUiLog {
    param([string]$Message)
    try {
        $line = '{0} [INFO] REBOOT-UI: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    } catch { }
}

function Schedule-Restart {
    param([int]$DelaySeconds)
    & $shutdown /r /f /t $DelaySeconds /d p:2:17 /c "Byson Cyber maintenance restart. Please save your work." | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Byson Cyber Maintenance'
$form.Size = New-Object System.Drawing.Size(470,220)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ControlBox = $false
$form.TopMost = $true
$form.ShowInTaskbar = $true
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual

$working = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(
    ($working.Right - $form.Width - 20),
    ($working.Bottom - $form.Height - 20)
)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Maintenance complete — restart pending'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 16)
$form.Controls.Add($title)

$message = New-Object System.Windows.Forms.Label
$message.Text = 'Windows needs to restart. Save your work, or cancel/delay the restart if now is a bad time.'
$message.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$message.Size = New-Object System.Drawing.Size(420, 42)
$message.Location = New-Object System.Drawing.Point(18, 50)
$form.Controls.Add($message)

$countdown = New-Object System.Windows.Forms.Label
$countdown.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$countdown.Size = New-Object System.Drawing.Size(420, 28)
$countdown.Location = New-Object System.Drawing.Point(18, 92)
$form.Controls.Add($countdown)

$restartNow = New-Object System.Windows.Forms.Button
$restartNow.Text = 'Restart now'
$restartNow.Size = New-Object System.Drawing.Size(110, 34)
$restartNow.Location = New-Object System.Drawing.Point(18, 132)
$form.Controls.Add($restartNow)

$delay = New-Object System.Windows.Forms.Button
$delay.Text = 'Delay 1 hour'
$delay.Size = New-Object System.Drawing.Size(110, 34)
$delay.Location = New-Object System.Drawing.Point(140, 132)
$form.Controls.Add($delay)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel restart'
$cancel.Size = New-Object System.Drawing.Size(120, 34)
$cancel.Location = New-Object System.Drawing.Point(262, 132)
$form.Controls.Add($cancel)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000

function Update-Countdown {
    $ts = [TimeSpan]::FromSeconds([Math]::Max(0, $script:Remaining))
    $countdown.Text = ('Restart in {0:mm\:ss}' -f $ts)
}

$restartNow.Add_Click({
    & $shutdown /a | Out-Null
    Write-RebootUiLog 'User selected Restart now.'
    Schedule-Restart -DelaySeconds 0
    $form.Close()
})

$delay.Add_Click({
    & $shutdown /a | Out-Null
    $script:Remaining = 3600
    Schedule-Restart -DelaySeconds 3600
    Write-RebootUiLog 'User delayed restart by 1 hour.'
    Update-Countdown
})

$cancel.Add_Click({
    & $shutdown /a | Out-Null
    Write-RebootUiLog 'User canceled the pending restart.'
    $form.Close()
})

$timer.Add_Tick({
    $script:Remaining--
    Update-Countdown
    if ($script:Remaining -le 0) {
        $timer.Stop()
        $form.Close()
    }
})

Update-Countdown
$timer.Start()
Write-RebootUiLog ("Cancelable restart prompt shown with {0} second(s) remaining." -f $script:Remaining)
[void]$form.ShowDialog()
'@

    Set-Content -Path $RebootPromptPath -Value $helperContent -Encoding utf8 -Force
}

function Cancel-BysonPendingRestart {
    $shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'
    & $shutdown /a | Out-Null
    $code = $LASTEXITCODE

    if ($code -eq 0) {
        Write-Host 'Pending restart canceled.'
        return $true
    }

    Write-Host 'No cancelable shutdown countdown was found.' -ForegroundColor Yellow
    return $false
}

function Request-BysonRestart {
    param(
        [ValidateRange(0,86400)]
        [int]$DelaySeconds = 300
    )

    $shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'

    if ($DelaySeconds -ge 60) {
        $minutes = [math]::Ceiling($DelaySeconds / 60)
        $timeText = if ($minutes -eq 1) { '1 minute' } else { "$minutes minutes" }
    }
    elseif ($DelaySeconds -gt 0) {
        $timeText = "$DelaySeconds seconds"
    }
    else {
        $timeText = 'immediately'
    }

    $comment = "Byson Cyber maintenance completed. This PC will restart $timeText from now. Please save your work."

    Write-Log ("Scheduling Windows restart in {0} second(s). Reboot policy: {1}." -f $DelaySeconds, $RebootPolicy) 'WARN'

    $shutdownArgs = @(
        '/r',
        '/f',
        '/t', [string]$DelaySeconds,
        '/d', 'p:2:17',
        '/c', $comment
    )

    $code = Invoke-LoggedExternal -FilePath $shutdown -ArgumentList $shutdownArgs

    if ($code -eq 0) {
        $script:Summary.ForcedRebootScheduled = $true
        $script:Summary.RebootDelaySeconds = $DelaySeconds

        if ($DelaySeconds -gt 0) {
            try {
                Install-BysonRebootPromptHelper
                $pwsh = Get-BysonPwshPath
                $promptArgs = '-NoProfile -STA -WindowStyle Hidden -File "{0}" -Seconds {1} -LogPath "{2}"' -f $RebootPromptPath, $DelaySeconds, $LogFile
                Start-Process -FilePath $pwsh -ArgumentList $promptArgs -WindowStyle Hidden | Out-Null
                $script:Summary.RebootPromptStarted = $true
                Write-Log 'Cancelable restart control launched. User may Restart now, Delay 1 hour, or Cancel restart.' 'WARN'
            }
            catch {
                Write-Log ("Restart was scheduled, but the cancelable prompt could not be launched: {0}" -f $_.Exception.Message) 'WARN'
                Write-Log 'The restart can still be canceled manually with: shutdown /a' 'WARN'
            }
        }

        return $true
    }

    Write-Log ("Failed to schedule restart. shutdown.exe exit code: {0}" -f $code) 'ERROR'
    return $false
}

if ($ShowVersion) {
    Write-Host ("Byson Cyber Endpoint Maintenance v{0}" -f $ScriptVersion)
    exit 0
}

if ($Status) {
    Show-BysonStatus
    exit 0
}

if ($CancelReboot) {
    if (Cancel-BysonPendingRestart) {
        exit 0
    }
    exit 1
}

try {
    Write-Log ('=' * 72)
    Write-Log ("Byson Cyber Endpoint Maintenance v{0}" -f $ScriptVersion)
    Write-Log ("Started: {0}" -f $RunStartedAt)
    Write-Log ("Schema version: {0}; Run ID: {1}; Device ID: {2}" -f $SchemaVersion, $RunId, $DeviceId)

    if (-not (Enter-BysonRunLock)) {
        $script:Summary.RunSkippedReason = 'Another Byson maintenance/configuration instance is already running.'
        Write-Log $script:Summary.RunSkippedReason 'WARN'
        return
    }

    Remove-BysonExpiredLogs
    Write-Log ("Computer: {0}" -f $env:COMPUTERNAME)
    Write-Log ("Operation: {0}" -f $script:OperationMode)

    if ($script:IsManagementOperation) {
        if ($InstallScheduledTask) {
            Write-Log ("Requested scheduled profile: {0}" -f $ScheduledProfile)
            Write-Log ("Requested scheduled reboot policy: {0}" -f $ScheduledRebootPolicy)
        }
    }
    else {
        Write-Log ("Execution profile: {0}" -f $Profile)

        if ($Profile -eq 'Safe') {
            Write-Log ("Profile policy: Safe -- Defender + normal WinGet updates; Windows/OEM audit; reboot policy: {0}." -f $RebootPolicy)
        }
        elseif ($Profile -eq 'Client') {
            Write-Log ("Profile policy: Client -- Windows Updates enabled; OEM drivers audit-only; reboot policy: {0}." -f $RebootPolicy)
        }
        elseif ($Profile -eq 'Aggressive') {
            Write-Log ("Profile policy: Aggressive -- Windows Updates + OEM drivers + aggressive WinGet; reboot policy: {0}." -f $RebootPolicy)
        }
    }

    if ($script:RebootPendingAtStart) {
        if ($script:IsManagementOperation) {
            Write-Log ('Endpoint currently has a pending reboot: {0}. This configuration operation will not schedule or cancel a restart.' -f ($script:RebootStatusAtStart.BlockingReasons -join '; ')) 'WARN'
        }
        else {
            Write-Log ('A blocking reboot was already pending when this maintenance run started: {0}' -f ($script:RebootStatusAtStart.BlockingReasons -join '; ')) 'WARN'
        }
    }
    else {
        if ($script:IsManagementOperation) {
            Write-Log 'No blocking Windows servicing/update reboot is currently pending on the endpoint.'
        }
        else {
            Write-Log 'No blocking Windows servicing/update reboot was pending at startup.'
        }
    }

    foreach ($rebootAdvisory in $script:RebootStatusAtStart.AdvisoryReasons) {
        Write-Log ("Reboot advisory: {0}" -f $rebootAdvisory) 'INFO'
    }

    if ($IncludeFirmware -and -not $InstallOEMUpdates) {
        Write-Log '-IncludeFirmware was specified without -InstallOEMUpdates. Firmware will be blocked by preflight.' 'WARN'
    }

    Get-BysonSystemHealth
    $script:InstallGuardBlocked = -not (Test-BysonInstallationGuardrails)

    if ($RemoveScheduledTask) {
        Remove-BysonScheduledTask
    }
    elseif ($InstallScheduledTask) {
        Install-BysonScheduledTask
    }
    else {
        Invoke-DefenderMaintenance
        Invoke-WingetMaintenance
        Invoke-WindowsUpdateMaintenance
        Invoke-OEMMaintenance
    }
}
catch {
    Write-Log ("Unhandled script error: {0}" -f $_.Exception.Message) 'ERROR'
}
finally {
    $finalRebootStatus = Get-BysonRebootStatus

    if ($finalRebootStatus.Blocking) {
        $script:Summary.RebootRequired = $true
        $script:Summary.RebootPendingReasons = @($finalRebootStatus.BlockingReasons)
    }

    # Keep advisory-only PFRO visibility in the final JSON without allowing it
    # to mark the workstation as requiring a blocking reboot.
    $script:Summary.RebootAdvisories = @($finalRebootStatus.AdvisoryReasons)

    if ($script:IsManagementOperation) {
        if ($script:Summary.RebootRequired) {
            Write-Log 'Endpoint reboot state: pending. Scheduled-task configuration/removal completed without changing the endpoint reboot state.' 'WARN'
        }
        else {
            Write-Log 'Endpoint reboot state: clear. Scheduled-task configuration/removal completed.'
        }

        # Management operations configure the future task only. They never apply
        # the runtime reboot policy to the current interactive installer session.
        $shouldRestart = $false
    }
    else {
        if ($script:Summary.RebootRequired) {
            Write-Log 'A reboot is pending/recommended.' 'WARN'
        }
        else {
            Write-Log 'No pending reboot was detected.'
        }

        # Apply the configured maintenance reboot policy.
        $shouldRestart = $false

        switch ($RebootPolicy) {
            'IfRequired' {
                $shouldRestart = [bool]$script:Summary.RebootRequired
            }
            'EveryRun' {
                $shouldRestart = -not $AuditOnly
            }
            default {
                $shouldRestart = $false
            }
        }

        if ($shouldRestart) {
            [void](Request-BysonRestart -DelaySeconds $RebootDelaySeconds)
        }
        elseif ($script:Summary.RebootRequired) {
            Write-Log 'A reboot is required, but the current reboot policy is Never. Restart was not scheduled.' 'WARN'
        }
    }

    $completedAt = Get-Date
    $script:Summary.Completed = $completedAt.ToString('o')
    $script:Summary.DurationSeconds = [math]::Round(($completedAt - $RunStartedAt).TotalSeconds)

    if ($script:Summary.ErrorCount -gt 0 -or $script:HadErrors) {
        $script:Summary.OverallStatus = 'Error'
    }
    elseif ($script:Summary.WarningCount -gt 0) {
        $script:Summary.OverallStatus = 'Warning'
    }
    else {
        $script:Summary.OverallStatus = 'Healthy'
    }

    Write-BysonRunSummary

    try {
        $script:Summary | ConvertTo-Json -Depth 6 | Set-Content -Path $SummaryFile -Encoding UTF8
        Write-Log ("JSON summary: {0}" -f $SummaryFile)
    }
    catch {
        Write-Log ("Failed to write JSON summary: {0}" -f $_.Exception.Message) 'ERROR'
    }

    Write-Log ("Completed: {0}" -f $completedAt)
    Write-Log ('=' * 72)

    Exit-BysonRunLock
}

if ($script:HadErrors -or $script:Summary.ErrorCount -gt 0) {
    exit 1
}

exit 0
