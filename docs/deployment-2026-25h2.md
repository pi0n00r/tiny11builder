# Windows 11 25H2 Deployment Profile

Status: candidate profile

Profile ID: `deployment/2026-25h2`

Scope: general-purpose, serviceable Windows 11 x64 installation media. This is
not an accounts-only image. TurboTax Business Incorporated and CRA Corporation
Internet Filing are required compatibility workloads because the 2024 appliance
did not preserve their supported browser shape.

Captured: 2026-08-30 America/Toronto

## Source gate

The builder accepts only:

- architecture `amd64`;
- Windows version `10.0.26200.x`, the Windows 11 25H2 build family;
- official Microsoft installation media with recorded provenance and SHA-256.

At profile capture, Microsoft's General Availability Channel release was
Windows 11 25H2 build `26200.9168`. Microsoft ISO media can lag the latest
cumulative update, so the builder accepts the `26200` family and target
qualification must update the installed system before promotion.

References:

- <https://www.microsoft.com/software-download/windows11>
- <https://learn.microsoft.com/windows/release-health/windows11-release-information>
- <https://learn.microsoft.com/windows/whats-new/whats-new-windows-11-version-25h2>

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

The 25H2 additions to the recovered 2024 intent are Microsoft Copilot, new
Outlook for Windows, current Teams (`MSTeams`), and Xbox Identity Provider.
These names are present in Microsoft's current inbox-app removal surface.

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

An offline SYSTEM hive does not expose `CurrentControlSet` as a live alias. The
builder reads `SYSTEM\Select\Default`, validates that control set, and writes
the values there. It does not assume `ControlSet001`.

These values select a Windows feature path. They are not storage-driver
injection and do not make an otherwise invisible setup controller visible.
After installation and reboot, read back the values and record the active NVMe
controller, provider, driver version, INF, binary, and Device Manager status.

```powershell
$Path = 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides'
Get-ItemProperty -LiteralPath $Path |
    Select-Object '735209102', '1853569164', '156965516'

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
- all three NVMe registry writes;
- successful DISM save/export and ISO creation.

Add these profile fields to the build receipt:

```yaml
profile:
  id: deployment/2026-25h2
  source_build_family: 26200
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
