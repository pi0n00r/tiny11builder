# Windows 11 26H2 Deployment Profile

Status: candidate profile

Profile ID: `deployment/2026-26h2`

Scope: general-purpose, serviceable Windows 11 x64 installation media. This is
not an accounts-only image. TurboTax Business Incorporated and CRA Corporation
Internet Filing are required compatibility workloads because the 2024 appliance
did not preserve their supported browser shape.

Prepared: 2026-09-29 America/Toronto. A second candidate ISO containing all
four NVMe overrides has been built and its embedded WIM checked. VM acceptance
is pending. This profile must not be called qualified on the strength of static
checks or the isolated driver-binding probe alone.

## Source gate

The builder accepts only:

- architecture `amd64`;
- Windows version `10.0.26300.x`, the Windows 11 26H2 build family;
- the selected image must be named `Windows 11 Pro`;
- official Microsoft installation media with recorded provenance and SHA-256.

Microsoft delivered 26H2 to Release Preview as an enablement package on
2026-08-27 and made Insider ISOs available on 2026-08-31. On 2026-09-29, the
public ISO download page still labeled 25H2, but Microsoft's Media Creation
Tool at <https://go.microsoft.com/fwlink/?linkid=2156295> generated
`Windows.iso` with Windows 11 Pro x64 `10.0.26300.9457` at index 6. The exact
source hash, size, and acquisition route are recorded in
`tiny11-build-20260929-26h2-attempt-receipt.yaml` in the shared ISO store.
Inspect the selected image on every new acquisition because the tool's output
can change. Do not relabel a 25H2 ISO as 26H2 or loosen the `26300` guard.
An Insider source remains a preview candidate and cannot replace a production
LKG without target qualification.

References:

- <https://www.microsoft.com/software-download/windows11>
- <https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewiso>
- <https://learn.microsoft.com/windows/release-health/windows11-release-information>
- <https://blogs.windows.com/windows-insider/2026/08/27/releasing-windows-11-version-26h2-to-the-release-preview-channel/>

Any other build family requires a separate reviewed profile revision. Do not
weaken the gate merely to make older or newer media run.

## 2024 lineage

The recovered May 2024 script used for the 23H2-era appliance is preserved as
evidence at commit `48714d253f77ea8d778949cc25244ab9083c21bd`. Its regular
builder SHA-256 is:

```text
e3cb91f2c81509c4ae650d3afc0fec4ea9151a0e95aa2dae6992306ec4c693ee
```

The 2026 profile carries forward the confirmed user-facing removals that still
map to current packages. It does not carry forward the old unchecked script,
its obsolete package identifiers, or its physical deletion of Edge and
WebView components.

Live read-only inventory of `GB-ACCOUNTS-RD` on 2026-08-30 established:

- Windows 11 Pro 23H2 build `22631`, x64;
- Microsoft Edge absent;
- Microsoft Edge Update absent;
- WebView2 Runtime `100.0.1185.36` present;
- the System32 WebView component present;
- .NET 4 Full release value `533320` present.

This is stronger evidence than a filename or recollection, but it is not an
authorization to change the running appliance.

## Removal policy

The exact provisioned-package prefixes removed by this branch are:

```text
Clipchamp.Clipchamp
Microsoft.BingNews
Microsoft.BingWeather
Microsoft.Copilot
Microsoft.GamingApp
Microsoft.GetHelp
Microsoft.Getstarted
Microsoft.MicrosoftOfficeHub
Microsoft.MicrosoftSolitaireCollection
Microsoft.OutlookForWindows
Microsoft.PowerAutomateDesktop
Microsoft.Todos
Microsoft.WindowsAlarms
Microsoft.WindowsFeedbackHub
Microsoft.WindowsSoundRecorder
Microsoft.Xbox.TCUI
Microsoft.XboxGamingOverlay
Microsoft.XboxIdentityProvider
Microsoft.XboxSpeechToTextOverlay
Microsoft.YourPhone
Microsoft.ZuneMusic
Microsoft.ZuneVideo
MicrosoftCorporationII.MicrosoftFamily
MicrosoftCorporationII.QuickAssist
MSTeams
```

The 25H2 additions to the recovered 2024 intent were Microsoft Copilot, new
Outlook for Windows, current Teams (`MSTeams`), and Xbox Identity Provider.
The 26H2 profile initially retains that reviewed package policy. Capture the
complete 26H2 provisioned-package inventory before removal and compare it with
this list; new or changed identities require a reviewed edit, not a wildcard
or an unrecorded deletion. These names are present in Microsoft's inbox-app
removal surface, but actual 26H2 presence is not yet verified.

