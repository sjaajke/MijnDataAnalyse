---
layout: home
title: MijnDataAnalyse
---

# MijnDataAnalyse

**Power quality analysis** for A-Eberle PQBox measurements,
compliant with **EN 50160** and **IEC 61000**.

---

## Download

<div class="download-buttons">

  <a href="https://github.com/sjaajke/MijnDataAnalyse/releases/latest" class="btn btn-windows">
    ⬇ Windows (.exe)
  </a>

  <a href="https://github.com/sjaajke/MijnDataAnalyse/releases/latest" class="btn btn-macos">
    ⬇ macOS (.dmg)
  </a>

  <a href="#" class="btn btn-android">
    ▶ Google Play Store
    <span class="badge">Coming soon</span>
  </a>

  <a href="#" class="btn btn-ios">
    ▶ Apple App Store
    <span class="badge">Coming soon</span>
  </a>

</div>

---

## What does it do?

MijnDataAnalyse reads and analyses **PQF measurement files** from the A-Eberle PQBox 300 power quality analyser. It gives you instant insight into:

- **Voltage** — RMS values, min/max envelopes, deviations from nominal
- **Current** — RMS per phase, load profile over time
- **Frequency** — deviation from 50 Hz nominal
- **Power** — active, reactive and apparent power, cos φ
- **Harmonics** — THD per phase, harmonic spectrum
- **EN 50160 compliance** — automatic pass/fail assessment
- **Events** — voltage dips, swells and transients
- **Comparisons** — overlay multiple measurement sessions

---

## Features

### EN 50160 Compliance Report
Automatic assessment of your measurement against EN 50160 power quality standard. Export results as a PDF report.

### Voltage Analysis
Time-series charts of RMS voltage per phase, including min/max envelopes. Spot deviations from the 230 V nominal instantly.

### Current & Load Analysis
Per-phase current profiles over the full recording period. Includes cable current capacity check.

### Frequency Analysis
Deviation from 50 Hz plotted over time. EN 50160 limits shown for reference.

### Harmonic Analysis
THD values and individual harmonic spectra per phase. Identify sources of harmonic distortion.

### Power & cos φ
Active, reactive and apparent power trends. Power factor (cos φ) per phase.

### Event Log
Overview of all recorded voltage events — dips, swells and transients — with timestamps and severity.

### Session Comparison
Load two measurement sessions side by side to compare before/after or different locations.

### PQBox Download
Connect directly to a PQBox 300 over the network to download measurement files without a PC tool.

### PDF Reports
Export any analysis view as a professional PDF report.

---

## Supported File Types

| File | Content |
|---|---|
| cyc.pqf | Per-cycle aggregated averages (~25-min blocks) |
| cyc10s.pqf | 10-second averages |
| cyc2h.pqf | 2-hour averages (EN 50160 reference) |
| event.pqf | Voltage events (dips, swells, transients) |
| recA.pqf | Waveform recordings |
| cycHF.pqf | High-frequency data |
| cycP.pqf | Power measurements |

---

## Standards

| Standard | Description |
|---|---|
| EN 50160 | Voltage characteristics of electricity supplied by public networks |
| IEC 61000-2-2 | Compatibility levels for low-voltage networks |
| IEC 61000-4-30 | Power quality measurement methods |

---

## Platforms

| Platform | Status |
|---|---|
| macOS | Available — [download here](https://github.com/sjaajke/MijnDataAnalyse/releases/latest) |
| Windows 10/11 | Available — [download here](https://github.com/sjaajke/MijnDataAnalyse/releases/latest) |
| Android | Coming soon |
| iOS / iPadOS | Coming soon |

---

## License

MijnDataAnalyse is open source software, licensed under the
[GNU General Public License v3.0](https://github.com/sjaajke/MijnDataAnalyse/blob/main/LICENSE).

© 2026 Jay Smeekes
