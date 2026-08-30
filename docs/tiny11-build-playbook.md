# Tiny11 Universal Build and Recovery Playbook

Status: controlled procedure

Purpose: produce a reproducible, serviceable Windows 11 installation image for
an appliance, VM, or workstation without trusting filenames, mutable upstream
branches, or undocumented operator memory.

This playbook treats every image as a candidate until its provenance, contents,
installation behavior, serviceability, and target-hardware behavior have all
been proven. It contains no credentials, product keys, or recovery secrets.

## 1. Non-negotiable rules

1. Use `tiny11maker.ps1`, the regular serviceable builder, for every durable
   system. Never use `tiny11Coremaker.ps1` for production.
2. Download Windows only from Microsoft. Record the source URL, retrieval time,
   published hash when available, and locally computed SHA-256.
3. Use `https://github.com/pi0n00r/tiny11builder`, branch
   `deployment/2026-25h2`, pinned to an explicit commit. Never build from a
   mutable branch tip or an unversioned ZIP.
4. Determine release, edition, locale, and architecture from mounted-media
   contents. A filename is not evidence.
5. Keep the pristine source ISO, exact builder commit or commit archive, answer
   file, build transcript, receipt, output ISO, and checksums. A bare ISO is not
   a reproducible build.
6. Build on local NTFS scratch space. The NFS share is an artifact repository,
   not a scratch disk or live build directory.
7. Do not overwrite an existing artifact. Every build gets a new build ID and
   directory.
8. Do not put product keys, passwords, BitLocker recovery material, API keys,
   or other secrets in the ISO, answer file, transcript, receipt, or share.
9. Do not wipe the target until a VM installation passes and both the Macrium
   recovery image and rescue media have been tested.
10. Read and inventory every destination before writing or renaming it.
11. Do not interpret a public GitHub fork as permission to relicense inherited
    code. Upstream currently publishes no software license; this fork therefore
    carries no AGPL notice.

## 2. Storage roles

- Artifact repository: `/volume1/Shared/ISOs` on `home`.
- Build station: a disposable or recoverable Windows system with local NTFS
  scratch space, Windows PowerShell 5.1, administrator access, and preferably
  at least 80 GiB free. The hardened script enforces a 40 GiB minimum.
- Target: the system that will eventually receive the qualified image.

Copy inputs from the repository to a new local build directory. Copy sealed
outputs back only after static validation succeeds.

Recommended local layout:

```text
C:\Builds\tiny11\<build-id>\
  source\
  builder-pristine\
  builder-run\
  drivers\
  output\
  evidence\
```

Recommended immutable names:

```text
windows11-<release>-<edition-or-multi>-<locale>-<arch>-microsoft.iso
tiny11builder-pi0n00r-<short-commit>.zip
tiny11-<release>-<edition>-<locale>-<arch>-builder-<short-commit>-<yyyymmdd>.iso
tiny11-<build-id>-receipt.yaml
tiny11-<build-id>-SHA256SUMS
```

Use `x64` or `arm64`, never the ambiguous suffix `arm`. Promotion status belongs
in the receipt, not in a mutable filename.

## 3. Stage A: recover the current machine

Complete this before changing the target:

1. Create a full Macrium image containing every required boot and OS partition.
2. Boot the Macrium rescue environment and prove that it can see the backup,
   system disk, keyboard, display, and network or attached backup storage.
3. Export the current signed driver store to a separate directory:

```powershell
pnputil /export-driver * D:\DriverExport
```

4. Record BIOS settings that matter to the target, including UMA allocation,
   Secure Boot, storage mode, virtualization, and boot order.
5. Export workload configuration using that workload's own documented process.
6. Store BitLocker and account recovery material in the authorized vault, not
   beside the ISO.

The driver bundle is evidence and a recovery aid. Keep it separate from the
universal ISO. Inject or load only setup-critical storage drivers when a clean
VM or hardware test proves that this is necessary.

## 4. Stage B: acquire and prove the Microsoft source

1. Download the desired current Windows 11 ISO from Microsoft's official
   software-download surface.
2. Compute its hash immediately:

```powershell
Get-FileHash .\windows11-source.iso -Algorithm SHA256
```

3. Compare with Microsoft's published hash when available. A mismatch rejects
   the source.
4. Mount the ISO and derive its facts from content:

