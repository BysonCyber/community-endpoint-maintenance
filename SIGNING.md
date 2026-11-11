# Code signing

## Current release model

v0.6.2 Community Beta is distributed **unsigned**.

That is a deliberate early-community cost/scope decision. It is not a claim that code signing is unnecessary.

Unsigned releases may be blocked by Smart App Control, App Control for Business, WDAC, enterprise application-control policies, or other trust enforcement.

The project does not recommend weakening those controls to install the utility.

## Future signed-release path

A future signed release should:

1. use a publicly trusted Authenticode-compatible signing identity for **Byson Cyber LLC**;
2. sign every distributed `.ps1` file;
3. timestamp signatures;
4. verify `Get-AuthenticodeSignature` reports `Valid`;
5. generate SHA-256 checksums after signing;
6. publish the signed ZIP and checksum manifest together;
7. test on an application-control-enforced Windows endpoint.

The validator currently uses:

```powershell
$SigningMode = 'UnsignedCommunityBeta'
```

A future signed release can switch to:

```powershell
$SigningMode = 'RequireValidSignature'
```

and missing/invalid signatures become release-blocking validation errors.

## CI / release automation

If adoption justifies signing costs, prefer signing through a controlled release pipeline rather than manually signing arbitrary working-tree files.

Never commit signing credentials or private keys to the repository.

## Internal signing

Organizations with their own application-control/PKI process can review the source and apply internal signatures according to their policy. Those signatures are outside the Byson community release trust model.