OneDrive setup remains removed and OneDrive synchronization remains disabled,
matching the confirmed fleet policy and use of Nextcloud.

Reference:

- <https://learn.microsoft.com/windows/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal>

## Discontinued identifiers

These identifiers from older scripts are deliberately absent from the 2026
policy because the product or package identity has been retired or replaced:

```text
Microsoft.549981C3F5F10
Microsoft.People
Microsoft.Windows.DevHome
Microsoft.WindowsMaps
Microsoft.XboxGameOverlay
MicrosoftTeams
microsoft.windowscommunicationsapps
```

An absent package is recorded in the build transcript; it is not grounds to
restore a stale identifier. New package identities require source inventory and
a reviewed profile change.

## Preserved components

Undiscussed components are preserved by default. The profile specifically
protects:

- Microsoft Edge and its update/servicing registration;
- the Evergreen and System32 WebView2 runtime paths;
- Microsoft Store and Store Purchase App;
- Desktop App Installer and `winget`;
- Windows Terminal, Notepad, Calculator, Paint, Photos, Camera, Snipping Tool,
  and Sticky Notes;
- Windows Security, Defender, Windows Update, WinRE, and the component store;
- Start Experiences, Windows Search/Bing Search, Client Web Experience, and
  Cross Device Experience Host;
- printing, scanning, Remote Desktop, SMB client, Hyper-V/WSL capabilities,
  and optional Windows features unless the source itself omits them;
- .NET Framework 4.x and its servicing path.

Cross Device Experience Host is preserved even though Phone Link is removed.
It is a Windows support component used by multiple device-integration surfaces,
not merely the Phone Link front end.

The protected package list is checked against the removal list during both
static validation and every build. Edge and System32 WebView presence are hard
build gates.

## CRA and TurboTax compatibility

TurboTax Desktop 2025 lists Microsoft Edge as its required Internet browser and
.NET 4.8 as required third-party software. CRA Corporation Internet Filing
requires a TLS 1.2-or-newer browser with cookies enabled. WebView2 alone does
not satisfy Intuit's published Edge requirement.

References:

- <https://turbotax.community.intuit.ca/turbotax-support/en-ca/help-article/download-products/end-support-windows-8-affect-turbotax-experience/L5VzEHDD4_CA_en_CA>
- <https://turbotax.intuit.ca/tax/software/download>
- <https://www.canada.ca/en/revenue-agency/services/e-services/digital-services-businesses/corporation-internet-filing/before-you-start.html>
- <https://www.canada.ca/en/revenue-agency/services/e-services/digital-services-businesses/corporation-internet-filing/your-browser.html>
- <https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution>

Qualification requires:

1. Edge launches and is current after Windows Update.
2. WebView2 Runtime is present, serviced, and current.
3. The .NET 4 Full release value is present.
4. TurboTax Business Incorporated installs, activates, updates, and launches.
5. TurboTax can open its CRA Corporation Internet Filing path in Edge with
   TLS 1.2 or newer and cookies enabled.
6. The first legitimate T2 transmission completes and its CRA confirmation is
   retained outside the public build receipt.

Do not submit a fabricated return merely to turn the last gate green. Until a
real filing succeeds, record `cra_t2_transmission: pending_real_submission`.

## NVMe feature overrides

Legible note `Windows 11 25H2 NVMe driver` (`uaL2ZCyfKh9y`) records the three
feature overrides used on hAIlo:

```text
HKLM\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides
  735209102  REG_DWORD  1
  1853569164 REG_DWORD  1
  156965516  REG_DWORD  1
```

The 26H2 builder now also writes `3244671118 REG_DWORD 1` (feature
`60786016`), proven by the isolated Booklette test below.

An offline SYSTEM hive does not expose `CurrentControlSet` as a live alias. The
builder reads `SYSTEM\Select\Default`, validates that control set, and writes
the values there. It does not assume `ControlSet001`.

