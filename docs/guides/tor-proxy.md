# tor-proxy

A Tor-based internet anonymizer for macOS. Routes system traffic through the Tor network by configuring your Mac's SOCKS proxy to point at a local Tor instance.

## Installation

```bash
brew tap davidwhittington/mac-security
brew install davidwhittington/mac-security/tor-proxy
```

This installs `tor-proxy` and its dependency (`tor`) in one step.

## Quick start

```bash
tor-proxy enable     # Start Tor and route traffic through it
tor-proxy status     # Check anonymized IP and connection status
tor-proxy newid      # Get a new exit node IP
tor-proxy disable    # Restore direct connection
```

## Commands

### `enable`

Starts the Tor daemon and configures the active network interface's SOCKS proxy to `127.0.0.1:9050`. Local addresses (`.local`, `127.0.0.1`, `localhost`, `169.254/16`) bypass the proxy automatically.

Waits up to 30 seconds for Tor to bootstrap before configuring the proxy. Prompts for your system password since `networksetup` requires admin privileges.

### `disable`

Turns off the SOCKS proxy on the active network interface and stops the Tor process. Your Mac returns to a direct internet connection.

### `status`

Displays:
- Detected network service (Wi-Fi, Ethernet, etc.)
- Whether the Tor process is running
- Whether the SOCKS proxy is enabled
- Your current external IP address
- Verification from `check.torproject.org` confirming traffic is exiting through Tor

### `newid`

Requests a new Tor circuit so your traffic exits from a different node with a different IP. If the Tor control port (9051) is available, it sends a `NEWNYM` signal. Otherwise, it restarts Tor entirely to force new circuits.

## How it works

```
┌──────────────┐     ┌───────────────┐     ┌───────────────┐
│  Your Mac    │     │  Tor SOCKS    │     │  Tor Network  │
│  (apps)      │────>│  127.0.0.1    │────>│  (3 relays)   │───> Internet
│              │     │  :9050        │     │               │
└──────────────┘     └───────────────┘     └───────────────┘
```

1. `tor-proxy` detects your active network interface by checking the default route
2. It starts the Tor daemon, which opens a SOCKS5 proxy on port 9050
3. It configures macOS to use that SOCKS proxy via `networksetup`
4. Applications that honor system proxy settings route traffic through Tor
5. Tor encrypts and relays traffic through three nodes before it exits to the destination

## Network interface detection

The script automatically identifies which network service to configure by parsing `networksetup -listnetworkserviceorder`:

1. Reads the default route interface (e.g., `en0`)
2. Maps it to the macOS network service name (e.g., "Wi-Fi") by matching the device in the service order list

This works whether you're on Wi-Fi, Ethernet, or a USB adapter without any manual configuration.

## Limitations

**Not all traffic is captured.** The macOS system SOCKS proxy is a cooperative setting. Applications that respect System Settings > Network > Proxies will route through Tor. Applications that manage their own connections (some CLI tools, VPN clients, certain apps) may bypass it entirely.

For coverage of specific tools:

| Tool | Honors system SOCKS proxy? |
|------|---------------------------|
| Safari | Yes |
| Chrome | Yes |
| Firefox | Has its own proxy settings (configure manually) |
| curl | Yes, with `--proxy socks5h://127.0.0.1:9050` or via env var |
| git (HTTPS) | Partial (set `http.proxy` in git config) |
| ssh | No (use `ProxyCommand` with `nc -X 5`) |

**DNS leaks.** When the SOCKS proxy is configured at the system level, DNS queries from compliant apps go through Tor (SOCKS5 resolves DNS remotely). Non-compliant apps may leak DNS queries to your ISP.

**Performance.** Tor adds latency (typically 200-800ms per request) due to multi-hop relay routing. Bandwidth is also reduced. This is normal and expected.

**Not a VPN.** This does not create a network tunnel. It configures a proxy. The distinction matters for threat modeling.

## Hardening (optional)

For stronger guarantees, you can add `pf` (packet filter) firewall rules to block any traffic that doesn't go through Tor. This prevents DNS leaks and forces non-compliant apps to fail rather than bypass the proxy.

Add to `/etc/pf.conf`:

```
# Block all outbound traffic except through Tor
block out quick on egress proto { tcp, udp } from any to any
pass out quick on egress proto tcp from any to 127.0.0.1 port 9050
pass out quick on lo0 all
```

Then reload with `sudo pfctl -f /etc/pf.conf && sudo pfctl -e`. Revert by disabling pf: `sudo pfctl -d`.

This is not done by the script automatically because it can break connectivity if something goes wrong. Use at your own discretion.

## Enabling the Tor control port

By default, Homebrew's Tor installation doesn't enable the control port. To allow `newid` to work without restarting Tor:

1. Edit the Tor config:
   ```bash
   echo -e "ControlPort 9051\nCookieAuthentication 0" >> $(brew --prefix)/etc/tor/torrc
   ```

2. Restart Tor:
   ```bash
   brew services restart tor
   ```

The `newid` command will then send a `NEWNYM` signal over the control port, which is faster and more graceful than a full restart.

## Troubleshooting

**"No default network interface found"**
You're not connected to any network. Connect to Wi-Fi or plug in Ethernet first.

**"Tor is not installed"**
Reinstall via `brew install davidwhittington/mac-security/tor-proxy`. The formula depends on `tor` and will install it automatically.

**"Tor failed to start within 30 seconds"**
Tor couldn't bootstrap. Check if your network blocks Tor (some corporate/school networks do). Try `tor --log notice stdout` to see detailed bootstrap output. You may need to configure bridges in your `torrc`.

**Password prompt on every enable/disable**
`networksetup` requires admin privileges. This is by design. You can wrap the script in a sudo alias if you prefer, but understand the security tradeoff.

**Some sites block Tor exit nodes**
Many websites (banking, streaming, some APIs) actively block known Tor exit IPs. This is expected. Use `tor-proxy newid` to try a different exit, but some services will block all Tor traffic regardless.
