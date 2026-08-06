#!/usr/bin/env python3
import json
import math
import os
import sys
import time

# Configuration Parameters
WINDOW_MINUTES = 15      # Keep a rolling 15-minute window of live spots
WRITE_INTERVAL = 300     # Write updated JSON output every 5 minutes (300 sec)
MIN_SNR = -10            # Minimum acceptable SNR threshold (dB)

# Output JSON file path
OUTPUT_JSON = "/var/www/html/data/hf/pskr_engine.json"

# Set of valid North American Maidenhead Field Prefixes
NA_PREFIXES = {
    "AK", "AL", "AM", "AN", "AO", "AP",
    "BK", "BL", "BM", "BN", "BO", "BP",
    "CK", "CL", "CM", "CN", "CO", "CP",
    "DK", "DL", "DM", "DN", "DO", "DP",
    "EK", "EL", "EM", "EN", "EO", "EP",
    "FK", "FL", "FM", "FN", "FO", "FP",
    "GK", "GL", "GM", "GN", "GO", "GP",
}

BANDS = ["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]

# Frequency mapping (MHz) for MUF & band classification
BAND_MHZ = {
    "160m": 1.8,  "80m": 3.5,  "40m": 7.0,  "30m": 10.1,
    "20m": 14.0,  "17m": 18.1, "15m": 21.0, "12m": 24.9,
    "10m": 28.0,  "6m": 50.0
}

spots = []
last_write_time = time.time()

os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)


def grid_to_latlon(grid):
    """
    Converts Maidenhead Grid Locator (2, 4, or 6 characters) 
    to precise Latitude/Longitude Centroids.
    """
    if not grid or len(grid) < 2:
        return None
    grid = grid.upper().strip()
    
    lon = (ord(grid[0]) - 65) * 20 - 180
    lat = (ord(grid[1]) - 65) * 10 - 90
    dlat, dlon = 10.0, 20.0

    # 4-Character Grid Refinement (e.g., EM73)
    if len(grid) >= 4 and grid[2].isdigit() and grid[3].isdigit():
        lon += int(grid[2]) * 2
        lat += int(grid[3]) * 1
        dlat, dlon = 1.0, 2.0

    # 6-Character Grid Refinement (e.g., EM73ab)
    if len(grid) >= 6 and grid[4].isalpha() and grid[5].isalpha():
        lon += (ord(grid[4]) - 65) * (2.0 / 24.0)
        lat += (ord(grid[5]) - 65) * (1.0 / 24.0)
        dlat, dlon = (1.0 / 24.0), (2.0 / 24.0)

    return round(lat + (dlat / 2.0), 4), round(lon + (dlon / 2.0), 4)


def calculate_path_metrics(lat1, lon1, lat2, lon2):
    """
    Calculates Great-Circle Distance (km) and the Ionospheric 
    Refraction Midpoint (Lat/Lon) between two stations.
    """
    R = 6371.0  # Earth's mean radius in kilometers
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    # Haversine Distance Calculation
    a = math.sin(delta_phi / 2.0)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0)**2
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    dist_km = R * c

    # Spherical Midpoint Calculation (F2 Layer Reflection Point)
    Bx = math.cos(phi2) * math.cos(delta_lambda)
    By = math.cos(phi2) * math.sin(delta_lambda)
    mid_lat = math.atan2(math.sin(phi1) + math.sin(phi2),
                         math.sqrt((math.cos(phi1) + Bx)**2 + By**2))
    mid_lon = math.radians(lon1) + math.atan2(By, math.cos(phi1) + Bx)

    return round(dist_km, 1), round(math.degrees(mid_lat), 4), round(math.degrees(mid_lon), 4)


def cleanup_old_spots():
    """Removes spots older than the defined WINDOW_MINUTES."""
    global spots
    now = time.time()
    keep_threshold = now - (WINDOW_MINUTES * 60)
    spots = [s for s in spots if s["ts"] > keep_threshold]


