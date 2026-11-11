# Roadmap

This roadmap is directional, not a promise of dates or commercial features.

## v0.5.x — Community stabilization

- Broader hardware testing across Dell/HP/Lenovo.
- Improve Dell return-state classification as vendor CLI behavior changes.
- More application-update/reporting coverage without weakening safe defaults.
- Better handling for unusual Windows Update servicing states.
- Continue hardening installer/upgrade/uninstall behavior.

## v0.6 — Reporting and provider maturity

Candidate work:

- richer installed-application inventory;
- clearer “managed / vendor-managed / unmanaged” application coverage;
- HP update provider;
- Lenovo update provider;
- package-manager provider abstraction for WinGet / Chocolatey / Scoop without overlapping ownership;
- patch-ring metadata and configurable deferral policy;
- optional offline HTML health report.

## v0.7+ — Optional read-only dashboard prototype

A future dashboard should begin as **endpoint -> API**, not arbitrary remote control.

Potential model:

```text
Endpoint maintenance
      ↓
Schema v1 JSON
      ↓
Authenticated HTTPS check-in
      ↓
Organizations / sites / devices
      ↓
Read-only health dashboard
```

Possible dashboard metrics:

- last check-in;
- last successful maintenance;
- patch compliance;
- application coverage;
- reboot pending age;
- OEM driver/firmware state;
- Defender signature age;
- BitLocker / Secure Boot / TPM posture;
- script/agent version drift.

## Explicitly out of scope for the early Community agent

Avoid casually turning this project into an RMM/MDM:

- arbitrary remote SYSTEM PowerShell;
- remote shell;
- remote desktop/control;
- credential collection;
- user surveillance;
- file exfiltration;
- remote wipe;
- identity/Conditional Access management.

If constrained remote actions ever exist, they should be designed as a separate authenticated/audited architecture rather than hidden inside the local maintenance script.

## Community vs future hosted product

The Community endpoint can remain useful without a subscription or cloud dependency.

A future optional hosted service could add centralized history, alerting, patch rings, compliance summaries, and multi-tenant reporting while keeping local maintenance functional on its own.


## Distribution / trust

- Authenticode-signed release artifacts when adoption justifies the signing/release infrastructure.
- Automated signing in CI/release workflow.
- Smart App Control / App Control compatibility testing for signed builds.
- Keep unsigned Community Beta limitations explicit until that work is complete.
