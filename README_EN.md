**Language:** [Tiếng Việt](README.md) | **English**

# SteamFix — Steam Network Diagnostics & Repair Tool

**Current version: v5.2**

**SteamFix** is a Windows troubleshooting utility packaged as a `.bat` file that combines Windows PowerShell and C#. It is designed to test, diagnose, and attempt to address selected Steam connectivity issues that may involve DNS resolution or TLS/SNI filtering along the network path. Since v5.1 it also includes an attempted fix for the **MW4 Texture Streamer** (textures not downloading) on PCs without real IPv6.

It is intended for situations such as:
- Steam Store or Community pages loading as blank pages or missing styles/CSS.
- Steam connection errors such as **`-105`**.
- Default or missing player avatars in Steam/CS2.
- Inability to connect to selected Steam domains or game-content delivery servers.
- MW4 failing to download textures through the Texture Streamer (CDN domain `cod-assets.cdn.callofduty.com`), typically on PCs that have no real IPv6 address.

> **Disclaimer:** SteamFix is a diagnostic and case-specific troubleshooting tool, not a guaranteed fix for every Steam or game issue. Results depend on the ISP, DNS configuration, network routing, Steam server and game-CDN status, and Windows configuration.

## What's New

- **v5.1 — MW4 Texture Streamer (IPv6) fix:** adds menu items **`[14]`** (enable) and **`[15]`** (diagnostics, read-only). The relay additionally listens on the IPv6 loopback address `[::1]:443` and `[::1]:80`, and the `hosts` file receives an extra `::1` line for the game's CDN domain. The relay now also accepts `*.cdn.callofduty.com` hostnames.
- **v5.2 — MW4 fallback mode:** if the relay **cannot open `[::1]`**, the tool no longer drops the MW4 part entirely. It falls back to writing only the `127.0.0.1` line, with a clear warning that this mode **may not work**. The tool prints the actual reason `[::1]` could not be opened (it reads `relay.log`, looks for programs occupying the IPv6 port, and checks the `DisabledComponents` registry value) and runs a self-check of how the hostname resolves.

## Key Features

### 1. Steam Connectivity Diagnostics

- Tests DNS resolution and HTTPS connectivity for the Steam domains configured in the tool.
- Helps distinguish between DNS resolution failures, TCP connection failures, and TLS/HTTPS errors.
- Can compare Windows DNS results with DNS-over-HTTPS (DoH) queries.
- Reports results by domain to help narrow down possible causes.
- Shows relay status at startup, including the `[::1]` ports if the MW4 part has been enabled.

### 2. Experimental Local TCP Relay for TLS/SNI Connections

SteamFix can attempt to run a local TCP relay on `127.0.0.1` and test different ways of sending the TLS **ClientHello**, including different data-splitting patterns.

If a domain passes the checks, the tool may offer to route that domain through the relay by adding an entry to a dedicated block in the Windows `hosts` file. The relay forwards TLS traffic; it does not decrypt HTTPS content. The relay only accepts hostnames on its allow-list (Steam domains and `*.cdn.callofduty.com`); connections for any other hostname are rejected.

This mechanism may help with certain types of connection filtering, but it **does not bypass every form of blocking**. For example, it may not help when the destination IP is blocked or the connection to the destination server itself fails.

### 3. DNS Management

- Sets IPv4/IPv6 DNS servers to Google DNS and Cloudflare DNS.
- Attempts to configure DNS-over-HTTPS (DoH) when the Windows version supports the required commands.
- Displays the current DNS configuration for inspection.
- Provides an option to return network adapters to automatic DNS configuration.

### 4. Backed-Up Windows `hosts` Management

- Adds only domains that pass the relay checks.
- Places SteamFix-managed entries inside a clearly marked block.
- Creates a backup before writing and checks the file after the change.
- Preserves lines outside the SteamFix-managed block when adding or removing that block.
- Detects some malformed `hosts` file conditions and can attempt recovery from a suitable backup if one is found.

If Steam domain redirects are found in `hosts` outside the SteamFix-managed block, the tool may ask before disabling them. Review the displayed details carefully before approving any change.

### 5. Steam Cache Cleanup and Restart

Can remove selected Steam browser, HTTP, and avatar caches so Steam can reload interface resources or images. The tool asks before closing a running Steam process.

### 6. Specialized Diagnostics

