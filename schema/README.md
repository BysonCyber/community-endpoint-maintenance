# JSON reporting contract

v0.5.1 introduces `SchemaVersion = "1.0"` for local maintenance summaries.

The schema is intentionally **extensible** (`additionalProperties: true`) while requiring stable core identity/status fields.

## Identity

`DeviceId` is a random GUID generated locally and persisted under ProgramData.

It is not based on:

- motherboard serial;
- Windows product key;
- MAC address;
- TPM identity;
- user identity.

`RunId` is a new random GUID for each run.

## Future dashboard use

A future dashboard can use:

```text
Tenant/Site (future enrollment metadata)
    -> DeviceId
        -> RunId
            -> maintenance summary
```

No cloud submission exists in the Community v0.5.1 release.

## Compatibility

Consumers should:

- require a supported `SchemaVersion`;
- ignore unknown fields;
- avoid assuming every optional OEM/security field is populated;
- distinguish `Warning` from `Error`;
- treat a safely blocked firmware operation as a warning, not a crash.
