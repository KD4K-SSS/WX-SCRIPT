#!/usr/bin/env python3
import json
import logging
from logging.handlers import RotatingFileHandler
import os
import re
import sys
import time
from datetime import datetime, timezone
from urllib.parse import parse_qs, unquote, urlparse
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from bs4 import BeautifulSoup

FETCH_INTERVAL = 60

# File Paths
OUTPUT_JSON = "/var/www/html/data/hf/omiss_engine.json"
PSKR_JSON = "/var/www/html/data/hf/pskr_engine.json"
LOG_FILE = "/mnt/ssbwx_tmp/omiss_engine.log"

# ---------------------------------------------------------------------------
# Logging Setup
# ---------------------------------------------------------------------------
logger = logging.getLogger("OMISS_Engine")
logger.setLevel(logging.INFO)

log_formatter = logging.Formatter(
    "[%(asctime)s UTC] [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
)
log_formatter.converter = time.gmtime

console_handler = logging.StreamHandler(sys.stdout)
console_handler.setFormatter(log_formatter)
logger.addHandler(console_handler)

try:
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    file_handler = RotatingFileHandler(
        LOG_FILE, maxBytes=2 * 1024 * 1024, backupCount=3
    )
    file_handler.setFormatter(log_formatter)
    logger.addHandler(file_handler)
except Exception as e:
    logger.warning(
        f"Could not create file log at {LOG_FILE} ({e}). Logging to console only."
    )

# ---------------------------------------------------------------------------
# Robust HTTP Session with Automatic Retries
# ---------------------------------------------------------------------------
def create_robust_session():
    session = requests.Session()
    
    # Configure retry logic for network drops & remote disconnections
    retries = Retry(
        total=3,                            # Retry up to 3 times
        backoff_factor=2,                   # Wait 2s, 4s, 8s between retries
        status_forcelist=[500, 502, 503, 504],
        raise_on_status=False
    )
    
    adapter = HTTPAdapter(max_retries=retries)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    
    # Headers to mimic a standard browser and prevent persistent socket drops
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Connection": "close"  # Prevents reuse of stale TCP sockets dropped by omiss.net
    })
    return session

session = create_robust_session()

# ---------------------------------------------------------------------------
# Data Configurations
# ---------------------------------------------------------------------------
CALLSIGN_REGEX = re.compile(r"^[A-Z0-9]{1,3}[0-9][A-Z0-9]{1,4}$", re.IGNORECASE)

IGNORED_WORDS = {
    "NOTE", "NOTES", "INFO", "NET", "BREAK",
    "NCS", "LOG", "OFFICIAL", "CLOSED", "PAUSED"
}

NET_META = {
    "OMISS 160m SSB Net":     {"band": "160m", "freq": "1.800 – 2.000 MHz (Entire Band)"},
    "OMISS 80m SSB Net":      {"band": "80m",  "freq": "3.800 – 4.000 MHz"},
    "OMISS 80m SSB Late Net": {"band": "80m",  "freq": "3.800 – 4.000 MHz"},
    "OMISS 40m SSB Net":      {"band": "40m",  "freq": "7.175 – 7.300 MHz"},
    "OMISS 40m SSB Late Net": {"band": "40m",  "freq": "7.175 – 7.300 MHz"},
    "OMISS 20m SSB Net":      {"band": "20m",  "freq": "14.225 – 14.350 MHz"},
    "OMISS 17m SSB Net":      {"band": "17m",  "freq": "18.110 – 18.168 MHz"},
    "OMISS 15m SSB Net":      {"band": "15m",  "freq": "21.275 – 21.450 MHz"},
    "OMISS 12m SSB Net":      {"band": "12m",  "freq": "24.930 – 24.990 MHz"},
    "OMISS 10m SSB Net":      {"band": "10m",  "freq": "28.300 – 29.700 MHz"},
}

def get_band_status(band_name):
    """Reads current band status (OPEN/MARGINAL/CLOSED) from pskr_engine.json."""
    if not os.path.exists(PSKR_JSON):
        return "UNKNOWN"
    try:
        with open(PSKR_JSON, "r") as f:
            data = json.load(f)
            bands = data.get("bands", {})
            if band_name in bands:
                return bands[band_name].get("status", "UNKNOWN").upper()
    except Exception as e:
        logger.error(f"Error reading PSKR status: {e}")
    return "UNKNOWN"


