# Byson Cyber — Community Endpoint Maintenance Utility

**Community Beta v0.6.2**  
**License:** MIT  
**Runtime:** Stable PowerShell 7.6+  
**Primary platform:** Windows 11

A local-first PowerShell utility for small environments that need practical Windows endpoint maintenance without deploying a full MDM/RMM platform.

It can update Microsoft Defender intelligence, maintain WinGet applications, scan/install Windows Updates, audit/install supported OEM drivers, optionally perform guarded Dell BIOS/firmware maintenance, manage scheduled maintenance/reboots, and write local human-readable + JSON results.

> **Community edition is local-only.** There is no Byson cloud service, telemetry collector, remote shell, or remote command channel in v0.5.0.

## Why this exists

A lot of small environments have Windows Update enabled but no repeatable process for third-party application updates, OEM drivers, reboot handling, or basic maintenance visibility.

This project is intentionally narrower than Intune, an RMM, or an MDM. It aims to answer:

> **“Can I keep these Windows endpoints reasonably maintained and know what needs attention without deploying a giant management stack?”**

## Quick start

> **Unsigned Community Beta:** v0.6.2 is not Authenticode-signed. Smart App Control / App Control may block it on enforced systems. **Do not disable Windows security controls to work around that block.** See [`INSTALL.md`](INSTALL.md) and [`SIGNING.md`](SIGNING.md).

1. Download/extract the release ZIP to a normal folder.
2. **Recommended:** right-click `START HERE - Install Byson Maintenance.cmd` and choose **Run as administrator**.
3. Approve UAC when requested.
4. Choose Safe, Client, or Aggressive.
5. Pick a daily maintenance time and reboot policy.
6. Review the configuration summary and confirm.

If Windows blocks the convenience launcher, open Windows Terminal/PowerShell in the extracted folder and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\START HERE - Install Byson Maintenance.ps1"
```

The bootstrap validates the local package before installation and uses/installs a supported **stable PowerShell 7.6+** runtime. Preview/RC builds are intentionally not used for scheduled maintenance.

`-ExecutionPolicy Bypass` does not bypass Smart App Control/App Control.

## Profiles

| Profile | Defender | WinGet | Windows Update | OEM drivers | Automatic reboot |
|---|---|---|---|---|---|
| **Safe** | Update | Normal updates | Scan only | Scan only | Never |
| **Client** | Update | Normal updates | Install | Scan only | Never or IfRequired |
| **Aggressive** | Update | `--include-unknown`, `--include-pinned`, `--force` | Install | Install when supported | Never, IfRequired, or EveryRun |

**OEM applications are excluded by default.**  
**BIOS/firmware are explicit opt-in and guarded.**

## v0.6.2 highlights

- Stable PowerShell 7.6+ runtime selection; Preview/RC builds are rejected for scheduled maintenance.
- Beginner-friendly interactive installer with a configuration review before changes.
- Safe / Client / Aggressive profiles.
- Optional immediate “run installed maintenance now” action.
- Reboot policies: `Never`, `IfRequired`, `EveryRun`.
- Configurable restart countdown plus cancel/delay UI.
- `-CancelReboot` fallback.
- Windows Update, Defender, WinGet, and Dell Command | Update integration.
- Guarded Dell BIOS/firmware workflow with AC/reboot/BitLocker checks.
- Global run lock prevents overlapping manual/scheduled maintenance.
- Low-disk guard defaults to **10 GB free** before install actions; scans continue when blocked.
- Local log/JSON retention defaults to **30 days**.
- Stable random per-device ID and per-run ID for future dashboard/report correlation.
- Dashboard-ready JSON `SchemaVersion = 1.0`.
- Local inventory includes OS/build, BIOS, free disk, Secure Boot, TPM, BitLocker/recovery-protector state, update/reboot state, and OEM information.
- Maintenance errors now return a non-zero process/Task Scheduler result.
- Included syntax/package validator, MIT license, community guide, security policy, changelog, contribution guide, release checklist, installation guide, and signing roadmap.
- Validated install path on a Smart App Control-enabled test endpoint: right-click the `.cmd` launcher and choose **Run as administrator**.
- Keeps the `.ps1` entrypoint as the documented fallback for restricted environments.
- Removes the experimental `.lnk` launcher now that a simpler workflow has been validated.
- Validator reports Authenticode state and treats unsigned scripts as expected for this Community Beta.

## Installed locations

Runtime files:

```text
C:\ProgramData\Byson Cyber\Maintenance\
```

Logs and JSON:

```text
C:\ProgramData\Byson Cyber\Maintenance\Logs\
```

Scheduled task:

```text
Byson Cyber - Endpoint Maintenance
```

The scheduled task points to a stable launcher under ProgramData. That launcher resolves the current supported stable PowerShell 7 runtime each time maintenance starts, so a PowerShell MSIX/MSI update should not orphan the task.

## Reboot behavior

When maintenance schedules a restart with a delay, the utility attempts to display a small user control with:

- **Restart now**
- **Delay 1 hour**
- **Cancel restart**

The Windows shutdown timer is authoritative. A pending restart can also be canceled from an elevated shell:

```powershell
shutdown /a
```

or:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Byson-ClientUpdate.ps1" `
  -CancelReboot
