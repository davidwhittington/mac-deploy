#!/usr/bin/env python3
"""
chromium-browse: Simulated browsing traffic generator for any Chromium-based browser.

Reads URLs from urls.txt, visits them in random order in headless mode,
follows random links on each page to simulate organic browsing. Controls the
browser via its native Chrome DevTools Protocol (CDP).

Supports: Chrome, Edge, Brave, Island, Arc, Vivaldi, Opera, Chromium,
          Comet, Atlas, Sidekick, Wavebox, and any custom Chromium binary.

Usage:
    python3 chromium-browse.py --browser island [--urls urls.txt] [--max-depth 2] [--rounds 1]
    python3 chromium-browse.py --browser chrome
    python3 chromium-browse.py --browser /path/to/custom/binary
    python3 chromium-browse.py --list-browsers
"""

import argparse
import asyncio
import json
import logging
import os
import platform
import random
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import urlparse

try:
    import websockets
except ImportError:
    print("Missing dependency: websockets")
    print("Install with: pip3 install websockets")
    sys.exit(1)

try:
    import aiohttp
except ImportError:
    print("Missing dependency: aiohttp")
    print("Install with: pip3 install aiohttp")
    sys.exit(1)

DEFAULT_CDP_PORT = 9222

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("chromium-browse")

# ---------------------------------------------------------------------------
# Browser registry: name -> (macOS path, Linux path, Windows path)
# Only macOS and Linux are meaningfully supported; Windows paths included
# for reference but untested.
# ---------------------------------------------------------------------------
BROWSERS: dict[str, dict[str, str]] = {
    "chrome": {
        "darwin": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "linux": "/usr/bin/google-chrome-stable",
        "win32": r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    },
    "chromium": {
        "darwin": "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "linux": "/usr/bin/chromium-browser",
        "win32": r"C:\Program Files\Chromium\Application\chrome.exe",
    },
    "edge": {
        "darwin": "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "linux": "/usr/bin/microsoft-edge-stable",
        "win32": r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    },
    "brave": {
        "darwin": "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
        "linux": "/usr/bin/brave-browser",
        "win32": r"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
    },
    "island": {
        "darwin": "/Applications/Island.app/Contents/MacOS/Island",
        "linux": "/opt/island/island",
        "win32": r"C:\Program Files\Island\Island.exe",
    },
    "arc": {
        "darwin": "/Applications/Arc.app/Contents/MacOS/Arc",
    },
    "vivaldi": {
        "darwin": "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi",
        "linux": "/usr/bin/vivaldi-stable",
        "win32": r"C:\Program Files\Vivaldi\Application\vivaldi.exe",
    },
    "opera": {
        "darwin": "/Applications/Opera.app/Contents/MacOS/Opera",
        "linux": "/usr/bin/opera",
        "win32": r"C:\Program Files\Opera\opera.exe",
    },
    "comet": {
        "darwin": "/Applications/Comet.app/Contents/MacOS/Comet",
    },
    "atlas": {
        "darwin": "/Applications/Atlas.app/Contents/MacOS/Atlas",
    },
    "sidekick": {
        "darwin": "/Applications/Sidekick.app/Contents/MacOS/Sidekick",
        "linux": "/opt/sidekick/sidekick",
    },
    "wavebox": {
        "darwin": "/Applications/Wavebox.app/Contents/MacOS/Wavebox",
        "linux": "/opt/wavebox/wavebox",
    },
    "thorium": {
        "darwin": "/Applications/Thorium.app/Contents/MacOS/Thorium",
        "linux": "/usr/bin/thorium-browser",
    },
    "ungoogled-chromium": {
        "darwin": "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "linux": "/usr/bin/chromium",
    },
}


def get_platform() -> str:
    return sys.platform  # darwin, linux, win32


def resolve_browser(name: str) -> tuple[str, str]:
    """
    Resolve a browser name or path to (display_name, binary_path).
    If `name` is an absolute path, use it directly.
    """
    # Absolute or relative path to a binary
    if os.sep in name or name.startswith("."):
        if os.path.isfile(name) and os.access(name, os.X_OK):
            return (os.path.basename(name), name)
        log.error("Custom binary not found or not executable: %s", name)
        sys.exit(1)

    key = name.lower().replace(" ", "").replace("-", "")
    # Normalize common aliases
    aliases = {
        "googlechrome": "chrome",
        "microsoftedge": "edge",
        "bravebrowser": "brave",
    }
    key = aliases.get(key, key)

    if key not in BROWSERS:
        log.error("Unknown browser '%s'. Use --list-browsers to see available options.", name)
        sys.exit(1)

    plat = get_platform()
    paths = BROWSERS[key]
    if plat not in paths:
        log.error("Browser '%s' has no known path for platform '%s'.", name, plat)
        sys.exit(1)

    binary = paths[plat]
    if not os.path.exists(binary):
        log.error("Browser '%s' not installed at expected path: %s", name, binary)
        sys.exit(1)

    return (name, binary)


