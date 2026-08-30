# tiny11builder
*Scripts to build a trimmed-down Windows 11 image - now in **PowerShell**!*

> [!IMPORTANT]
> This fork hardens the regular builder for reproducible use. It requires
> explicit source and scratch volumes, a reviewed local answer file, and a
> Microsoft-signed `oscdimg.exe`. Native command failures terminate the build,
> failed-build evidence is retained, and no mutable build input is downloaded
> at runtime. `tiny11Coremaker.ps1` remains upstream code and is not covered by
> these reliability changes.

## Fleet deployment branch

Branch `deployment/2024-template` is the controlled x64 deployment lane. It
preserves the serviceable intent of the archived May 2024 template while using
the hardened builder and corrected answer file. It does not reuse the old
script or any historical ISO. Follow the
[Tiny11 Universal Build and Recovery Playbook](docs/tiny11-build-playbook.md)
and pin an exact deployment commit for every build.

## Introduction :
Tiny11 builder, now completely overhauled. <br> After more than a year (for which I am so sorry) of no updates, tiny11 builder is now a much more complete and flexible solution - one script fits all. Also, it is a steppingstone for an even more fleshed-out solution.

You can use it on Windows 11 releases and languages supported by the source media. The included `autounattend.xml` is for `amd64`; an ARM64 build requires a separately reviewed answer file whose architecture declarations are all `arm64`.
This is made possible thanks to the much-improved scripting capabilities of PowerShell, compared to the older Batch release.

This is a script created to automate the build of a streamlined Windows 11 image, similar to tiny10.
The script has also been updated to use DISM's recovery compression, resulting in a much smaller final ISO size, and no utilities from external sources. The only other executable included is **oscdimg.exe**, which is provided in the Windows ADK and it is used to create bootable ISO images. 
Also included is an unattended answer file, which is used to bypass the Microsoft Account on OOBE and to deploy the image with the `/compact` flag.
The source is publicly available for inspection. See [License status](#license-status) before redistributing or modifying inherited code.

Also, for the very first time, **introducing tiny11 core builder**! A more powerful script, designed for a quick and dirty development testbed. Just the bare minimum, none of the fluff. 
This script generates a significantly reduced Windows 11 image. However, **it's not suitable for regular use due to its lack of serviceability - you can't add languages, updates, or features post-creation**. tiny11 Core is not a full Windows 11 substitute but a rapid testing or development tool, potentially useful for VM environments.

---

## ⚠️ Script versions:
- **tiny11maker.ps1** : The regular script, which removes a lot of bloat but keeps the system serviceable. You can add languages, updates, and features post-creation. This is the recommended script for regular use.
- ⚠️ **tiny11coremaker.ps1** : The core script, which removes even more bloat but also removes the ability to service the image. You cannot add languages, updates, or features post-creation. This is recommended for quick testing or development use.

## Instructions:
1. Download Windows 11 from the [Microsoft website](https://www.microsoft.com/software-download/windows11) or [Rufus](https://github.com/pbatard/rufus), then record and verify its provenance.
2. Install the Windows ADK Deployment Tools, or place a reviewed Microsoft-signed `oscdimg.exe` beside the script.
3. Review the local `autounattend.xml`. Do not add a product key; the builder rejects a populated key.
4. Mount the source ISO using Windows Explorer.
5. Prepare a different fixed local volume with at least 40 GiB free for scratch. The builder rejects a source and scratch drive using the same letter.
6. Open **Windows PowerShell 5.1** as Administrator.
7. If the current policy blocks the script, change it for this process only:
```powershell
Set-ExecutionPolicy Bypass -Scope Process
```
This leaves the persistent execution policy unchanged.

8. Start the regular builder with explicit source and scratch drive letters:
```powershell
& 'C:\path\to\tiny11builder\tiny11maker.ps1' -ISO E -SCRATCH D -ImageIndex 6 -OutputPath 'C:\Builds\tiny11.iso'
```
Omit `-ImageIndex` only when an interactive image selection is intended. The output path must not already exist.

9. Retain the transcript written beside the script and verify the resulting ISO before deployment. On failure, reconcile the retained `tiny11` and `scratchdir` directories on the scratch volume before retrying.

Run `Get-Help .\tiny11maker.ps1 -Full` for parameter details.

---

## What is removed:
<table>
  <tbody>
    <tr>
      <th>Tiny11maker</th>
      <th>Tiny11coremaker</th>
    </tr>
    <tr>
      <td>
        <ul>
          <li>Clipchamp</li>
          <li>News</li>
          <li>Weather</li>
          <li>Xbox</li>
          <li>GetHelp</li>
          <li>GetStarted</li>
          <li>Office Hub</li>
          <li>Solitaire</li>
          <li>PeopleApp</li>
          <li>PowerAutomate</li>
          <li>ToDo</li>
          <li>Alarms</li>
          <li>Mail and Calendar</li>
          <li>Feedback Hub</li>
          <li>Maps</li>
          <li>Sound Recorder</li>
          <li>Your Phone</li>
          <li>Media Player</li>
          <li>QuickAssist</li>
          <li>Internet Explorer</li>
          <li>Tablet PC Math</li>
          <li>Edge</li>
          <li>OneDrive</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>all from regular tiny +</li>
          <li>Windows Component Store (WinSxS)</li>
          <li>Windows Defender (only disabled, can be enabled back if needed)</li>
          <li>Windows Update (wouldn't work without WinSxS, enabling it would put the system in a state of failure)</li>
          <li>WinRE</li>
        </ul>
      </td>
    </tr>
  </tbody>
</table>

Keep in mind that **you cannot add back features in tiny11 core**! <br>
The Core builder asks whether to enable .NET Framework 3.5 because it cannot be added after image creation.

---

## Known issues:
- Although Edge is removed, there are some remnants in the Settings, but the app in itself is deleted. 
- You might have to update Winget before being able to install any apps, using Microsoft Store.
- Outlook and Dev Home might reappear after some time. This is an ongoing battle, though the latest script update tries to prevent this more aggressively.

## Build safety

- Use only official Windows source media with recorded provenance.
- Never build from a network share or use a network share as scratch.
- Do not edit or replace source, answer-file, or ADK inputs during a build.
- Do not reuse a failed scratch tree. Preserve it for diagnosis, then remove it deliberately before a clean retry.
- Treat ISO creation as the start of qualification, not proof of a deployable image. Boot and install it in a disposable VM, verify servicing and Windows Update, then capture hashes and build evidence.

## License status

The upstream repository currently provides no software license. This fork does not relicense inherited code and does not add an AGPL notice. Default copyright rules continue to apply unless the upstream copyright holder publishes a compatible license or grants explicit permission.

---

## Features to be implemented:
- ~~disabling telemetry~~ (Implemented in the 04-29-24 release!)
- ~~more ad suppression~~ (Partially implemented in the 09-06-25 release!)
- improved language and arch detection
- more flexibility in what to keep and what to delete
- maybe a GUI???

And that's pretty much it for now!
## ❤️ Support the Project

If this project has helped you, please consider showing your support! A small donation helps me dedicate more time to projects like this.
Thank you!

**[Patreon](http://patreon.com/ntdev) | [PayPal](http://paypal.me/ntdev2) | [Ko-fi](http://ko-fi.com/ntdev)**
Thanks for trying it and let me know how you like it!