- **SNI/IP:** investigates whether connection resets appear to depend on the TLS hostname or destination IP.
- **Game downloads:** reads part of `content_log.txt` and checks Steam content-delivery domains.
- **Avatars:** checks relay logs and avatar cache, attempts avatar downloads, and inspects TCP connections associated with Steam, SteamWebHelper, and CS2.
- **Relay logs:** displays recent entries to help determine whether the relay receives connections or reports errors.
- **MW4 / IPv6:** checks whether the PC has real IPv6, the MW4-related `hosts` lines, what address Windows resolves the CDN hostname to, and whether the relay is listening on `127.0.0.1` and `[::1]` (see section 7).
- **QUIC:** optionally adds or removes a Windows Firewall rule blocking UDP port 443 for `steamwebhelper.exe`. This can be used to test whether forcing the Steam browser toward TCP helps with a compatibility issue. It is not intended to be enabled by default.

### 7. MW4 Texture Streamer (IPv6) Fix — new in v5.1

**The cause this targets:** on a PC without real IPv6, Windows may hand the game an IPv4 address in IPv4-mapped form (`::ffff:a.b.c.d`). The game then cannot open its socket and textures do not download.

**How it works (item `[14]`):**
- Runs the same relay-setup workflow as `[1]` (it also tests the Steam domains, so it takes a few tens of seconds) and adds `cod-assets.cdn.callofduty.com` to the domains being tested.
- The relay additionally listens on `[::1]:443` (HTTPS) and `[::1]:80` (HTTP).
- The SteamFix block in `hosts` gets two extra lines for the game's CDN domain: `127.0.0.1 cod-assets.cdn.callofduty.com` and `::1 cod-assets.cdn.callofduty.com`. Because of the `::1` line, the game receives a real IPv6 address instead of the `::ffff:a.b.c.d` form; the relay forwards the TLS bytes to the CDN's real IPv4 address.
- `hosts` is written only after the user confirms. If the game's CDN domain cannot be reached through the relay, the MW4 part is skipped and the Steam part is still installed normally.
- Re-running `[1]` keeps a previously enabled MW4 part; menu item `[4]` removes it as well.
- After setup, **fully close the game** (and the Battle.net launcher, if open) and start it again.

**Fallback mode (v5.2):** the relay opens `[::1]` after `127.0.0.1`, and the tool waits up to about 5 seconds for it. If `[::1]` still isn't listening (for example the port is occupied by another program, or the OS has no IPv6 support), the tool:
- Writes only the `127.0.0.1` line for MW4 (no `::1` line) instead of abandoning MW4.
- Warns that this mode only works if the game accepts `127.0.0.1`; if the game still receives `::ffff:127.0.0.1`, textures will still not download.
- Prints the actual reason `[::1]` could not be opened and suggests next steps.
- Explains how to confirm the result: start the game, then choose `[15]`; section `[5]` must show `ok=` lines before you can treat the game as actually reaching the relay. After fixing the cause of the `[::1]` bind failure, choose `[14]` again to install with the `::1` line.

**Diagnostics (item `[15]`, read-only, changes nothing):**
1. The PC's IPv6: whether it has a global IPv6 address, and the `DisabledComponents` value.
2. The `hosts` lines related to the game's CDN domain.
3. What address Windows resolves the CDN hostname to (as the game would see it).
4. Whether the relay is listening on `127.0.0.1:443`, `127.0.0.1:80`, `[::1]:443`, and `[::1]:80`.
5. `relay.log` lines mentioning MW4 or `[::1]`.
6. Whether the real CDN is reachable directly (IP obtained via encrypted DNS, bypassing the relay).

Signs of success: the game's texture cache folder starts receiving files, and `relay.log` contains a `stat cod-assets... ok=N` line (view it with `[10]`).

## How to Use

1. Download `STEAM FIX.bat` from the repository to a Windows PC.
2. Review the source before running it, especially because some operations require Administrator privileges.
3. Run the file and approve the elevation prompt if you want to continue.
4. Review the startup diagnostics, then select an item from the menu.
5. To attempt the combined troubleshooting workflow, choose **`[1] SUA TOAN DIEN`** (Vietnamese for “Full Repair”). The tool checks domains, attempts relay setup, and asks for confirmation before adding relay mappings to `hosts`.
6. To investigate the cause before changing settings, start with the primarily read-only diagnostics **`[2]`**, **`[3]`**, **`[11]`**, **`[12]`**, **`[13]`**, or **`[15]`**.
7. If MW4 fails to download textures: choose **`[15]`** to see the current state, choose **`[14]`** to enable the fix, fully close and reopen the game, then choose **`[15]`** again to confirm.

### Menu Reference

