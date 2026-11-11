#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Installer = Join-Path $ScriptDir 'Install-BysonMaintenance.ps1'
$Validator = Join-Path $ScriptDir 'Test-Maintenance-Syntax.ps1'

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

        # Preview/RC builds include a prerelease suffix such as 7.7.0-rc.1.
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

    # Traditional stable MSI install.
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

    # PATH candidates are last because Preview and stable can coexist.
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

    return $null
}

function Install-StablePowerShell {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue

    if (-not $winget) {
        throw 'Stable PowerShell 7.6+ was not found, and WinGet is unavailable. Install the stable Microsoft PowerShell package and retry.'
    }

    Write-Host ''
    Write-Host 'Stable PowerShell 7.6+ was not found.' -ForegroundColor Yellow
    $answer = Read-Host 'Install the current stable Microsoft PowerShell package with WinGet now? [Y/n]'

    if ($answer -match '^(?i)n(?:o)?$') {
        throw 'PowerShell installation was declined. Byson Endpoint Maintenance requires stable PowerShell 7.6+.'
    }

    Write-Host 'Installing Microsoft.PowerShell...' -ForegroundColor Cyan

    & $winget.Source install `
        --id Microsoft.PowerShell `
        --exact `
        --source winget `
        --accept-source-agreements `
        --accept-package-agreements `
        --silent

    if ($LASTEXITCODE -ne 0) {
        Write-Host ("WinGet returned exit code {0}. Re-checking for an installed stable runtime..." -f $LASTEXITCODE) -ForegroundColor Yellow
    }
}

if (-not (Test-Path $Installer)) {
    throw "Installer script not found: $Installer"
}

if (-not (Test-Path $Validator)) {
    throw "Validation script not found: $Validator"
}

Write-Host ''
Write-Host 'UNSIGNED COMMUNITY BETA' -ForegroundColor Yellow
Write-Host '-----------------------' -ForegroundColor Yellow
Write-Host 'This community release is not Authenticode-signed.' -ForegroundColor Yellow
Write-Host 'Smart App Control / App Control may block unsigned scripts on enforced systems.' -ForegroundColor Yellow
Write-Host 'Do NOT disable Windows security controls just to run this tool.' -ForegroundColor Yellow
Write-Host 'See INSTALL.md and SIGNING.md for details.'
Write-Host ''

$pwsh = Get-StablePwshPath

if (-not $pwsh) {
    Install-StablePowerShell
    Start-Sleep -Seconds 2
    $pwsh = Get-StablePwshPath
}

if (-not $pwsh) {
    Write-Host ''
    Write-Host 'A supported stable PowerShell 7.6+ runtime still could not be located.' -ForegroundColor Red
    Write-Host 'Preview/RC builds are intentionally ignored.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Useful diagnostics:'
    Write-Host '  winget list --id Microsoft.PowerShell --exact'
    Write-Host '  winget list --id Microsoft.PowerShell.Preview --exact'
    exit 1
}

$version = & $pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' | Select-Object -First 1

Write-Host ''
Write-Host 'Byson Cyber Endpoint Maintenance' -ForegroundColor Cyan
Write-Host 'Community Beta v0.6.2' -ForegroundColor Cyan
Write-Host ''
Write-Host ("Stable PowerShell: {0}" -f $version) -ForegroundColor Green
Write-Host ("Runtime path: {0}" -f $pwsh)
Write-Host 'Running local package validation...' -ForegroundColor Cyan
Write-Host ''

& $pwsh -NoProfile -ExecutionPolicy Bypass -File $Validator

if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host 'Package validation failed. Installation was stopped.' -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ''
& $pwsh -NoProfile -ExecutionPolicy Bypass -File $Installer
exit $LASTEXITCODE