```powershell
$SourceIso = (Resolve-Path .\windows11-source.iso).Path
$DiskImage = Mount-DiskImage -ImagePath $SourceIso -PassThru
$Volume = $DiskImage | Get-Volume
$IsoDrive = "$($Volume.DriveLetter):"

$HasX64 = Test-Path "$IsoDrive\efi\boot\bootx64.efi"
$HasArm64 = Test-Path "$IsoDrive\efi\boot\bootaa64.efi"
if ([int]$HasX64 + [int]$HasArm64 -ne 1) {
    throw "Media architecture is absent or ambiguous"
}

$InstallImage = @(
    "$IsoDrive\sources\install.wim",
    "$IsoDrive\sources\install.esd"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $InstallImage) { throw "No install.wim or install.esd found" }

Get-WindowsImage -ImagePath $InstallImage |
    Select-Object ImageIndex, ImageName, Architecture, Version
```

5. Record the ISO volume label, EFI marker, image index, image name, reported
   architecture, build/version, and locale in the receipt.
6. For this deployment profile, require x64 Windows 11 25H2 version
   `10.0.26200.x`. Reject another build family even if its filename says 25H2.
7. Dismount the source after inspection:

```powershell
Dismount-DiskImage -ImagePath $SourceIso
```

Reject media when its filename and contents disagree. Rename only after the
content-derived facts are recorded.

## 5. Stage C: acquire and pin tiny11builder

1. Use the fleet fork only:
   `https://github.com/pi0n00r/tiny11builder`.
2. Fetch branch `deployment/2026-25h2`, resolve its commit, and check out
   that detached commit. Record the branch, commit, archive URL when used, and
   archive SHA-256. A branch name by itself is not a pin.
3. Verify that the pinned commit descends from hardened baseline commit
   `b87486a608805fd8e58e0c734b0576d0ea429c4d`.
4. Keep one pristine checkout or commit archive and make a separate disposable
   run copy.
5. Read `docs/deployment-2026-25h2.md`. Hash at least `tiny11maker.ps1`,
   `autounattend.xml`, the profile document, the static test, and the commit
   archive when an archive is used.
6. Run the repository static checks before building:

```powershell
.\tests\Static.Tests.ps1
```

7. Parse the PowerShell script independently before running it:

```powershell
$Tokens = $null
$Errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\tiny11maker.ps1),
    [ref]$Tokens,
    [ref]$Errors
) | Out-Null
if ($Errors.Count) {
    $Errors | Format-List
    throw "tiny11maker.ps1 failed PowerShell syntax validation"
}
```

If PSScriptAnalyzer is already part of the controlled build station, require
version 1.25.0 and record its findings. Do not install an unpinned analyzer
during a build.

Do not edit the pinned deployment commit in place. If a target-specific change
is unavoidable, commit it to a new deployment branch revision, review it, and
generate a distinct output and receipt. Never silently replace the pristine
script.

## 6. Stage D: answer-file architecture gate

Parse `autounattend.xml` and enumerate every `processorArchitecture` value:

```powershell
[xml]$Answer = Get-Content .\autounattend.xml -Raw
$Architectures = $Answer.SelectNodes('//*[@processorArchitecture]') |
    ForEach-Object { $_.GetAttribute('processorArchitecture') } |
    Sort-Object -Unique
$Architectures
```

For x64 media, all values must be `amd64`. For ARM64 media, all values must be
`arm64`. Any mismatch is a hard stop.

As of 2026-08-30, both the historical May 2024 archive and upstream release
`06-09-25` carried the same x64-only answer file with SHA-256:

```text
ed9837ab4a19c812d28e20f5278ca5bb25815a6a01d1caddbce157be5d519dba
```

That inherited file placed `ConfigureChatAutoInstall` outside any `settings`
configuration pass. The fleet fork corrected the structure while preserving the
setting in `oobeSystem`. Hardened baseline answer-file SHA-256:

```text
4d62f45eb45eaa7d88a1a68037d56f185ec889bbe552ce23c9f27c5c0deba19a
```

The deployment profile is qualified only for x64. An ARM64 build requires a
separately reviewed, architecture-correct answer file and its own deployment
branch revision and receipt. Do not label an image ARM64 merely because the
source or output filename says so.

Before use, verify that every `component` is contained by a `settings` pass and
that the answer file contains no populated product key or secret material.

## 7. Stage E: build

