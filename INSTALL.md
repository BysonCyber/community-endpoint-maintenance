# Installation

## Unsigned Community Beta

**v0.6.2 Community Beta is intentionally unsigned.**

Smart App Control, App Control for Business, WDAC, or another application-control policy may block the unsigned PowerShell entrypoint before the installer runs.

**Do not disable Smart App Control, App Control, antivirus, or other Windows security controls just to install this utility.**

If your organization requires signed code, wait for a signed release or use an internally reviewed/signing process appropriate for your environment.

## Recommended installation

### Recommended — right-click and run as administrator

After extracting the ZIP:

1. Locate:

```text
START HERE - Install Byson Maintenance.cmd
```

2. Right-click it.
3. Choose **Run as administrator**.
4. Approve the UAC prompt.

This was validated on a Smart App Control-enabled Windows endpoint where a normal double-click was blocked but **Run as administrator** succeeded.

### Why not just double-click?

On some Smart App Control / App Control configurations, the normal:

```text
Explorer -> cmd.exe
```

launch chain can be blocked before the Byson PowerShell bootstrap starts.

That does **not** mean Byson is bypassing Smart App Control when run elevated. It simply reflects a different Windows/UAC launch context.

The Community Beta remains unsigned and can still be blocked by application-control policy.

### PowerShell fallback

If the convenience launcher is blocked, open Windows Terminal or PowerShell in the extracted release folder and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\START HERE - Install Byson Maintenance.ps1"
```

If already using stable PowerShell 7.6+:

```powershell
& ".\START HERE - Install Byson Maintenance.ps1"
```

The bootstrap:

1. locates a supported stable PowerShell 7.6+ runtime;
2. offers to install stable `Microsoft.PowerShell` with WinGet if missing;
3. runs the local package validator;
4. launches the interactive installer.

Preview/RC PowerShell builds are intentionally not used for scheduled maintenance.

## Execution policy is not application control

`-ExecutionPolicy Bypass` changes PowerShell execution-policy behavior for that process.

It does **not** override Smart App Control, App Control for Business, WDAC, or another application-control policy.

If Windows blocks the unsigned script, that is a trust limitation of the unsigned Community Beta—not a reason to weaken the protection.

## Installed locations

Runtime:

```text
C:\ProgramData\Byson Cyber\Maintenance\
```

Logs:

```text
C:\ProgramData\Byson Cyber\Maintenance\Logs\
```

Scheduled task:

```text
Byson Cyber - Endpoint Maintenance
```