```

## Status

From an elevated stable PowerShell 7 session:

```powershell
.\Byson-ClientUpdate.ps1 -Status
```

Status includes:

- source/deployed version;
- task profile and reboot policy;
- task state, next run, last result;
- stable device ID;
- most recent maintenance health;
- pending Windows updates from the last maintenance run;
- last reboot requirement;
- last recorded system-drive free space.

## Manual examples

Audit only:

```powershell
.\Byson-ClientUpdate.ps1 -AuditOnly
```

Client maintenance:

```powershell
.\Byson-ClientUpdate.ps1 -Profile Client
```

Aggressive maintenance:

```powershell
.\Byson-ClientUpdate.ps1 -Profile Aggressive
```

Aggressive + guarded Dell firmware:

```powershell
.\Byson-ClientUpdate.ps1 `
  -Profile Aggressive `
  -IncludeFirmware `
  -AcknowledgeFirmwareRisk `
  -RecoveryKeyEscrowConfirmed
```

Low-disk safety override (technician-controlled only):

```powershell
.\Byson-ClientUpdate.ps1 `
  -Profile Aggressive `
  -IgnoreDiskSpaceGuard
```

## Scheduled-task behavior

Installed tasks are configured to:

- run with highest privileges;
- wake the PC;
- run on battery;
- continue if AC power is removed;
- start when available if the normal time was missed;
- ignore duplicate Task Scheduler starts;
- use a two-hour execution limit.

**Important:** the task uses an interactive user token. It is designed for PCs where that user remains signed in/locked/sleeping. It is not a SYSTEM-service replacement and is not intended to run after a full sign-out with no interactive user session.

## Firmware safety

Firmware is intentionally opt-in.

For an actual Dell BIOS/firmware install, the utility requires:

- OEM installation mode enabled;
- explicit firmware-risk acknowledgement;
- no blocking servicing reboot;
- AC power;
- readable BitLocker state;
- a recovery-password protector when the OS volume is encrypted;
- explicit acknowledgement that the recovery key is available outside the endpoint.

A failed firmware preflight **blocks firmware and reports a warning**; it does not treat the safe block itself as a script crash.

## OEM support

### Dell
Current mature OEM adapter through Dell Command | Update:

- driver audit/install;
- OEM application audit/install only when explicitly requested;
- guarded BIOS/firmware audit/install.

### HP / Lenovo
Manufacturer detection exists, but vendor-specific installation adapters are not implemented yet. Windows Update, Defender, and WinGet maintenance still function.

## Package managers

v0.6.2 manages applications through **WinGet**.

Chocolatey, Scoop, and other package managers are potential future provider adapters. The project intentionally does not run multiple package managers blindly against the same software because overlapping ownership can create upgrade conflicts.

## Local data and privacy

The Community utility does **not** send results to Byson Cyber.

Local JSON/log files can include:

- hostname;
- Windows build;
- manufacturer/model;
- BIOS version;
- update titles/status;
- OEM details;
- generated random device/run IDs;
- BitLocker protection state (never the recovery key).

Review and sanitize logs before posting them publicly or attaching them to a GitHub issue.

## Dashboard-ready reporting

Each run writes structured JSON with:

- `SchemaVersion`
- `ScriptVersion`
- `RunId`
- `DeviceId`
- profile/operation
- endpoint inventory
- patch state
- security posture signals
- OEM state
- reboot state
- warning/error counts
- `OverallStatus`

The current Community edition stores that JSON locally only. The schema is intentionally designed so a future optional dashboard can ingest the same results without rewriting the endpoint engine.

See [`schema/byson-maintenance-summary-v1.json`](schema/byson-maintenance-summary-v1.json).

## What this is not

This project is **not**:

- an EDR;
- a vulnerability scanner;
- a full MDM/RMM;
- a remote shell;
- a remote-control agent;
- an application allowlisting product;
- a guarantee that every installed application is patched;
- a substitute for backups, tested recovery, change control, or an organization's patch policy.

## Windows support note

Windows 11 is the primary target.

Windows 10 may still execute portions of the utility, but Windows 10 servicing/support depends on edition and ESU/LTSC status. Do not interpret script execution as proof that the underlying OS remains vendor-supported.

## Unsigned release / application control

The Community Beta is currently unsigned. Application-control-enforced systems may block it before the bootstrap runs.

This project does **not** recommend disabling Smart App Control, App Control, WDAC, antivirus, or other protections to install the tool.

See [`INSTALL.md`](INSTALL.md) and [`SIGNING.md`](SIGNING.md).

## Before publishing a release

Run:

```powershell
.\Test-Maintenance-Syntax.ps1
```

Then follow [`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md).

## Community / support

Issues and pull requests are welcome. Please read:

- [`INSTALL.md`](INSTALL.md)
- [`SIGNING.md`](SIGNING.md)
- [`COMMUNITY-GUIDE.md`](COMMUNITY-GUIDE.md)
- [`CONTRIBUTING.md`](CONTRIBUTING.md)
- [`SECURITY.md`](SECURITY.md)
- [`ROADMAP.md`](ROADMAP.md)

Community support is best-effort. Do not post client secrets, credentials, BitLocker recovery keys, or unredacted customer logs.

## License

MIT License. See [`LICENSE`](LICENSE).

---

**Byson Cyber LLC**  
Practical security for small organizations.  
**Into the Storm 🦬**