1. Mount the proven Microsoft source ISO.
2. Open Windows PowerShell 5.1 as Administrator.
3. Set execution policy for this process only:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

4. Use different drive letters for mounted source and scratch. Scratch must be
   a fixed local NTFS volume. The script enforces 40 GiB free; 80 GiB is the
   operational recommendation.
5. Run the regular builder with an explicit image index and output path:

```powershell
.\tiny11maker.ps1 `
    -ISO E `
    -SCRATCH D `
    -ImageIndex 6 `
    -OutputPath 'C:\Builds\tiny11\output\tiny11-candidate.iso'
```

6. Record the selected image index and SKU. The regular deployment builder has
   no .NET 3.5 prompt.
7. Let the pinned builder finish. Do not interrupt it because a stage appears to
   pause, and do not run a second builder against the same scratch directory.
8. Preserve the generated transcript before cleaning the run directory.

Use a controlled Windows ADK installation for `oscdimg.exe` and record the ADK
version. A reviewed Microsoft-signed copy beside the script is the fallback.
The hardened builder downloads nothing, does not delete `autounattend.xml` or
`oscdimg.exe`, refuses to overwrite output or stale scratch, and retains failed
scratch evidence for diagnosis.

## 8. Stage F: seal and statically validate the output

1. Rename the output ISO using content-derived facts and the canonical template.
2. Compute output size and SHA-256.
3. Mount the output ISO and repeat the architecture and `Get-WindowsImage`
   inspection from Stage B.
4. Verify all of the following:
   - exactly one expected EFI architecture marker exists;
   - `sources\boot.wim` and `sources\install.wim` are present and readable;
   - the selected edition, image index, build, locale, and architecture match
     the receipt;
   - the embedded `autounattend.xml` hash matches the reviewed answer file;
   - no product key or secret is embedded;
   - the PowerShell transcript ends in successful completion;
   - no mount or scratch directory remains active.
5. Write the receipt and checksum file before copying the candidate back to the
   artifact repository.

Static validation proves internal consistency. It does not qualify an installer.

## 9. Stage G: VM qualification

Install the candidate in a disposable UEFI VM of the matching architecture.
The VM pass requires:

1. Boot from ISO and complete setup without modifying the image.
2. OOBE permits the intended local-account path.
3. The installed edition, build, locale, and architecture match the receipt.
4. Device Manager has no unexplained unknown or failed devices.
5. Windows servicing remains functional: updates can scan/install and optional
   Windows capabilities can still be enumerated.
6. IPv4 and IPv6 both work.
7. At least two cold boots and one shutdown/start cycle complete normally.
8. Event Viewer shows no unresolved boot-critical, storage-critical, or
   servicing-critical failure introduced by the image.
9. Edge, Edge Update, and WebView2 remain installed and serviced.
10. Microsoft Store, Desktop App Installer, Windows Terminal, Windows Security,
    and the other protected packages remain present.
11. The three NVMe feature overrides read back as `REG_DWORD 1` from the live
    `CurrentControlSet`.

Any failure creates a rejected build receipt. Do not repair the only copy in
place; fix the input or documented profile and generate a new build ID.

## 10. Stage H: target qualification and promotion

Only after the VM pass:

1. Reconfirm the Macrium image and bootable rescue path.
2. Install on the target without adding undocumented startup tasks, wrappers,
   runtimes, or helper services.
3. Install only signed OEM or exported LKG drivers. Use:

```powershell
pnputil /add-driver D:\DriverExport\*.inf /subdirs /install
```

4. Apply Windows updates, then capture the exact driver and firmware state.
5. Read back the active NVMe controller, provider, driver version, INF, binary,
   Device Manager status, and all three feature overrides. The registry values
   are not substitutes for a healthy controller readback.
6. Run target-specific acceptance separately. The base-image pass is not a
   workload pass.
7. For the CRA workload, verify current Edge and WebView2, .NET 4.x, TurboTax
   Business Incorporated install/activation/update, and the CRA filing launch
   path. Record the first legitimate T2 transmission as workload evidence; do
   not submit a fabricated return for testing.
8. Prove normal boot, reboot, shutdown/start, networking, power management,
   remote administration, backup, and recovery.
9. Promote the receipt from `candidate` to `qualified`, then to `lkg` only after
   the agreed soak period and workload acceptance are green.

## 11. Receipt schema

Every build must carry a receipt with at least this shape:

