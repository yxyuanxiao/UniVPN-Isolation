# Local release assets

This directory holds machine-local release inputs generated or verified during packaging.

Expected files:

```text
univpn-isolation-arm64.oci.tar
SHA256SUMS
```

They are intentionally ignored by Git. `scripts/build-distribution.command` exports the OCI image from the verified local tag when the archive is absent, then records its SHA-256. Do not place configuration volumes, credentials, cookies, certificates, proxy snapshots, or logs here.
