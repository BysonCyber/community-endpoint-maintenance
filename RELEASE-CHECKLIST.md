# Release checklist

Use this before publishing a GitHub release.

## Source/package

- [ ] Update `$ScriptVersion` and changelog.
- [ ] Run `.\Test-Maintenance-Syntax.ps1`.
- [ ] Confirm README/profile tables match actual code.
- [ ] Confirm MIT `LICENSE` is present.
- [ ] Confirm no credentials, client names, recovery keys, local absolute user paths, or customer logs are in the repo.
- [ ] Rebuild `SHA256SUMS.txt`.

## Fresh-install test

- [ ] Extract ZIP to a new folder.
- [ ] Right-click `START HERE - Install Byson Maintenance.cmd` and choose **Run as administrator**.
- [ ] Confirm the recommended elevated launcher opens the bootstrap/installer.
- [ ] Test `START HERE - Install Byson Maintenance.ps1` from PowerShell/Windows Terminal as the fallback path.
- [ ] Confirm the unsigned Community Beta warning is visible/documented.
- [ ] On an application-control-enforced test endpoint, document whether normal double-click is blocked and whether **Run as administrator** works; do **not** disable the control to force the test.
- [ ] Test on a machine with stable PowerShell already installed.
- [ ] Test bootstrap behavior when stable PowerShell is absent, if practical.
- [ ] Verify Preview/RC PowerShell is not selected for scheduled maintenance when stable and Preview coexist.
- [ ] Verify UAC/self-elevation.

## Profiles

- [ ] Safe profile install + scheduled run.
- [ ] Client profile install + scheduled run.
- [ ] Aggressive profile install + scheduled run.
- [ ] Confirm OEM applications remain excluded by default.
- [ ] Confirm low-disk guard converts installs to scans.
- [ ] Confirm an actual ERROR returns a non-zero Task Scheduler result.
- [ ] Confirm global run lock blocks overlapping runs.

## Reboot UX

- [ ] `IfRequired` behavior.
- [ ] `EveryRun` behavior.
- [ ] Restart countdown appears when an interactive user is available.
- [ ] Restart now.
- [ ] Delay one hour.
- [ ] Cancel restart.
- [ ] `shutdown /a` fallback.

## Firmware

- [ ] Audit firmware on AC.
- [ ] Audit/install request on battery blocks safely.
- [ ] Missing recovery-key acknowledgement blocks safely.
- [ ] Pre-existing servicing reboot blocks firmware.
- [ ] Only perform a real BIOS/firmware install on a non-critical test endpoint with external recovery material.

## OEM

- [ ] Dell with updates available.
- [ ] Dell fully current/no updates.
- [ ] Dell Command | Update self-update/busy condition if encountered.
- [ ] At least one non-Dell endpoint for graceful unsupported-adapter behavior.

## Reporting

- [ ] Log generated.
- [ ] JSON generated and parses.
- [ ] `SchemaVersion` = `1.0`.
- [ ] Stable `DeviceId` persists across runs.
- [ ] Unique `RunId` changes per run.
- [ ] `-Status` shows the latest maintenance result accurately.
- [ ] Log retention cleanup behaves as expected.

## Signing / trust

- [ ] Confirm validator signing mode matches the release (`UnsignedCommunityBeta` for this beta).
- [ ] Confirm `Get-AuthenticodeSignature` status is reported by the validator.
- [ ] If/when publishing a signed release, switch to `RequireValidSignature` and regenerate checksums after signing.

## Release

- [ ] Tag version.
- [ ] Attach ZIP.
- [ ] Attach/verify SHA-256 checksums.
- [ ] Mark Community Beta clearly until broader hardware testing is complete.
