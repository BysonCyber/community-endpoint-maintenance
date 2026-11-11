# Contributing

Thanks for helping improve the Byson Cyber Community Endpoint Maintenance Utility.

## Before proposing changes

1. Open an issue describing the behavior, goal, Windows version/build, PowerShell version, profile, and OEM involved.
2. Do **not** post unredacted client logs, credentials, BitLocker recovery keys, serial numbers, or sensitive internal hostnames.
3. Run `.\Test-Maintenance-Syntax.ps1`.
4. Test behavior changes on a non-critical Windows endpoint or disposable lab system.
5. Preserve noninteractive command-line usage as well as the guided installer.
6. Preserve conservative defaults:
   - OEM applications excluded by default;
   - firmware explicit opt-in and fail-closed;
   - no automatic cloud telemetry;
   - no arbitrary remote command channel.
7. New OEM/package-manager integrations should be isolated provider adapters where practical.
8. Note which PowerShell stable version and Windows build you tested.

For maintenance behavior changes, include representative **sanitized** log output when possible.

By contributing code, you agree that it may be distributed under the repository's MIT License.