def get_active_omiss_net_names():
    """Scrapes activeNets.php and extracts running net names."""
    url = "https://www.omiss.net/Facelift/iPhone/activeNets.php"
    active_nets = []

    try:
        resp = session.get(url, timeout=(10, 15))
        if resp.status_code == 200:
            soup = BeautifulSoup(resp.text, "html.parser")

            for a_tag in soup.find_all("a", href=True):
                href = a_tag["href"]

                if "net=" in href:
                    parsed_url = urlparse(href)
                    query_params = parse_qs(parsed_url.query)

                    if "net" in query_params:
                        raw_net_param = query_params["net"][0]
                        clean_param = raw_net_param.split("|")[0]
                        net_name = unquote(clean_param.replace("+", " ")).strip()

                        if net_name in NET_META and net_name not in active_nets:
                            active_nets.append(net_name)

            if not active_nets:
                for a_tag in soup.find_all("a"):
                    text = a_tag.get_text(strip=True)
                    for known_net in NET_META:
                        if (
                            known_net.lower() in text.lower()
                            and known_net not in active_nets
                        ):
                            active_nets.append(known_net)

    except (requests.exceptions.RequestException, Exception) as e:
        logger.error(f"Error fetching activeNets.php: {e}")

    return active_nets


def fetch_omiss_nets():
    net_names = get_active_omiss_net_names()
    formatted_nets = []

    if not net_names:
        logger.info("No active OMISS nets detected.")
        return formatted_nets

    for net_name in net_names:
        encoded_net = net_name.replace(" ", "+")
        url = f"https://www.omiss.net/Facelift/iPhone/checkins.php?net={encoded_net}|NETLOGGER2"

        try:
            resp = session.get(url, timeout=(10, 15))
            if resp.status_code != 200:
                logger.warning(
                    f"Received HTTP {resp.status_code} when querying {net_name}"
                )
                continue

            soup = BeautifulSoup(resp.text, "html.parser")
            checkins = []
            states_set = set()

            meta = NET_META.get(net_name, {"band": "--", "freq": "--"})

            for li in soup.find_all("li"):
                h3 = li.find("h3")
                a_tag = li.find("a")

                if not h3 or not a_tag or not h3.text.isdigit():
                    continue

                li_classes = li.get("class", [])
                if "out" in li_classes or "inactive" in li_classes:
                    continue

                lines = [
                    line.strip()
                    for line in a_tag.get_text(separator="\n").split("\n")
                    if line.strip()
                ]

                if lines:
                    parts = lines[0].split()
                    candidate_call = parts[0].upper() if len(parts) > 0 else ""
                    state = parts[1].upper() if len(parts) > 1 else ""

                    if (
                        candidate_call in IGNORED_WORDS
                        or not CALLSIGN_REGEX.match(candidate_call)
                    ):
                        continue

                    if state:
                        states_set.add(state)

                    checkins.append(
                        {
                            "num": int(h3.text),
                            "call": candidate_call,
                            "state": state,
                        }
                    )

            band_status = get_band_status(meta["band"])

            formatted_nets.append(
                {
                    "name": net_name,
                    "band": meta["band"],
                    "freq": meta["freq"],
                    "status": band_status,
                    "checkins": len(checkins),
                    "states": sorted(list(states_set)),
                    "list": checkins,
                }
            )

            logger.info(
                f"Captured Active Net: [{net_name}] | Freq: {meta['freq']} MHz | Checkins: {len(checkins)} | States: {len(states_set)}"
            )

        except (requests.exceptions.RequestException, Exception) as e:
            logger.error(f"Error fetching checkins for {net_name}: {e}")

    return formatted_nets


def write_json():
    nets = fetch_omiss_nets()
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    payload = {"timestamp": now_str, "nets": nets}

    os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)
    tmp_path = OUTPUT_JSON + ".tmp"

    with open(tmp_path, "w") as f:
        json.dump(payload, f, indent=2)
    os.replace(tmp_path, OUTPUT_JSON)


def main():
    logger.info("Starting OMISS Multi-Net Engine with Logging...")
    try:
        while True:
            write_json()
            time.sleep(FETCH_INTERVAL)
    except KeyboardInterrupt:
        logger.info("Engine manually stopped by user. Exiting...")
        sys.exit(0)
    except Exception as e:
        logger.critical(f"Fatal error in main execution loop: {e}")


if __name__ == "__main__":
    main()