| Item | Function |
|---|---|
| `[1]` | Combined repair workflow: DNS, DoH if supported, relay checks/setup, connectivity checks, and Steam restart; keeps the MW4 part if it was enabled earlier |
| `[2]` | Re-scan connectivity and show DNS/relay status (including `[::1]` status if MW4 is enabled); primarily read-only |
| `[3]` | Test TLS ClientHello splitting patterns; reads the existing configuration |
| `[4]` | Remove the relay, the SteamFix-managed `hosts` block (including MW4 lines), and the relay data folder |
| `[5]` | Clear Steam web/HTTP/avatar caches and restart Steam |
| `[6]` | Set Google/Cloudflare DNS and attempt to enable DoH |
| `[7]` | Return network adapters to automatic DNS configuration |
| `[8]` / `[9]` | Enable / remove the QUIC-blocking rule for SteamWebHelper |
| `[10]` | View relay logs |
| `[11]` | Diagnose possible SNI-based versus IP-based filtering |
| `[12]` | Diagnose Steam game-content download connectivity |
| `[13]` | Diagnose avatar and CDN connectivity |
| `[14]` | **New:** fix MW4 Texture Streamer (IPv6): `[::1]` relay for `cod-assets.cdn.callofduty.com`, with a fallback mode if `[::1]` cannot be opened |
| `[15]` | **New:** MW4 / IPv6 diagnostics (read-only, changes nothing) |
| `[0]` | Exit |

## Requirements and Implementation

- Windows with Windows PowerShell and the networking/task-scheduling components used by the script.
- **Administrator** privileges for operations that change DNS, `hosts`, Windows Firewall, or Scheduled Tasks.
- An Internet connection to test public DNS services and Steam endpoints.
- No separate Python installation or relay library download is required. The C# component is compiled at runtime using PowerShell's .NET `Add-Type` mechanism.
- DoH support depends on the Windows version and the DNS management commands available on that system.
- The MW4 part needs an OS that supports the IPv6 loopback address (`::1`) to work fully; otherwise the tool falls back as described in section 7.

## System Changes to Be Aware Of

Depending on the selected menu item, SteamFix may:
- Change DNS settings on the network adapters it processes; DoH settings may also be registered in Windows.
- Create a Scheduled Task named **`SteamFix Relay`** that runs the relay under the SYSTEM account at startup or logon.
- Listen on local TCP address `127.0.0.1:443` and, when its HTTP component is enabled, `127.0.0.1:80`.
- When the MW4 fix (`[14]`) is enabled: also listen on the IPv6 loopback `[::1]:443` and `[::1]:80`.
- Write Steam domain mappings to the Windows `hosts` file after user confirmation. For MW4, this block also contains a `127.0.0.1` line and, if the relay can listen on `[::1]`, a `::1` line for `cod-assets.cdn.callofduty.com`.
- Delete Steam web/HTTP/avatar cache data when the cache-cleanup option is selected.
- Add a Windows Firewall rule if the user enables the QUIC-blocking option.

**Removing the relay does not automatically restore every setting to its previous state.** Menu item `[4]` removes the Scheduled Task, the `hosts` block managed by SteamFix (including MW4 lines), and **deletes the `%ProgramData%\SteamFix\` folder, including its logs**; if MW4 was enabled, restart the game afterward. If QUIC blocking was enabled, use `[9]` to remove that rule. Menu item `[7]` changes adapters to automatic DNS; it does not restore a previous custom static DNS configuration. Record your original network settings before running the tool if your system uses a custom configuration.

## Limitations

- SteamFix cannot repair Steam server outages, account issues, game bugs, or broken game/application installations.
- Changing DNS does not, by itself, resolve every TLS/SNI issue or IP-based block.
- The relay applies only to domains that are tested and configured; other Steam connections may not use it.
- The MW4 part applies only to `cod-assets.cdn.callofduty.com` and only targets socket failures caused by IPv4-mapped addresses; it does not fix other game or launcher problems.
- The MW4 fallback mode (only a `127.0.0.1` line) is **not guaranteed to work**; treat it as working only when `[15]` shows `ok=` lines in `relay.log` after you start the game.
- Diagnostic output provides clues for troubleshooting, not definitive proof of an ISP's filtering policy.
- The tool may not resolve an issue if the relay cannot reach the destination server or if the network filtering method is incompatible with the tested TLS-splitting patterns.

## Logs

Relay data and logs are stored under:

```text
%ProgramData%\SteamFix\
```

Files may include `relay.log`, `relay-error.log`, and relay support data. Logs can help when reporting a problem, but review them and redact personal or sensitive information before sharing them publicly. Note that menu item `[4]` deletes this entire folder, so back up the logs first if you need them for a bug report.

## Bug Reports and Contributions

When reporting an issue, include your Windows version, ISP or connection type, the symptoms observed, and the menu item you ran. For MW4 issues, also include the output of item `[15]`. If you attach logs, share only the relevant portion and remove private information first.

## Disclaimer

This tool is provided for network diagnostics and troubleshooting on the user's own computer. Review the source code before running it and evaluate the system changes it proposes. The author does not guarantee that it will work with every network configuration and is not responsible for changes the user explicitly approves.

---

**Author:** TimmyHeart - V — Tran Hieu Nghia
