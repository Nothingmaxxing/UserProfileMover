[Русский](https://github.com/Nothingmaxxing/UserProfileMover) | **English**

<h1 align="center">UserProfileMover</h1>

<p align="center">Move a domain user's data to a new PC with one button</p>

<p align="center">
  <a href="https://github.com/Nothingmaxxing/UserProfileMover/releases/latest"><img src="https://img.shields.io/github/v/release/Nothingmaxxing/UserProfileMover" alt="Release"></a>
  <a href="https://github.com/Nothingmaxxing/UserProfileMover/actions/workflows/check.yml"><img src="https://img.shields.io/github/actions/workflow/status/Nothingmaxxing/UserProfileMover/check.yml?branch=main&label=checks" alt="Checks"></a>
  <a href="https://github.com/Nothingmaxxing/UserProfileMover/releases"><img src="https://img.shields.io/github/downloads/Nothingmaxxing/UserProfileMover/total" alt="Downloads"></a>
  <a href="https://github.com/Nothingmaxxing/UserProfileMover/blob/main/LICENSE"><img src="https://img.shields.io/github/license/Nothingmaxxing/UserProfileMover" alt="License"></a>
  <img src="https://img.shields.io/badge/PowerShell-5.1-5391FE" alt="PowerShell 5.1">
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D6" alt="Windows 10 | 11 | Server">
</p>

**UserProfileMover** moves an Active Directory user's data from an old PC to a new one: desktop, documents, downloads, browsers with saved passwords and CryptoPro CSP signatures. Everything is done from one window on the admin PC, with nothing to install and no agents on users' PCs.

> [!IMPORTANT]
> Copies contain browser passwords and signature keys. Keep them where only administrators have access, or turn on copy encryption.

## Features

- **Move now**: when both PCs are on, one button moves everything from the old PC to the new one.
- **Via a storage**: "Capture from PC" now, "Restore to PC" later, for example after reinstalling Windows. The storage is a share on a NAS or file server, or, without a NAS, a folder or USB drive on the admin PC.
- **Browser passwords without export**: Chrome, Edge, Firefox, Yandex Browser, Chromium-Gost. DPAPI keys move with the profile: the user opens the browser and everything is there.
- **CryptoPro CSP signatures**: "Directory" and "Registry" containers, personal certificates with their keys.
- **Copy encryption**: 7-Zip, AES-256.
- **Transfer report**: HTML with a "what was transferred" table and lines for signatures.
- **The old PC stays as it was**: nothing is deleted or changed there.
- **Detailed log**: every step and every file that was not copied, with the reason.
- **Russian and English interface**, update check on GitHub.

## Quick start

1. Download the ZIP from the [latest release](https://github.com/Nothingmaxxing/UserProfileMover/releases/latest), extract it to a folder users cannot write to, and remove the "downloaded from the internet" mark: `Get-ChildItem -Recurse | Unblock-File` in that folder.
2. Copy `config.example.en.psd1` to `config.psd1` and set `StoreRoot` in it: where to keep the copies.
3. Run `profile-move.cmd` and enter a domain admin account.

Requirements: an AD domain, Windows 10/11 or Windows Server with Windows PowerShell 5.1, and an account that is an administrator on users' PCs. No RSAT needed.

Full guide: **[README.en.md](https://github.com/Nothingmaxxing/UserProfileMover/blob/main/README.en.md)**. It is also in the ZIP and opens with the **Guide** button in the window.

## Support the project

If the tool helped you, give the project a ⭐. Report bugs and ideas in [Issues](https://github.com/Nothingmaxxing/UserProfileMover/issues).

## License

[MIT](https://github.com/Nothingmaxxing/UserProfileMover/blob/main/LICENSE): free to use, change and share.
