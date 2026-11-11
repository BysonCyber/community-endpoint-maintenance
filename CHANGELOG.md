# Changelog

## v0.6.2 — Validated elevated convenience launcher (2026-11-11)

- Documents the validated Community Beta install path: right-click `START HERE - Install Byson Maintenance.cmd` and choose **Run as administrator**.
- Retains the PowerShell `.ps1` entrypoint as the fallback for restricted/application-control environments.
- Removes the experimental `.lnk` launcher after the simpler elevated `.cmd` workflow succeeded on the Smart App Control-enabled test endpoint.
- Clarifies that successful elevated launch is not a Smart App Control bypass and does not make unsigned Byson scripts trusted.
- Updates README, install guide, community guide, validator output, and release checklist to use the same installation guidance.

## v0.6.1 — Multi-launcher compatibility experiment (2026-11-11)

- Restores `START HERE - Install Byson Maintenance.cmd` as the simple double-click convenience launcher.
- Keeps `START HERE - Install Byson Maintenance.ps1` as the documented PowerShell fallback.
- Adds `EXPERIMENTAL - Start Byson Maintenance.lnk`, which targets Windows PowerShell directly and attempts to run the sibling bootstrap without the `cmd.exe` hop.
- Keeps all Smart App Control/App Control warnings: the shortcut is a compatibility experiment, **not** a security bypass and does not make unsigned scripts trusted.
- Expands release validation/checklists to test all three launcher paths.

## v0.6.0 — Public unsigned-distribution model (2026-11-11)

- Removes the `.cmd` public launcher after Smart App Control testing showed Explorer-to-`cmd.exe` can be blocked before the PowerShell bootstrap starts.
- Renames the bootstrap to `START HERE - Install Byson Maintenance.ps1` and makes PowerShell/Windows Terminal the supported entrypoint.
- Documents that the Community Beta is unsigned and may be blocked by Smart App Control, App Control for Business, WDAC, or similar policy.
- Explicitly advises users **not** to disable Windows security controls as an installation workaround.
- Adds `INSTALL.md` and `SIGNING.md`.
- Adds Authenticode status reporting to the package validator.
- Adds validator signing mode `UnsignedCommunityBeta`, with a future `RequireValidSignature` release path.
- Retains MIT licensing, SHA-256 manifests, local package validation, and local-only operation.

## v0.5.2 — Status UX / legacy history compatibility (2026-11-10)

- Translates Task Scheduler's `0x41303` / `267011` state into `Not yet run` and displays sentinel pre-run timestamps as `Never`.
- Splits status output into **Installation / Schedule**, **Latest Activity**, and **Latest Maintenance** sections.
- Searches backward through JSON history for the most recent true maintenance run instead of treating task installation/removal as maintenance telemetry.
- Adds backward compatibility for pre-`Operation` JSON summaries by checking matching legacy log section markers.
- Displays the maintenance summary path and a compatibility note when a legacy run was inferred.
- Keeps installation/configuration activity visible without overwriting the user's last meaningful maintenance health.

## v0.5.1 — Validator / public package hygiene hotfix (2026-11-10)

- Renames internal scratch variables that wrote to PowerShell's automatic `$args` variable.
- Corrects the package validator so idiomatic `$null = ...` output-discard assignments are not treated as forbidden writes.
- Improves validator output to distinguish PowerShell parse checks from automatic-variable hygiene checks.
- Regenerates release metadata and SHA-256 checksums.

## v0.5.0 — Community release hardening (2026-11-10)

### Endpoint/runtime
- Requires stable PowerShell 7.6+ Core; Preview/RC runtimes are excluded from scheduled maintenance.
- Public package now uses the stable versionless `Byson-ClientUpdate.ps1` filename; version lives in script metadata/changelog.
- Renames the scheduled task to `Byson Cyber - Endpoint Maintenance` and automatically removes/migrates the legacy `Byson Cyber - Client Update` task during upgrade.
- Adds a stable random `DeviceId` and per-run `RunId`.
- Adds JSON `SchemaVersion = 1.0` for future dashboard/report consumers.
- Adds system inventory fields for OS/build, BIOS, free disk, Secure Boot, TPM, and BitLocker state.
- Adds `OverallStatus`, warning/error counts, and duration to the JSON summary.
- True `ERROR` conditions now produce a non-zero process/Task Scheduler result.
- Safe firmware preflight blocks are WARN rather than script failures.
- Adds a global named mutex to prevent overlapping manual/scheduled runs.
- Adds a default 10 GB free-space install guard. Audits continue when installation is deferred.
- Adds 30-day local log/JSON retention.
- Dell no-update classification now also checks native DCU log content, including `NO_INVENTORIED_UPDATES_FOUND`.
- Archived Dell logs are cleaned from the native temporary location after capture.

### Installer/user experience
- Installer shows existing installation status.
- Adds a configuration review/confirmation before installation.
- Allows a configurable restart countdown.
- Adds “Run installed maintenance now.”
- Adds fuller removal workflow with optional local-data purge.
- Bootstrap asks before installing PowerShell.
- Bootstrap validates package syntax/files before opening the installer.
- `-Status` now includes last maintenance health and selected inventory/patch fields.

### Community/repository
- Adds MIT License.
- Adds README, community guide, contribution guide, security policy, release checklist, JSON schema, `.gitignore`, and local syntax/package validator.
- Adds SHA-256 release manifest.
- Community edition remains local-only: no cloud telemetry, remote shell, or remote command channel.

## v0.4.x — Installer/runtime stabilization (2026-11-10)

- Migrated maintenance runtime to stable PowerShell 7.6+.
- Added Safe / Client / Aggressive scheduled profiles.
- Added `Never`, `IfRequired`, and `EveryRun` reboot policies.
- Added cancel/delay restart UX and `-CancelReboot`.
- Added stable PowerShell runtime discovery for MSI/MSIX installs.
- Added ProgramData runtime launcher so MSIX package-version changes do not orphan Scheduled Tasks.
- Added guarded scheduled firmware opt-in.
- Improved scheduled-task configuration logging.
- Fixed case-insensitive firmware confirmation and friendly `4:30` time input.

## v0.3.x — Scheduling/profiles

- Added self-installing Scheduled Task support.
- Added Safe / Client / Aggressive profiles.
- Added status/version reporting.
- Added wake-to-run, battery execution, highest privileges, missed-run recovery, and duplicate-run protection.
- Added explicit scheduled firmware opt-in.

## v0.2.x — Core update engine

- Added Defender, WinGet, Windows Update, Dell Command | Update, reboot detection, JSON logging, and firmware/BitLocker preflight.
- Added Dell progress monitoring and handling for vendor self-update/busy/no-update conditions.
- Changed OEM applications to opt-in and drivers to the default Dell scope.
