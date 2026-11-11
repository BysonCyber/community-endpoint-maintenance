# Security policy

This repository contains an elevated Windows maintenance utility. Treat changes to update execution, firmware handling, scheduled tasks, reboot behavior, runtime selection, and local file permissions as security-sensitive.

## Reporting a vulnerability

Please avoid publicly sharing proof-of-concept exploit details, credentials, BitLocker recovery keys, customer data, or sensitive endpoint logs.

Use GitHub private vulnerability reporting if enabled for this repository, or contact the project maintainer privately through the publicly listed Byson Cyber contact channel.

## Safety guidelines

- Use this tool only on endpoints you own, manage, or are authorized to administer.
- Review the source before deployment in sensitive environments.
- Test Community Beta releases on non-critical systems before broad rollout.
- Firmware maintenance is explicit opt-in and should only be used with external recovery material and a tested recovery process.
- Never commit credentials, API keys, recovery keys, customer logs, or secrets.
- Sanitize hostnames, usernames, paths, customer names, and generated reports before opening a public issue.
- Do not treat `OverallStatus = Healthy` as proof that an endpoint is vulnerability-free or compliant.
- Community v0.6.2 has no Byson cloud telemetry or remote command channel.

## Unsigned Community Beta

The current Community Beta is unsigned and can be blocked by Smart App Control, App Control for Business, WDAC, or other application-control policy.

Do not instruct users to disable those controls as an installation workaround.

Future signed-release guidance is documented in [`SIGNING.md`](SIGNING.md).

## Supported versions

Security fixes are expected to land on the latest Community Beta/release line. Older development ZIPs may not receive backports.
