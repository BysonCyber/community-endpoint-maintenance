#requires -Version 7.6
#requires -PSEdition Core

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ExpectedVersion = '0.6.2'

$SigningMode = 'UnsignedCommunityBeta'

$requiredFiles = @(
    'Byson-ClientUpdate.ps1',
    'START HERE - Install Byson Maintenance.ps1',
    'START HERE - Install Byson Maintenance.cmd',
    'Install-BysonMaintenance.ps1',
    'INSTALL.md',
    'SIGNING.md',
    'README.md',
    'COMMUNITY-GUIDE.md',
    'CONTRIBUTING.md',
    'SECURITY.md',
    'CHANGELOG.md',
    'ROADMAP.md',
    'RELEASE-CHECKLIST.md',
    'VERSION',
    'LICENSE',
    'schema\byson-maintenance-summary-v1.json'
)

$scriptFiles = @(
    'Byson-ClientUpdate.ps1',
    'START HERE - Install Byson Maintenance.ps1',
    'Install-BysonMaintenance.ps1',
    'Test-Maintenance-Syntax.ps1'
)

$bad = 0

foreach ($name in $requiredFiles) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path $path)) {
        Write-Host ("MISSING required file: {0}" -f $name) -ForegroundColor Red
        $bad++
    }
}

foreach ($name in $scriptFiles) {
    $path = Join-Path $PSScriptRoot $name

    if (-not (Test-Path $path)) {
        Write-Host ("MISSING script: {0}" -f $name) -ForegroundColor Red
        $bad++
        continue
    }

    try {
        $bytes = Get-Content -Path $path -AsByteStream -TotalCount 3
        if ($bytes.Count -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
            Write-Host ("ENCODING WARNING {0}: expected UTF-8 with BOM." -f $name) -ForegroundColor Yellow
            $bad++
        }
    }
    catch {
        Write-Host ("ENCODING CHECK FAILED {0}: {1}" -f $name, $_.Exception.Message) -ForegroundColor Yellow
        $bad++
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)

    if ($errors.Count -gt 0) {
        foreach ($err in $errors) {
            Write-Host ("PARSE ERROR {0}: {1} line {2}" -f $name, $err.Message, $err.Extent.StartLineNumber) -ForegroundColor Red
        }
        $bad += $errors.Count
        continue
    }

    $reserved = @(
        'home','host','pid','pshome','psversiontable','true','false',
        'error','input','matches','args','myinvocation','psscriptroot',
        'pscommandpath','lastexitcode'
    )

    $writes = @($ast.FindAll({
        param($node)

        if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst]) {
            return $false
        }

        if ($node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
            return $false
        }

        $varName = $node.Left.VariablePath.UserPath.ToLowerInvariant()
        return $varName -in $reserved
    }, $true))

    if ($writes.Count -gt 0) {
        foreach ($write in $writes) {
            Write-Host ("RESERVED/AUTOMATIC VARIABLE WRITE {0}: {1}" -f $name, $write.Extent.Text) -ForegroundColor Yellow
        }
        $bad += $writes.Count
    }
    else {
        Write-Host ("PASS PowerShell parse + automatic-variable hygiene: {0}" -f $name) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host ("Release signing mode: {0}" -f $SigningMode) -ForegroundColor Cyan

foreach ($name in $scriptFiles) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path $path)) { continue }

    try {
        $signature = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop

        if ($SigningMode -eq 'UnsignedCommunityBeta') {
            if ($signature.Status -eq 'NotSigned') {
                Write-Host ("INFO Authenticode: {0} is unsigned (expected for Community Beta)." -f $name) -ForegroundColor Yellow
            }
            elseif ($signature.Status -eq 'Valid') {
                Write-Host ("PASS Authenticode: {0} has a valid signature." -f $name) -ForegroundColor Green
            }
            else {
                Write-Host ("SIGNATURE WARNING {0}: status={1}" -f $name, $signature.Status) -ForegroundColor Yellow
            }
        }
        elseif ($SigningMode -eq 'RequireValidSignature') {
            if ($signature.Status -ne 'Valid') {
                Write-Host ("SIGNATURE ERROR {0}: expected Valid, got {1}" -f $name, $signature.Status) -ForegroundColor Red
                $bad++
            }
            else {
                Write-Host ("PASS Authenticode: {0}" -f $name) -ForegroundColor Green
            }
        }
    }
    catch {
        if ($SigningMode -eq 'RequireValidSignature') {
            Write-Host ("SIGNATURE ERROR {0}: {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
            $bad++
        }
        else {
            Write-Host ("SIGNATURE INFO {0}: unable to query Authenticode status: {1}" -f $name, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

$mainPath = Join-Path $PSScriptRoot 'Byson-ClientUpdate.ps1'
if (Test-Path $mainPath) {
    $mainText = Get-Content -Path $mainPath -Raw

    $versionPattern = '\$ScriptVersion\s*=\s*[''"]{0}[''"]' -f [regex]::Escape($ExpectedVersion)
    if ($mainText -notmatch $versionPattern) {
        Write-Host ("VERSION ERROR: main script does not declare {0}" -f $ExpectedVersion) -ForegroundColor Red
        $bad++
    }

    $schemaPattern = '\$SchemaVersion\s*=\s*[''"]1\.0[''"]'
    if ($mainText -notmatch $schemaPattern) {
        Write-Host 'SCHEMA ERROR: expected JSON schema version 1.0 declaration was not found.' -ForegroundColor Red
        $bad++
    }

    if ($mainText -match 'C:\\Users\\|OneDrive - ') {
        Write-Host 'HYGIENE ERROR: personal development path detected in main script.' -ForegroundColor Red
        $bad++
    }
}

$versionFile = Join-Path $PSScriptRoot 'VERSION'
if (Test-Path $versionFile) {
    $versionValue = (Get-Content -Path $versionFile -Raw).Trim()
    if ($versionValue -ne $ExpectedVersion) {
        Write-Host ("VERSION ERROR: VERSION file is {0}, expected {1}." -f $versionValue, $ExpectedVersion) -ForegroundColor Red
        $bad++
    }
}

$schemaFile = Join-Path $PSScriptRoot 'schema\byson-maintenance-summary-v1.json'
if (Test-Path $schemaFile) {
    try {
        $null = Get-Content -Path $schemaFile -Raw | ConvertFrom-Json -ErrorAction Stop
        Write-Host 'PASS JSON schema file parses.' -ForegroundColor Green
    }
    catch {
        Write-Host ("SCHEMA JSON ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
        $bad++
    }
}

if ($bad -gt 0) {
    throw "$bad source/package validation issue(s) found. Do not install or publish until addressed."
}

Write-Host ''
Write-Host ''
Write-Host 'Launcher guidance:' -ForegroundColor Cyan
Write-Host '  Recommended : Right-click START HERE - Install Byson Maintenance.cmd -> Run as administrator.' -ForegroundColor Green
Write-Host '  Fallback    : Launch START HERE - Install Byson Maintenance.ps1 from PowerShell/Windows Terminal.' -ForegroundColor Yellow
Write-Host '  Note        : Normal double-click may be blocked by Smart App Control / App Control on some systems.' -ForegroundColor Yellow
Write-Host ''

Write-Host 'PASS - Community package source files parsed and required release files are present.' -ForegroundColor Green

if ($SigningMode -eq 'UnsignedCommunityBeta') {
    Write-Host 'NOTE - This is an unsigned Community Beta. Smart App Control / App Control compatibility is not guaranteed.' -ForegroundColor Yellow
    Write-Host 'Do not disable Windows security controls to work around trust enforcement.' -ForegroundColor Yellow
}

Write-Host 'Runtime update behavior still requires testing on a Windows endpoint before release.' -ForegroundColor Yellow
