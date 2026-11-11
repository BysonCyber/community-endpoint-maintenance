# Community guide: Byson Cyber Endpoint Maintenance

## First time running the tool

Extract the release ZIP.

Recommended install:

1. Right-click:

```text
START HERE - Install Byson Maintenance.cmd
```

2. Choose **Run as administrator**.
3. Approve UAC.

On the Smart App Control-enabled test endpoint used during development, a normal double-click was blocked while **Run as administrator** succeeded.

If the convenience launcher is still blocked, use Windows Terminal/PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\START HERE - Install Byson Maintenance.ps1"
```

The bootstrap checks for a supported stable PowerShell 7.6+ runtime and validates the package before the installer opens.

**v0.6.2 Community Beta is unsigned.** Smart App Control / App Control may block unsigned scripts. Do not disable Windows security controls just to install the utility. See `INSTALL.md`.

For a first deployment, **Safe** is the lowest-risk profile. It updates Defender and normal WinGet applications while keeping Windows Update and OEM maintenance in audit-only mode.

## Who this is for

This community project is aimed at:

- small businesses with a handful of Windows PCs;
- consultants/fractional IT providers;
- homelabs and technically managed personal systems;
- environments that need practical patch hygiene but do not need a full MDM/RMM platform.

It is intentionally not trying to recreate Intune, an enterprise RMM, or a remote administration suite.

## The three profiles

| Profile | Intent |
|---|---|
| **Safe** | Low-risk recurring maintenance and visibility |
| **Client** | Normal SMB workstation patching with controlled reboot behavior |
| **Aggressive** | More automated application/OEM driver maintenance for systems where that tradeoff is acceptable |

Profiles are convenience presets, not security grades.

## A green run does not mean “fully secure”

A successful maintenance run means the checks/actions performed by this utility completed within their configured scope.

It does not prove:

- there are no vulnerabilities;
- every application is managed by WinGet;
- firmware is current on unsupported OEMs;
- the OS is still in vendor support;
- EDR/AV controls are correctly configured beyond the limited Defender signals collected here;
- backups or recovery processes work.

Treat the output as maintenance evidence, not an attestation.

## Why application ownership matters

WinGet is the current package-management provider. Some applications:

- are not represented in WinGet;
- expose an unknown installed version;
- use their own auto-updater;
- are pinned;
- were installed through another package manager.

Do not blindly add Chocolatey/Scoop/etc. to the same endpoint and let every provider manage the same application. Future provider adapters should define ownership and avoid duplicate management.

## OEM updates

Dell is the current supported OEM adapter.

HP and Lenovo are detected but their vendor-specific adapters are not implemented yet.

OEM **applications** are excluded by default because vendor “recommended” software can include utilities that are not required for basic endpoint maintenance.

## Firmware

Firmware is an advanced, explicit opt-in.

The utility intentionally blocks firmware when it cannot confirm the required safety conditions. A blocked firmware attempt is not a crash; it is the safety system doing its job.

Keep recovery material outside the endpoint before allowing automated firmware maintenance.

## Reboots

`IfRequired` is the recommended default for Client/Aggressive systems.

`EveryRun` can be useful for a nightly workstation reboot, but it is deliberately restricted to Aggressive scheduled profiles because it changes user experience even when no patch requires a restart.

Users can cancel or delay the restart during the countdown. Administrators can also use `shutdown /a`.

## Low-disk guard

Install actions are deferred when the Windows system drive has less than 10 GB free (default).

Audits still run so the endpoint can report why changes were skipped.

`-IgnoreDiskSpaceGuard` exists for a technician who has manually evaluated the situation; do not make that override a default scheduled setting.

## Logs and privacy

Community results remain local under:

```text
C:\ProgramData\Byson Cyber\Maintenance\Logs
```

Logs may expose client/device context. Before sharing:

- remove customer names;
- redact usernames/paths where appropriate;
- remove internal hostnames if sensitive;
- never share credentials or BitLocker recovery keys.

The generated `DeviceId` is a random local identifier, not a hardware serial number.

## Dashboard-ready does not mean cloud-connected

v0.6.0 writes stable JSON fields so future reporting software can consume them.

There is currently:

- no Byson API call;
- no telemetry;
- no remote command queue;
- no remote shell;
- no endpoint count/licensing service.

That boundary is intentional.

## Safe community contribution principles

When proposing changes:

1. Preserve safe defaults.
2. Keep active maintenance explicit.
3. Fail closed for firmware.
4. Avoid collecting secrets.
5. Avoid arbitrary remote code execution features in the Community endpoint.
6. Prefer provider adapters over hardcoded vendor spaghetti.
7. Keep local/noninteractive automation working.
8. Test changes on a non-critical Windows endpoint before recommending broad rollout.

## Things learned while building this

- Windows Update “install succeeded” can still require a real servicing reboot before the build changes.
- Reboot detection needs authoritative servicing signals; `PendingFileRenameOperations` alone creates false positives.
- Dell Command | Update changes CLI behavior between releases and can self-update during a run.
- Dell native log paths have restrictions.
- OEM application updates are not the same thing as OEM driver updates.
- MSIX PowerShell installs can move between versioned WindowsApps locations, so Scheduled Tasks should not bind permanently to a package-version path.
- Preview PowerShell can coexist with stable PowerShell; production maintenance should intentionally select stable/LTS.

## Community scope

Ideas that fit this project:

- better reporting/inventory;
- additional safe package-manager adapters;
- HP/Lenovo OEM adapters;
- patch-ring metadata;
- offline dashboard/report generation;
- better compatibility/testing.

Ideas that materially change the security model (remote shell, arbitrary remote SYSTEM execution, credential collection, remote-control tooling) should be treated as a separate architecture/product discussion rather than casually added to this Community agent.

---

No automated maintenance script should claim a machine is fully secure from a green status alone.

**Byson Cyber — Into the Storm 🦬**