def write_json_file():
    """Aggregates active paths and writes output to JSON atomically."""
    cleanup_old_spots()
    now_str = time.strftime("%Y-%m-%d %H:%M:%S")
    aggregated = {}

    for s in spots:
        key = f"{s['tx']}|{s['rx']}|{s['band']}"
        if key not in aggregated:
            aggregated[key] = {
                "tx": s["tx"],
                "rx": s["rx"],
                "tx_coords": [s["tx_lat"], s["tx_lon"]],
                "rx_coords": [s["rx_lat"], s["rx_lon"]],
                "midpoint": [s["mid_lat"], s["mid_lon"]],
                "distance_km": s["dist_km"],
                "band": s["band"],
                "freq_mhz": BAND_MHZ.get(s["band"], 0.0),
                "count": 0,
                "total_snr": 0,
                "best_snr": -999,
                "last_seen": 0,
            }

        aggregated[key]["count"] += 1
        aggregated[key]["total_snr"] += s["snr"]
        if s["snr"] > aggregated[key]["best_snr"]:
            aggregated[key]["best_snr"] = s["snr"]
        if s["ts"] > aggregated[key]["last_seen"]:
            aggregated[key]["last_seen"] = int(s["ts"])

    # Write output to temporary file first, then replace atomically to prevent file locks
    with open(OUTPUT_JSON + ".tmp", "w") as f:
        json.dump({
            "timestamp": now_str,
            "window_minutes": WINDOW_MINUTES,
            "total_paths": len(aggregated),
            "spots": list(aggregated.values())
        }, f, indent=2)
    os.replace(OUTPUT_JSON + ".tmp", OUTPUT_JSON)


# Set unbuffered input stream for continuous streaming
sys.stdin = open(
    sys.stdin.fileno(), mode="r", encoding="utf-8", errors="ignore", buffering=1
)

buffer = ""
while True:
    chunk = sys.stdin.read(4096)
    if not chunk:
        break

    buffer += chunk

    while "pskr/filter/v2raw/" in buffer:
        parts_split = buffer.split("pskr/filter/v2raw/", 2)
        if len(parts_split) < 3:
            break

        raw_block = "pskr/filter/v2raw/" + parts_split[1]
        buffer = "pskr/filter/v2raw/" + parts_split[2]

        try:
            space_idx = raw_block.find(" ")
            if space_idx == -1:
                continue

            topic = raw_block[:space_idx]
            payload = raw_block[space_idx + 1 :]

            parts = topic.split("/")
            if len(parts) < 9:
                continue

            band = parts[3]
            tx_grid = parts[7].upper()
            rx_grid = parts[8].upper()

            if tx_grid.startswith("UNK") or rx_grid.startswith("UNK"):
                continue
            if len(tx_grid) < 2 or len(rx_grid) < 2:
                continue
            if band not in BANDS:
                continue

            tx_prefix = tx_grid[:2]
            rx_prefix = rx_grid[:2]

            # Enforce North American boundaries
            if tx_prefix not in NA_PREFIXES or rx_prefix not in NA_PREFIXES:
                continue

            clean_json = payload.strip()
            data = json.loads(clean_json)

            # Restrict to FT8 and FT4 modes
            if data.get("md") not in ["FT8", "FT4"]:
                continue

            snr = int(data.get("rp", 0))
            if snr < MIN_SNR:
                continue

            # Resolve coordinates
            tx_coords = grid_to_latlon(tx_grid)
            rx_coords = grid_to_latlon(rx_grid)

            if not tx_coords or not rx_coords:
                continue

            # Compute Great-Circle distance and ionospheric reflection midpoint
            dist_km, mid_lat, mid_lon = calculate_path_metrics(
                tx_coords[0], tx_coords[1], rx_coords[0], rx_coords[1]
            )

            spots.append({
                "ts": time.time(),
                "tx": tx_grid[:4],
                "rx": rx_grid[:4],
                "tx_lat": tx_coords[0],
                "tx_lon": tx_coords[1],
                "rx_lat": rx_coords[0],
                "rx_lon": rx_coords[1],
                "mid_lat": mid_lat,
                "mid_lon": mid_lon,
                "dist_km": dist_km,
                "band": band,
                "snr": snr,
            })
        except Exception:
            continue

    now = time.time()
    if now - last_write_time >= WRITE_INTERVAL:
        write_json_file()
        last_write_time = now
