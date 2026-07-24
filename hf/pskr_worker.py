#!/usr/bin/env python3
import sys
import time
import json
import os
import subprocess

# Configuration
WINDOW_MINUTES = 15
WRITE_INTERVAL = 300
MIN_SNR = -10
OUTPUT_JSON = "/var/www/html/data/hf/pskr.json"
SUMMARY_JSON = "/var/www/html/data/hf/pskr_summary.json"
IMG_OUTPUT = "/var/www/html/data/hf/pskr_heatmap.png"
TMPDIR = "/dev/shm/pskr_tmp"

NOISE_FILE = "/var/www/html/data/hf/noise_level.txt"

def get_noise_s():
    try:
        with open(NOISE_FILE, "r") as f:
            noise = f.read().strip().upper()

        for n in range(10):
            if f"S{n}" in noise:
                return n

    except Exception:
        pass

    return 3
    
def get_noise_penalty(noise_s):
    if noise_s <= 2:
        return 0
    elif noise_s <= 4:
        return 2
    elif noise_s <= 6:
        return 4
    else:
        return 6
   
    
NA_PREFIXES = {
    "AK","AL","AM","AN","AO","AP",
    "BK","BL","BM","BN","BO","BP",
    "CK","CL","CM","CN","CO","CP",
    "DK","DL","DM","DN","DO","DP",
    "EK","EL","EM","EN","EO","EP",
    "FK","FL","FM","FN","FO","FP",
    "GK","GL","GM","GN","GO","GP"
}

BANDS = ["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"]

spots = []
total_raw = 0
accepted_na = 0
last_write_time = time.time()

os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)
os.makedirs(TMPDIR, exist_ok=True)


def cleanup_old_spots():
    global spots
    now = time.time()
    keep_threshold = now - (WINDOW_MINUTES * 60)
    spots = [s for s in spots if s['ts'] > keep_threshold]


def render_heatmap_async():
    band_counts = {b: 0 for b in BANDS}
    for s in spots:
        if s['band'] in band_counts:
            band_counts[s['band']] += 1

    max_val = max(band_counts.values()) if band_counts else 1
    if max_val < 1:
        max_val = 1

    total_spots = len(spots)
    ztime = time.strftime('%d %b %Y %H:%MZ', time.gmtime())

    frame_file = os.path.join(TMPDIR, 'frame_counter')
    frame = 1
    if os.path.exists(frame_file):
        try:
            with open(frame_file) as ff:
                frame = int(ff.read().strip()) + 1
        except Exception:
            pass

    with open(frame_file, 'w') as ff:
        ff.write(str(frame))

    framestamp = f'Frame {frame} | {ztime}'
    im = 'magick' if subprocess.call('type magick', shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0 else 'convert'
    tmp_img = os.path.join(TMPDIR, 'tmp_heatmap.png')

    cmd = [im, '-size', '2200x1100', 'xc:#101010']

    try:
        proc = subprocess.Popen(cmd + [tmp_img], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        proc.wait()
        if os.path.exists(tmp_img):
            os.replace(tmp_img, IMG_OUTPUT)
    except Exception as e:
        sys.stderr.write(f'\n[Heatmap Error] Failed to generate image: {e}\n')


def write_json_file():
    cleanup_old_spots()
    now_str = time.strftime('%Y-%m-%d %H:%M:%S')

    band_counts = {b: 0 for b in BANDS}
    band_snrs = {b: [] for b in BANDS}
    aggregated = {}

    for s in spots:
        if s['band'] in band_counts:
            band_counts[s['band']] += 1
            band_snrs[s['band']].append(s['snr'])

        key = f"{s['tx']}|{s['rx']}|{s['band']}"
        if key not in aggregated:
            aggregated[key] = {'count': 0, 'total_snr': 0, 'best_snr': -999, 'last_seen': 0}

        aggregated[key]['count'] += 1
        aggregated[key]['total_snr'] += s['snr']
        if s['snr'] > aggregated[key]['best_snr']:
            aggregated[key]['best_snr'] = s['snr']
        if s['ts'] > aggregated[key]['last_seen']:
            aggregated[key]['last_seen'] = int(s['ts'])

    summary_stats = []
    for b in BANDS:
        count = band_counts[b]
        avg_snr = int(sum(band_snrs[b]) / count) if count > 0 else 0
        max_snr = max(band_snrs[b]) if count > 0 else 0
        summary_stats.append({'band': b, 'active_spots': count, 'avg_snr': avg_snr, 'max_snr': max_snr})

    with open(SUMMARY_JSON + '.tmp', 'w') as f:
        json.dump({'timestamp': now_str, 'window_minutes': WINDOW_MINUTES, 'total_spots': len(spots), 'bands': summary_stats}, f, indent=2)
    os.replace(SUMMARY_JSON + '.tmp', SUMMARY_JSON)


sys.stdin = open(sys.stdin.fileno(), mode='r', encoding='utf-8', errors='ignore', buffering=1)

buffer = ''
while True:
    chunk = sys.stdin.read(4096)
    if not chunk:
        break

    buffer += chunk

    while 'pskr/filter/v2raw/' in buffer:
        parts_split = buffer.split('pskr/filter/v2raw/', 2)
        if len(parts_split) < 3:
            break

        raw_block = 'pskr/filter/v2raw/' + parts_split[1]
        buffer = 'pskr/filter/v2raw/' + parts_split[2]

        total_raw += 1

        try:
            space_idx = raw_block.find(' ')
            if space_idx == -1:
                continue

            topic = raw_block[:space_idx]
            payload = raw_block[space_idx + 1:]

            parts = topic.split('/')
            if len(parts) < 9:
                continue

            band = parts[3]
            tx_grid = parts[7].upper()
            rx_grid = parts[8].upper()

            if tx_grid.startswith('UNK') or rx_grid.startswith('UNK'):
                continue
            if len(tx_grid) < 2 or len(rx_grid) < 2:
                continue
            if band not in BANDS:
                continue

            clean_json = payload.strip()
            data = json.loads(clean_json)

            if data.get('md') != 'FT8':
                continue

            if data.get('md') != 'FT8':
                continue

            snr = int(data.get('rp', 0))

            noise_s = get_noise_s()
            effective_snr = snr - get_noise_penalty(noise_s)

            if effective_snr < MIN_SNR:
                continue

            if tx_grid[:2] in NA_PREFIXES or rx_grid[:2] in NA_PREFIXES:
                accepted_na += 1
                spots.append({
                    'ts': time.time(),
                    'tx': tx_grid[:4],
                    'rx': rx_grid[:4],
                    'band': band,
                    'snr': snr
                })

            if time.time() - last_write_time >= WRITE_INTERVAL:
                write_json_file()
                render_heatmap_async()
                last_write_time = time.time()
            if data.get('md') != 'FT8':
                continue

            snr = int(data.get('rp', 0))

            noise_s = get_noise_s()
            effective_snr = snr - get_noise_penalty(noise_s)

            if effective_snr < MIN_SNR:
                continue

            if tx_grid[:2] in NA_PREFIXES or rx_grid[:2] in NA_PREFIXES:
                accepted_na += 1
                spots.append({
                    'ts': time.time(),
                    'tx': tx_grid[:4],
                    'rx': rx_grid[:4],
                    'band': band,
                    'snr': snr
                })

            if time.time() - last_write_time >= WRITE_INTERVAL:
                write_json_file()
                render_heatmap_async()
                last_write_time = time.time()

        except Exception:
            continue