```yaml
schema: tiny11-build-receipt/v1
build_id: null
status: candidate
created_at: null
operator: null
source:
  filename: null
  official_url: null
  downloaded_at: null
  sha256: null
  volume_label: null
  windows_release: null
  windows_build: null
  edition: null
  image_index: null
  locale: null
  architecture: null
  efi_marker: null
builder:
  repository: https://github.com/pi0n00r/tiny11builder
  branch: deployment/2026-25h2
  commit: null
  hardened_baseline: b87486a608805fd8e58e0c734b0576d0ea429c4d
  upstream_baseline: 00e7d8a151a39ccffccab4a267bb81fb3756a01d
  archive_sha256: null
  tiny11maker_sha256: null
  autounattend_sha256: null
  static_tests_sha256: null
  powershell_version: null
  psscriptanalyzer_version: 1.25.0
  adk_version: null
profile:
  id: deployment/2026-25h2
  script: tiny11maker.ps1
  serviceable: true
  architecture: amd64
  source_build_family: 26200
  scratch_is_local: true
  image_index_explicit: true
  package_inventory_captured: false
  edge_preserved: false
  webview2_preserved: false
  nvme_feature_overrides: false
  custom_commit: null
drivers:
  bundle_sha256: null
  setup_critical_injection: false
output:
  filename: null
  size_bytes: null
  sha256: null
evidence:
  transcript_sha256: null
  static_validation: false
  vm_install: false
  target_install: false
  cold_boots: 0
  workload_acceptance: false
  turbotax_incorporated: false
  cra_t2_transmission: pending_real_submission
notes: null
```

## 12. Retention and cleanup

Retain for each LKG:

- Microsoft source ISO and provenance evidence;
- pinned builder archive and commit;
- reviewed answer file;
- any reviewed patch;
- driver bundle manifest;
- build transcript;
- output ISO;
- receipt and checksums;
- VM and target acceptance evidence;
- rollback instructions.

Delete local scratch and disposable run copies after evidence is sealed. Do not
retain contradictory handoffs, stale profiles, or undocumented modified scripts.
Do not delete the previous qualified LKG until the replacement has passed its
target soak and the recovery image has been verified.

## 13. Deployment profile lineage

Branch `deployment/2026-25h2` carries forward only the recoverable intent of the
May 2024 template:

- regular, serviceable tiny11 rather than tiny11 Core;
- x64 (`amd64`) media and answer-file components;
- compact OS deployment;
- local-account OOBE availability;
- no embedded product key, credentials, hostnames, or network literals;
- no driver injection unless a setup-critical need is proven;
- edition and image index selected explicitly from the current Microsoft source.

The branch is general-purpose rather than accounts-specific. Its exact 25H2
package policy, preserved components, discontinued identifiers, CRA/TurboTax
gate, and NVMe settings are authoritative in
`docs/deployment-2026-25h2.md`.

Evidence baseline:

```text
Upstream template commit: 48714d253f77ea8d778949cc25244ab9083c21bd
Archived ZIP SHA-256: 3e9b9a6f9b40caedd1e87b085ba11e6e4d9447e4c5e69a99a3bc344736eac91e
Archived tiny11maker.ps1 SHA-256: e3cb91f2c81509c4ae650d3afc0fec4ea9151a0e95aa2dae6992306ec4c693ee
Archived autounattend.xml SHA-256: ed9837ab4a19c812d28e20f5278ca5bb25815a6a01d1caddbce157be5d519dba
```

The deployment branch does not carry forward the old script, physical Edge or
WebView deletion, stale package identifiers, unchecked native commands, runtime
downloads, self-elevation, persistent execution-policy changes, destructive
failure cleanup, malformed answer-file component placement, obsolete source
media, or historical output ISOs.

## 14. Current historical inventory

The following files in `/volume1/Shared/ISOs` are historical evidence, not
approved installation sources:

| File | Size (bytes) | Evidence-derived identity | Status |
|---|---:|---|---|
| `tiny11-24H2-en-gb-x64.iso` | 4,264,777,728 | 24H2-era en-GB x64 | deprecated |
| `tiny11-24H2-edge-en-gb-x64.iso` | 4,267,255,808 | 24H2-era en-GB x64; `edge` delta not recoverable | deprecated |
| `tiny11-24H2-home-en-gb-x64.iso` | 4,244,983,808 | 24H2-era Home en-GB x64 | deprecated |
| `tiny11builder-2024-05-21.zip` | 20,442 | May 2024 builder snapshot | deprecated |
| `Windows11_24H2_Home_en-gb_x64.iso` | 4,742,053,888 | x64 ESD media; formerly mislabeled ARM64 | unqualified source |