These are undocumented Windows-client feature overrides, not storage-driver
injection. **They did not enable the native NVMe path on Booklette's 26H2
build 26300.9457.** On 2026-09-29, all three read back as `1` on that live
machine, and `nvmedisk.sys` existed, but its `Standard NVM Express Controller`
still used Microsoft `stornvme.inf` / service `stornvme` (driver
`10.0.26100.9278`). The first 26H2 candidate ISO's `install.wim` SYSTEM hive
also contained only those three under its selected default `ControlSet001`. This PC,
still on 25H2 build 26200.9457, has the same three flags but its Samsung boot
disk is now `DiskDrive` using `disk.inf`, with an NVMe controller using
`stornvme.inf`. The loss of native binding therefore predates this 26H2 image
on at least one target. Registry presence proves only that the writes succeeded.
The observation is for this hardware and build, not a claim that every 26H2
installation behaves identically.

Microsoft's published Native NVMe opt-in is for **Windows Server 2025** and
uses a different feature ID, `1176759950`; it is not a Windows 11 26H2
qualification for these client IDs. **Native binding is a required target
promotion gate for this deployment.** The first candidate is blocked at this
gate. On 2026-09-29, an isolated native-boot VHDX on Booklette added the fourth
override `3244671118=1` to the three above. Its physical SSSTC disk then
enumerated as class `NvmeDisk`, instance `NVME\NVMEDISK...`, with Microsoft
`nvmedisk.inf` version `10.0.26100.8972`. The VHD itself remained a virtual
`disk.inf` device. The specialize pass captured this result and restarted;
the machine subsequently entered recovery during setup, so a normal completed
installation and reboot are still unqualified. No production OS was changed.

The fourth override maps to feature `60786016`, reported effective by a
firsthand tester on 26200.8116. Our physical-hardware test qualifies native
binding on Booklette 26300.9457, not future servicing or stable full setup.
The second candidate ISO, `tiny11-26h2-pro-en-us-x64-native-nvme4-20260929.iso`,
contains a clean exported one-index Pro WIM. The WIM passed full file-data
verification; the extracted SYSTEM hive contains all four overrides at `1` in
ControlSet001. The mounted ISO's embedded WIM SHA-256 matched the verified
source WIM, and both BIOS and UEFI boot files were present. This validates the
artifact contents, not a completed installer run.
Read back the actual driver on each target after installation. Sources:
https://forums.mydigitallife.net/threads/discussion-windows-11-26x00-native-nvme-driver-discussion.89933/page-11
and
https://techcommunity.microsoft.com/blog/windowsservernewsandbestpractices/announcing-native-nvme-in-windows-server-2025-ushering-in-a-new-era-of-storage-p/4477353

Read the keys back and verify the active
controller in the target test; do not infer a driver change from the values.
After installation and reboot, read back the values and record the active NVMe
controller, provider, driver version, INF, binary, and Device Manager status.

```powershell
$Path = 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides'
Get-ItemProperty -LiteralPath $Path |
    Select-Object '735209102', '1853569164', '156965516', '3244671118'

Get-CimInstance Win32_PnPSignedDriver |
    Where-Object DeviceClass -eq 'SCSIAdapter' |
    Select-Object DeviceName, Manufacturer, DriverVersion, InfName
```

Do not add OEM storage drivers to the universal image unless a clean setup test
proves they are required. Keep target driver exports separate.

## Build evidence

The build transcript is part of the receipt and must include:

- source image name, version, architecture, locale, and image index;
- complete provisioned-package inventory before removal;
- exact package names removed;
- Edge and WebView preservation checks;
- resolved offline default control set;
- all four NVMe registry writes;
- successful DISM save/export and ISO creation.

Add these profile fields to the build receipt:

```yaml
profile:
  id: deployment/2026-26h2
  source_build_family: 26300
  package_inventory_captured: false
  edge_preserved: false
  webview2_preserved: false
  nvme_feature_overrides: false
acceptance:
  windows_update: false
  edge_current: false
  webview2_current: false
  turbotax_incorporated: false
  cra_t2_transmission: pending_real_submission
```

The output remains a candidate until the universal playbook's VM, target,
servicing, recovery, and workload gates pass.

## 26H2-specific acceptance

Microsoft has removed the `bypassnro.cmd` helper and has been changing the
interactive local-account path. The existing answer file requests hidden online
account screens, but that setting and the offline `BypassNRO` registry value
must be tested in a clean 26H2 VM rather than assumed effective. If OOBE fails,
revise the answer file as a new pinned commit and rebuild; do not change the
installer interactively and call it qualified.

Inspect the resulting ISO's selected WIM image, its build, architecture, locale,
edition, EFI marker and embedded answer-file hash. Verify Windows Update,
component-store serviceability, Edge, WebView2, local-account OOBE, and cold
boots in a disposable UEFI VM before any target or workload promotion.
