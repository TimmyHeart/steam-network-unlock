**Language:** [Tiếng Việt](README.md) | **English**

# SteamFix — Steam Network Diagnostics & Repair Tool

**SteamFix** is a Windows troubleshooting utility packaged as a `.bat` file that combines Windows PowerShell and C#. It is designed to test, diagnose, and attempt to address selected Steam connectivity issues that may involve DNS resolution or TLS/SNI filtering along the network path.

It is intended for situations such as:
- Steam Store or Community pages loading as blank pages or missing styles/CSS.
- Steam connection errors such as **`-105`**.
- Default or missing player avatars in Steam/CS2.
- Inability to connect to selected Steam domains or game-content delivery servers.

> **Disclaimer:** SteamFix is a diagnostic and case-specific troubleshooting tool, not a guaranteed fix for every Steam issue. Results depend on the ISP, DNS configuration, network routing, Steam server status, and Windows configuration.

## Key Features

### 1. Steam Connectivity Diagnostics

- Tests DNS resolution and HTTPS connectivity for the Steam domains configured in the tool.
- Helps distinguish between DNS resolution failures, TCP connection failures, and TLS/HTTPS errors.
- Can compare Windows DNS results with DNS-over-HTTPS (DoH) queries.
- Reports results by domain to help narrow down possible causes.

### 2. Experimental Local TCP Relay for TLS/SNI Connections

SteamFix can attempt to run a local TCP relay on `127.0.0.1` and test different ways of sending the TLS **ClientHello**, including different data-splitting patterns.

If a domain passes the checks, the tool may offer to route that domain through the relay by adding an entry to a dedicated block in the Windows `hosts` file. The relay forwards TLS traffic; it does not decrypt HTTPS content.

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
- **QUIC:** optionally adds or removes a Windows Firewall rule blocking UDP port 443 for `steamwebhelper.exe`. This can be used to test whether forcing the Steam browser toward TCP helps with a compatibility issue. It is not intended to be enabled by default.

## How to Use

1. Download `STEAM FIX.bat` from the repository to a Windows PC.
2. Review the source before running it, especially because some operations require Administrator privileges.
3. Run the file and approve the elevation prompt if you want to continue.
4. Review the startup diagnostics, then select an item from the menu.
5. To attempt the combined troubleshooting workflow, choose **`[1] SUA TOAN DIEN`** (Vietnamese for “Full Repair”). The tool checks domains, attempts relay setup, and asks for confirmation before adding relay mappings to `hosts`.
6. To investigate the cause before changing settings, start with the primarily read-only diagnostics **`[2]`**, **`[3]`**, **`[11]`**, **`[12]`**, or **`[13]`**.

### Menu Reference

| Item | Function |
|---|---|
| `[1]` | Combined repair workflow: DNS, DoH if supported, relay checks/setup, connectivity checks, and Steam restart |
| `[2]` | Re-scan connectivity and show DNS/relay status; primarily read-only |
| `[3]` | Test TLS ClientHello splitting patterns; reads the existing configuration |
| `[4]` | Remove the relay and the SteamFix-managed `hosts` block |
| `[5]` | Clear Steam web/HTTP/avatar caches and restart Steam |
| `[6]` | Set Google/Cloudflare DNS and attempt to enable DoH |
| `[7]` | Return network adapters to automatic DNS configuration |
| `[8]` / `[9]` | Enable / remove the QUIC-blocking rule for SteamWebHelper |
| `[10]` | View relay logs |
| `[11]` | Diagnose possible SNI-based versus IP-based filtering |
| `[12]` | Diagnose Steam game-content download connectivity |
| `[13]` | Diagnose avatar and CDN connectivity |
| `[0]` | Exit |

## Requirements and Implementation

- Windows with Windows PowerShell and the networking/task-scheduling components used by the script.
- **Administrator** privileges for operations that change DNS, `hosts`, Windows Firewall, or Scheduled Tasks.
- An Internet connection to test public DNS services and Steam endpoints.
- No separate Python installation or relay library download is required. The C# component is compiled at runtime using PowerShell's .NET `Add-Type` mechanism.
- DoH support depends on the Windows version and the DNS management commands available on that system.

## System Changes to Be Aware Of

Depending on the selected menu item, SteamFix may:
- Change DNS settings on the network adapters it processes; DoH settings may also be registered in Windows.
- Create a Scheduled Task named **`SteamFix Relay`** that runs the relay under the SYSTEM account at startup or logon.
- Listen on local TCP address `127.0.0.1:443` and, when its HTTP component is enabled, `127.0.0.1:80`.
- Write Steam domain mappings to the Windows `hosts` file after user confirmation.
- Delete Steam web/HTTP/avatar cache data when the cache-cleanup option is selected.
- Add a Windows Firewall rule if the user enables the QUIC-blocking option.

**Removing the relay does not automatically restore every setting to its previous state.** Menu item `[4]` removes the relay and the `hosts` block managed by SteamFix. If QUIC blocking was enabled, use `[9]` to remove that rule. Menu item `[7]` changes adapters to automatic DNS; it does not restore a previous custom static DNS configuration. Record your original network settings before running the tool if your system uses a custom configuration.

## Limitations

- SteamFix cannot repair Steam server outages, account issues, game bugs, or broken game/application installations.
- Changing DNS does not, by itself, resolve every TLS/SNI issue or IP-based block.
- The relay applies only to domains that are tested and configured; other Steam connections may not use it.
- Diagnostic output provides clues for troubleshooting, not definitive proof of an ISP's filtering policy.
- The tool may not resolve an issue if the relay cannot reach the destination server or if the network filtering method is incompatible with the tested TLS-splitting patterns.

## Logs

Relay data and logs are stored under:

```text
%ProgramData%\SteamFix\
```

Files may include `relay.log`, `relay-error.log`, and relay support data. Logs can help when reporting a problem, but review them and redact personal or sensitive information before sharing them publicly.

## Bug Reports and Contributions

When reporting an issue, include your Windows version, ISP or connection type, the symptoms observed, and the menu item you ran. If you attach logs, share only the relevant portion and remove private information first.

## Disclaimer

This tool is provided for network diagnostics and troubleshooting on the user's own computer. Review the source code before running it and evaluate the system changes it proposes. The author does not guarantee that it will work with every network configuration and is not responsible for changes the user explicitly approves.

---

**Author:** TimmyHeart - V — Tran Hieu Nghia