def list_browsers():
    """Print all known browsers and their install status."""
    plat = get_platform()
    print(f"\nKnown Chromium-based browsers (platform: {plat}):\n")
    print(f"  {'Name':<22} {'Status':<12} Path")
    print(f"  {'----':<22} {'------':<12} ----")
    for name, paths in sorted(BROWSERS.items()):
        path = paths.get(plat, "")
        if not path:
            status = "no path"
        elif os.path.exists(path):
            status = "installed"
        else:
            status = "not found"
        print(f"  {name:<22} {status:<12} {path}")
    print(f"\n  You can also pass an absolute path: --browser /path/to/binary\n")


def load_urls(path: str) -> list[str]:
    """Load URLs from file, one per line. Skips blanks and comments."""
    urls = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                if not line.startswith("http"):
                    line = "https://" + line
                urls.append(line)
    if not urls:
        log.error("No URLs found in %s", path)
        sys.exit(1)
    log.info("Loaded %d URLs from %s", len(urls), path)
    return urls


def start_browser(binary: str, display_name: str, cdp_port: int, user_data_dir: str) -> subprocess.Popen:
    """Launch a Chromium-based browser in headless mode with CDP enabled."""
    args = [
        binary,
        f"--remote-debugging-port={cdp_port}",
        f"--user-data-dir={user_data_dir}",
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        "--disable-popup-blocking",
        "--disable-translate",
        "--disable-sync",
        "--disable-background-networking",
        "--metrics-recording-only",
        "--mute-audio",
        "--window-size=1920,1080",
    ]
    log.info("Starting %s (headless, CDP port %d)...", display_name, cdp_port)
    proc = subprocess.Popen(
        args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc


async def wait_for_cdp(port: int, browser_name: str, timeout: float = 15.0) -> str:
    """Wait for CDP endpoint to become available, return WebSocket URL."""
    url = f"http://127.0.0.1:{port}/json/version"
    deadline = time.monotonic() + timeout
    async with aiohttp.ClientSession() as session:
        while time.monotonic() < deadline:
            try:
                async with session.get(url) as resp:
                    data = await resp.json()
                    ws_url = data["webSocketDebuggerUrl"]
                    browser_version = data.get("Browser", "unknown")
                    log.info("CDP ready (%s): %s", browser_version, ws_url)
                    return ws_url
            except (aiohttp.ClientError, KeyError, ConnectionRefusedError):
                await asyncio.sleep(0.5)
    raise TimeoutError(f"{browser_name} CDP did not respond on port {port} within {timeout}s")


class BrowserSession:
    """Manages a CDP connection for page navigation and link discovery."""

    def __init__(self, ws_url: str):
        self.ws_url = ws_url
        self.ws = None
        self._msg_id = 0
        self._responses: dict[int, asyncio.Future] = {}
        self._listener_task = None

    async def connect(self):
        self.ws = await websockets.connect(self.ws_url, max_size=10 * 1024 * 1024)
        self._listener_task = asyncio.create_task(self._listen())

    async def _listen(self):
        try:
            async for msg in self.ws:
                data = json.loads(msg)
                if "id" in data and data["id"] in self._responses:
                    self._responses[data["id"]].set_result(data)
        except websockets.ConnectionClosed:
            pass

    async def send(self, method: str, params: dict | None = None, timeout: float = 30.0) -> dict:
        self._msg_id += 1
        msg_id = self._msg_id
        payload = {"id": msg_id, "method": method}
        if params:
            payload["params"] = params
        future = asyncio.get_event_loop().create_future()
        self._responses[msg_id] = future
        await self.ws.send(json.dumps(payload))
        try:
            result = await asyncio.wait_for(future, timeout=timeout)
        finally:
            self._responses.pop(msg_id, None)
        return result

    async def navigate(self, url: str, wait_seconds: float = 3.0):
        """Navigate to a URL and wait for load."""
        log.info("  -> Navigating to %s", url)
        await self.send("Page.enable")
        await self.send("Page.navigate", {"url": url})
        await asyncio.sleep(wait_seconds)

    async def get_links(self, base_url: str) -> list[str]:
        """Extract all <a href> links from the current page."""
        js = """
        (() => {
            const links = Array.from(document.querySelectorAll('a[href]'));
            return links.map(a => a.href).filter(h =>
                h.startsWith('http') && !h.startsWith('javascript:')
            );
        })()
        """
        try:
            result = await self.send(
                "Runtime.evaluate",
                {"expression": js, "returnByValue": True},
                timeout=10.0,
            )
            value = result.get("result", {}).get("result", {}).get("value", [])
            if isinstance(value, list):
                return list(set(value))
        except (asyncio.TimeoutError, KeyError):
            pass
        return []

    async def scroll_randomly(self):
        """Simulate some scroll behavior."""
        scroll_y = random.randint(200, 2000)
        await self.send(
            "Runtime.evaluate",
            {"expression": f"window.scrollTo(0, {scroll_y})"},
            timeout=5.0,
        )
        await asyncio.sleep(random.uniform(0.5, 1.5))

    async def close(self):
        if self._listener_task:
            self._listener_task.cancel()
        if self.ws:
            await self.ws.close()


def is_same_domain(url1: str, url2: str) -> bool:
    return urlparse(url1).netloc == urlparse(url2).netloc


def filter_crawlable_links(links: list[str], base_url: str) -> list[str]:
    """Filter links to same-domain, non-asset URLs worth following."""
    skip_extensions = {
        ".pdf", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp",
        ".mp3", ".mp4", ".zip", ".tar", ".gz", ".exe", ".dmg",
        ".css", ".js", ".woff", ".woff2", ".ttf", ".ico",
    }
    result = []
    for link in links:
        if not is_same_domain(link, base_url):
            continue
        parsed = urlparse(link)
        path_lower = parsed.path.lower()
        if any(path_lower.endswith(ext) for ext in skip_extensions):
            continue
        if parsed.path == urlparse(base_url).path and parsed.fragment:
            continue
        result.append(link)
    return result


async def browse_site(session: BrowserSession, url: str, max_depth: int, max_links: int,
                      min_delay: float, max_delay: float, depth: int = 0):
    """Visit a URL and optionally follow links to simulate browsing."""
    await session.navigate(url, wait_seconds=random.uniform(2.0, 4.0))

    await session.scroll_randomly()
    dwell = random.uniform(min_delay, max_delay)
    log.info("  -- Dwelling %.1fs on page (depth %d)", dwell, depth)
    await asyncio.sleep(dwell)

    if depth >= max_depth:
        return

    links = await session.get_links(url)
    crawlable = filter_crawlable_links(links, url)

    if not crawlable:
        log.info("  -- No crawlable links found on this page")
        return

    num_to_follow = min(len(crawlable), random.randint(1, max_links))
    chosen = random.sample(crawlable, num_to_follow)
    log.info("  -- Following %d/%d links from this page", num_to_follow, len(crawlable))

    for link in chosen:
        await browse_site(session, link, max_depth, max_links, min_delay, max_delay, depth + 1)


async def run(args, display_name: str, binary: str):
    urls = load_urls(args.urls)
    user_data_dir = tempfile.mkdtemp(prefix="chromium-browse-")

    proc = start_browser(binary, display_name, args.cdp_port, user_data_dir)
    try:
        ws_url = await wait_for_cdp(args.cdp_port, display_name)
        session = BrowserSession(ws_url)
        await session.connect()

        for round_num in range(1, args.rounds + 1):
            log.info("=== Round %d/%d (%s) ===", round_num, args.rounds, display_name)
            shuffled = urls.copy()
            random.shuffle(shuffled)

            for i, url in enumerate(shuffled, 1):
                log.info("[%d/%d] Starting with: %s", i, len(shuffled), url)
                try:
                    await browse_site(
                        session, url,
                        max_depth=args.max_depth,
                        max_links=args.max_links,
                        min_delay=args.min_delay,
                        max_delay=args.max_delay,
                    )
                except Exception as e:
                    log.warning("  !! Error browsing %s: %s", url, e)

                between = random.uniform(args.min_delay, args.max_delay)
                log.info("  -- Pausing %.1fs before next site", between)
                await asyncio.sleep(between)

        await session.close()
        log.info("Browsing complete.")

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        shutil.rmtree(user_data_dir, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(
        description="Generate simulated browsing traffic through any Chromium-based browser (headless CDP).",
    )
    parser.add_argument("--browser", "-b", default="chrome",
                        help="Browser name (chrome, edge, brave, island, arc, comet, atlas, etc.) "
                             "or absolute path to a Chromium binary (default: chrome)")
    parser.add_argument("--list-browsers", action="store_true",
                        help="List all known browsers and their install status, then exit")
    parser.add_argument("--urls", default="urls.txt",
                        help="Path to URL list file (default: urls.txt)")
    parser.add_argument("--max-depth", type=int, default=2,
                        help="Max link-follow depth per site (default: 2)")
    parser.add_argument("--min-delay", type=float, default=2.0,
                        help="Min dwell time in seconds (default: 2)")
    parser.add_argument("--max-delay", type=float, default=8.0,
                        help="Max dwell time in seconds (default: 8)")
    parser.add_argument("--max-links", type=int, default=5,
                        help="Max links to follow per page (default: 5)")
    parser.add_argument("--rounds", type=int, default=1,
                        help="Number of full passes through the URL list (default: 1)")
    parser.add_argument("--cdp-port", type=int, default=DEFAULT_CDP_PORT,
                        help=f"CDP port (default: {DEFAULT_CDP_PORT})")
    args = parser.parse_args()

    if args.list_browsers:
        list_browsers()
        sys.exit(0)

    display_name, binary = resolve_browser(args.browser)
    log.info("Using browser: %s (%s)", display_name, binary)

    try:
        asyncio.run(run(args, display_name, binary))
    except KeyboardInterrupt:
        log.info("Interrupted, shutting down.")


if __name__ == "__main__":
    main()