Historical builder archive SHA-256:

```text
3e9b9a6f9b40caedd1e87b085ba11e6e4d9447e4c5e69a99a3bc344736eac91e
```

Historical regular builder SHA-256:

```text
e3cb91f2c81509c4ae650d3afc0fec4ea9151a0e95aa2dae6992306ec4c693ee
```

All three historical outputs contain `efi/boot/bootx64.efi`, share the same
x64-only unattended file, and carry the same core setup-binary hashes. The
historical `tiny11arm.iso` name was therefore false. The adjacent source formerly
named `Windows11_Home_en-gb_arm64.iso` is also x64 and reports a 557,056-byte
tail after the UDF archive when inspected with 7-Zip 16.02.

The May 2024 builder predates tiny11builder's official 24H2-support release of
2024-11-17, while these outputs were created in October 2024. Their exact source
and interactive build choices are not durably recorded. They must not be
promoted. The deployment branch uses this archive only as an evidence baseline
for the 2024 serviceable x64 intent; it does not reuse the obsolete script or
any historical output ISO.

## 15. Upstream and fork reference at capture

This is reference evidence, not a permanent instruction to use an old release:

```text
Captured: 2026-08-30 America/Toronto
Latest official release tag observed: 06-09-25
Release commit: 977c06ae1887e6f515278b4135ba99a8b4368c1a
Release archive SHA-256: 4ec46733106f89c613a932e92c1f74fc5f69de9d99d785ab269c07c7d1ff8bec
Release tiny11maker.ps1 SHA-256: 7a66ae5c45346adfd7b7c9a1bb2e72923745c7206b4750ab7ca3d979eb230068
Release autounattend.xml SHA-256: ed9837ab4a19c812d28e20f5278ca5bb25815a6a01d1caddbce157be5d519dba
Latest upstream main commit observed: 00e7d8a151a39ccffccab4a267bb81fb3756a01d
Upstream main archive SHA-256: 76f4afc9ca9a0f6da2de200ceb8685154d73c8a127e5db820133ddaee04a560f
Upstream main tiny11maker.ps1 SHA-256: 7a7baffa75742d9ae9512936d72887931c8bc2a91ac16ccd451a8869752b6f5e
Fleet hardened baseline commit: b87486a608805fd8e58e0c734b0576d0ea429c4d
Fleet hardened tiny11maker.ps1 SHA-256: 5b21023714ecc485f51cd375df62652d026d614f89ecb99009bde45458b6c3ff
Fleet hardened autounattend.xml SHA-256: 4d62f45eb45eaa7d88a1a68037d56f185ec889bbe552ce23c9f27c5c0deba19a
```

Refresh upstream only when intentionally evaluating a rebase. A later upstream
release or main commit replaces no fleet input until its source, scripts, answer
file, behavior, and license status have been reviewed and merged as an explicit
fleet commit.

## 16. Explicitly prohibited shortcuts

- Do not trust `arm`, `x64`, edition, language, or release text in a filename.
- Do not use tiny11 Core for a durable appliance.
- Do not run from upstream GitHub `main`, an unreviewed release, or an unpinned
  deployment branch tip, and do not let the build fetch mutable dependencies.
- Do not rebuild from the 2024 archive or install any historical output ISO.
- Do not set a machine-wide execution-policy exception.
- Do not use the NFS repository as scratch space.
- Do not overwrite an ISO, script, answer file, manifest, or receipt.
- Do not perform an unrecorded manual edit and call the result reproducible.
- Do not inject every driver merely because a driver export exists.
- Do not remove Edge, Edge Update, WebView2, or their servicing registrations.
- Do not translate a live `CurrentControlSet` registry path into a hard-coded
  offline `ControlSet001`; resolve `SYSTEM\Select\Default`.
- Do not treat a bootable ISO, completed setup, or one successful reboot as LKG.
- Do not wipe the target before recovery and VM gates pass.
- Do not retain stale instructions that contradict the final qualified receipt.
- Do not apply AGPL-3.0 or another license to inherited code without an upstream
  compatible license or explicit permission from the copyright holder.
