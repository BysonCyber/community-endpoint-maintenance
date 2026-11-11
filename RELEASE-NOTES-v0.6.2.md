# Byson Cyber Endpoint Maintenance Utility — v0.6.2 Community Beta

v0.6.2 locks in the validated installer workflow for the unsigned Community Beta.

## Recommended install

After extracting the ZIP:

1. Right-click:

```text
START HERE - Install Byson Maintenance.cmd
```

2. Choose **Run as administrator**.
3. Approve UAC.

This flow was tested successfully on a Smart App Control-enabled Windows endpoint where normal double-click launch was blocked.

## Fallback

If the convenience launcher is blocked:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\START HERE - Install Byson Maintenance.ps1"
```

## Important trust limitation

The Community Beta remains unsigned.

Successful launch with **Run as administrator** is not a Smart App Control bypass and does not make the PowerShell source trusted.

Do not disable Smart App Control, App Control for Business, WDAC, antivirus, or other protections to install Byson Endpoint Maintenance.

See `INSTALL.md` and `SIGNING.md`.
