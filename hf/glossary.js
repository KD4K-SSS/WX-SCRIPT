document.addEventListener("DOMContentLoaded", function() {
    // 1. Inject the CSS styles cleanly using a standard style tag
    const style = document.createElement('style');
    style.textContent = `
        .legend-trigger { color: var(--cyan); text-decoration: none; font-size: 0.9rem; border: 1px solid var(--border-color); padding: 4px 10px; border-radius: 4px; background: var(--card-bg); transition: 0.2s; cursor: pointer; display: inline-block; margin-top: 10px; }
        .legend-trigger:hover { background: #1f242c; border-color: var(--cyan); }
        .lightbox-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0, 0, 0, 0.8); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; opacity: 0; pointer-events: none; transition: opacity 0.3s ease; z-index: 9999; }
        .lightbox-overlay:target { opacity: 1; pointer-events: auto; }
        .lightbox-content { background: var(--card-bg); border: 1px solid var(--border-color); padding: 25px; border-radius: 8px; max-width: 650px; width: 90%; max-height: 80vh; overflow-y: auto; position: relative; box-shadow: 0 10px 25px rgba(0,0,0,0.5); text-align: left; }
        .lightbox-close { position: absolute; top: 15px; right: 20px; color: var(--text-dim); text-decoration: none; font-size: 1.8rem; line-height: 1; transition: 0.2s; }
        .lightbox-close:hover { color: var(--red); }
        .legend-item { font-size: 0.9rem; line-height: 1.5; margin-bottom: 12px; border-bottom: 1px dashed #21262d; padding-bottom: 12px; color: var(--text-main); }
        .legend-item strong { color: var(--cyan); display: inline-block; margin-right: 4px; }
        .legend-item:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
    `;
    document.head.appendChild(style);

    // 2. Inject the clickable Link into the Header
    const header = document.querySelector('header');
    if (header) {
        const linkDiv = document.createElement('div');
        linkDiv.innerHTML = '<a href="#legend-lightbox" class="legend-trigger">&#x2139; Documentation & Field Glossary</a>';
        header.appendChild(linkDiv);
    }

    // 3. Inject the Lightbox HTML Container at the bottom of the body
    const modal = document.createElement('div');
    modal.id = 'legend-lightbox';
    modal.className = 'lightbox-overlay';
    modal.innerHTML = `
        <div class="lightbox-content">
            <a href="#" class="lightbox-close">&times;</a>
            <h2 style="margin-top: 0; border-left: none; padding-left: 0; color: var(--cyan); font-size: 1.4rem;">Dashboard Telemetry Glossary</h2>
            <hr style="border: 0; border-top: 1px solid var(--border-color); margin-bottom: 15px;">
            <div class="legend-item"><strong>Solar Flux Index (SFI):</strong> Measures solar radio emissions at 10.7 cm. Higher numbers (140+) show robust F-layer ionization, boosting long-distance HF paths.</div>
            <div class="legend-item"><strong>Sunspot Number (SSN):</strong> Tracks the count of active dark magnetic areas on the sun. Higher counts correlate with stronger SFI output.</div>
            <div class="legend-item"><strong>X-Ray Flare Level:</strong> Logs emissions on a logarithmic baseline (A, B, C, M, X). Background values past M or X indicate powerful flares that can cause sudden day-side HF blackouts.</div>
            <div class="legend-item"><strong>Solar Wind Speed:</strong> The velocity of plasma streaming out from the sun. Baseline is 300–400 km/s; spikes past 500 km/s indicate coronal storms that disrupt paths.</div>
            <div class="legend-item"><strong>Planetary K-Index:</strong> A 3-hour global geomagnetic tracker scaled 0–9. Stable paths need a K-index &le; 2; 5+ marks active storms causing heavy signal fade.</div>
            <div class="legend-item"><strong>A-Index:</strong> The linear daily average of geomagnetic noise. Low storm risk profiles stay below 10; values above 20 warn of unstable conditions.</div>
            <div class="legend-item"><strong>Bz Magnetic Field:</strong> The polar vector of the Interplanetary Magnetic Field. Positive is stable; a negative direction (-) pulls solar energy into our atmosphere, disrupting signals.</div>
            <div class="legend-item"><strong>Signal Noise Level:</strong> Tracks baseline background RF noise (S0–S9+). Quieter values (S0–S2) enable weak signals to surface cleanly.</div>
            <div class="legend-item"><strong>MUF (Maximum Usable Frequency):</strong> The peak frequency limit where local ionosondes detect refracting skywave returns over a standard 3,000 km baseline path.</div>
        </div>
    `;
    document.body.appendChild(modal);
});
