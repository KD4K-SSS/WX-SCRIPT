#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time

# Configuration
WINDOW_MINUTES = 15
WRITE_INTERVAL = 300
MIN_SNR = -18
OUTPUT_JSON = "/var/www/html/data/hf/pskr.json"
SUMMARY_JSON = "/var/www/html/data/hf/pskr_summary.json"
IMG_OUTPUT = "/var/www/html/data/hf/pskr_heatmap.png"
TMPDIR = "/dev/shm/pskr_tmp"

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

spots = []
total_raw = 0
accepted_na = 0
last_write_time = time.time()
band_raw_counts = {b: 0 for b in BANDS}
band_accepted_counts = {b: 0 for b in BANDS}
band_best_raw_snr = {b: -999 for b in BANDS}
grid_raw_counts = {}

os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)
os.makedirs(TMPDIR, exist_ok=True)


def cleanup_old_spots():
    global spots
    now = time.time()
    keep_threshold = now - (WINDOW_MINUTES * 60)
    spots = [s for s in spots if s["ts"] > keep_threshold]


def render_heatmap_async():
    band_counts = {b: 0 for b in BANDS}
    for s in spots:
        if s["band"] in band_counts:
            band_counts[s["band"]] += 1

    max_val = max(band_counts.values()) if band_counts else 1
    if max_val < 1:
        max_val = 1

    total_spots = len(spots)
    ztime = time.strftime("%d %b %Y %H:%MZ", time.gmtime())

    frame_file = os.path.join(TMPDIR, "frame_counter")
    frame = 1
    if os.path.exists(frame_file):
        try:
            with open(frame_file) as ff:
                frame = int(ff.read().strip()) + 1
        except Exception:
            pass

    with open(frame_file, "w") as ff:
        ff.write(str(frame))

    framestamp = f"Frame {frame} | {ztime}"
    im = (
        "magick"
        if subprocess.call(
            "type magick",
            shell=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        == 0
        else "convert"
    )
    tmp_img = os.path.join(TMPDIR, "tmp_heatmap.png")

    cmd = [im, "-size", "2200x1100", "xc:#101010"]

    try:
        proc = subprocess.Popen(
            cmd + [tmp_img], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        proc.wait()
        if os.path.exists(tmp_img):
            os.replace(tmp_img, IMG_OUTPUT)
    except Exception as e:
        sys.stderr.write(f"\n[Heatmap Error] Failed to generate image: {e}\n")


def write_json_file():
    cleanup_old_spots()
    now_str = time.strftime("%Y-%m-%d %H:%M:%S")

    band_counts = {b: 0 for b in BANDS}
    band_snrs = {b: [] for b in BANDS}
    aggregated = {}

    for s in spots:
        if s["band"] in band_counts:
            band_counts[s["band"]] += 1
            band_snrs[s["band"]].append(s["snr"])

        key = f"{s['tx']}|{s['rx']}|{s['band']}"
        if key not in aggregated:
            aggregated[key] = {
                "tx": s["tx"],
                "rx": s["rx"],
                "band": s["band"],
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

    # Write aggregated spot details to OUTPUT_JSON
    with open(OUTPUT_JSON + ".tmp", "w") as f:
        json.dump({"timestamp": now_str, "spots": list(aggregated.values())}, f, indent=2)
    os.replace(OUTPUT_JSON + ".tmp", OUTPUT_JSON)

    # Compile Summary Data
    summary_stats = []

    for b in BANDS:
        count = band_counts[b]

        avg_snr = int(sum(band_snrs[b]) / count) if count > 0 else 0
        max_snr = max(band_snrs[b]) if count > 0 else 0

        raw = band_raw_counts[b]
        accepted = band_accepted_counts[b]

        ratio = round((accepted / raw) * 100, 1) if raw else 0

        summary_stats.append(
            {
                "band": b,
                "active_spots": count,
                "avg_snr": avg_snr,
                "max_snr": max_snr,
                "raw_ft8_spots": raw,
                "ssb_spots": accepted,
                "acceptance_ratio": ratio,
                "best_ft8_snr": band_best_raw_snr[b],
            }
        )

    with open(SUMMARY_JSON + ".tmp", "w") as f:
        json.dump(
            {
                "timestamp": now_str,
                "window_minutes": WINDOW_MINUTES,
                "total_spots": len(spots),
                "bands": summary_stats,
            },
            f,
            indent=2,
        )
    os.replace(SUMMARY_JSON + ".tmp", SUMMARY_JSON)


# Set unbuffered input stream
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

        total_raw += 1

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

            # Strictly require BOTH transmitter AND receiver to be within North America
            if tx_prefix not in NA_PREFIXES or rx_prefix not in NA_PREFIXES:
                continue

            clean_json = payload.strip()
            data = json.loads(clean_json)

            # --- MODE FILTER ---
            # Drops WSPR, JS8, CW, RTTY, etc. strictly parsing digital voice/data targets
            if data.get("md") not in ["FT8", "FT4"]:
                continue

            snr = int(data.get("rp", 0))

            # Track activity per prefix to identify sparse zones dynamically
            grid_raw_counts[tx_prefix] = grid_raw_counts.get(tx_prefix, 0) + 1
            grid_raw_counts[rx_prefix] = grid_raw_counts.get(rx_prefix, 0) + 1

            # Track all FT8/FT4 spots before filtering
            band_raw_counts[band] += 1

            if snr > band_best_raw_snr[band]:
                band_best_raw_snr[band] = snr

            # Pure Telemetry SNR Pass-Through
            effective_snr = snr

            if effective_snr < MIN_SNR:
                continue

            accepted_na += 1
            band_accepted_counts[band] += 1

            spots.append(
                {
                    "ts": time.time(),
                    "tx": tx_grid[:4],
                    "rx": rx_grid[:4],
                    "band": band,
                    "snr": snr,
                    "effective_snr": effective_snr,
                }
            )
        except Exception:
            continue

    # Periodic execution of output generation
    now = time.time()
    if now - last_write_time >= WRITE_INTERVAL:
        write_json_file()
        render_heatmap_async()
        last_write_time = now
