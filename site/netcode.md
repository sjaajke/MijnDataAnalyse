---
layout: page
title: NETCODE
permalink: /netcode/
---

# Netcode Elektriciteit (Systeemcode 2026)

MijnDataAnalyse toetst meetresultaten automatisch aan de **Netcode Elektriciteit (Systeemcode elektriciteit 2026)**, vastgesteld door de ACM (ref. ACM/UIT/666113, Staatscourant 2026, nr. 4089).

---

## Spanningskwaliteit — Artikel 8.3

In normale bedrijfsomstandigheden gelden de volgende grenswaarden:

### Frequentie

| Eis | Grenswaarde |
|---|---|
| Nominale frequentie | 50 Hz |
| Frequentie-afwijking (99,5% van een week) | 50 Hz ± 0,2 Hz |
| Frequentie-afwijking (100% van de tijd) | 50 Hz ± 0,5 Hz |

### RMS-spanning (10-minutengemiddelde, 95% van een week)

| Spanningsniveau | Grenswaarde |
|---|---|
| Laagspanning (230 V / 400 V) | ±10% van nominale spanning |
| Middenspanning | ±10% van nominale spanning |
| Hoogspanning | ±10% van nominale spanning |

### THD (Total Harmonic Distortion)

| Spanningsniveau | THD-grens |
|---|---|
| Laagspanning | ≤ 8% |
| Middenspanning | ≤ 5% |
| Hoogspanning | ≤ 3% |

### Individuele harmonischen

| Spanningsniveau | Grens |
|---|---|
| Laagspanning | ≤ 5% |
| Middenspanning | ≤ 3% |
| Hoogspanning | ≤ 2% |

### Spanningsonbalans

| Spanningsniveau | Grens |
|---|---|
| Laagspanning | ≤ 3% |
| Middenspanning | ≤ 2% |
| Hoogspanning | ≤ 2% |

### Flicker (langetermijn, Plt — 95% van een week)

| Spanningsniveau | Plt-grens |
|---|---|
| Laagspanning | ≤ 1,0 |
| Middenspanning | ≤ 1,0 |
| Hoogspanning | ≤ 0,6 |

---

## Arbeidsfactor — Artikel 8.5

- Aangeslotenen zorgen voor een arbeidsfactor van **minimaal 0,95**.
- Uitzondering kleinverbruik: artikel 2.19 (tussen **0,85 inductief en 1,0**).

---

## Flicker-emissie — Artikel 2.26 (laagspanning)

| Parameter | Waarde |
|---|---|
| ΔPst | ≤ 1,0 |
| ΔPlt | ≤ 0,8 |
| Referentie-impedantie (Zref) | 283 mΩ |
| Norm | IEC 61000-3-3:2013 |

---

## Produktie-eenheden — Frequentievereisten (Artikel 3.11)

### Frequentiebanden voor aanblijven

| Frequentieband | Maximale duur |
|---|---|
| 47,5 Hz – 48,5 Hz | 30 minuten |
| 48,5 Hz – 49,0 Hz | 30 minuten |
| 49,0 Hz – 51,0 Hz | Onbeperkt |
| 51,0 Hz – 51,5 Hz | 30 minuten |

### Frequentiegradiënt (ROCOF)

| Type eenheid | ROCOF-grens | Tijdsvenster |
|---|---|---|
| Synchrone eenheid | 1 Hz/s | 500 ms voortschrijdend |
| Power park module | 2 Hz/s | 500 ms voortschrijdend |

### Beveiligingsdrempels — Artikel 3.12

| Parameter | Drempel | Vertragingstijd |
|---|---|---|
| Onderspanning | < 80% Un | 2 seconden |
| Onderspanning | < 70% Un | 0,2 seconden |
| Overspanning | > 110% Un | 2 seconden |
| Onderfrequentie | 47,5 Hz | 2 seconden |
| Overfrequentie | 51,5 Hz | 2 seconden |

---

## Vergelijking met EN 50160

| Parameter | EN 50160 | Netcode 2026 (Art. 8.3) |
|---|---|---|
| Spanning (95% van week) | ±10% Un | ±10% Un |
| Frequentie (99,5% van week) | ±1% (±0,5 Hz) | ±0,2 Hz |
| THD laagspanning | ≤ 8% | ≤ 8% |
| Onbalans laagspanning | ≤ 2% | ≤ 3% |
| Flicker Plt | ≤ 1,0 | ≤ 1,0 |

---

## Gebruikte normen

| Norm | Toepassing |
|---|---|
| IEC 61000-3-3:2013 | Flicker / snelle spanningsveranderingen LS |
| NPR-IEC/TR 61000-3-7:2008 | Harmonische emissie fluctuerende installaties MS/HS |
| IEC 61000-4-30 | Meetmethoden spanningskwaliteit |

---

## Bron

Staatscourant 2026, nr. 4089 — *Netcode elektriciteit (Systeemcode elektriciteit 2026)*,
vastgesteld door ACM op 20-02-2026 (kenmerk ACM/UIT/666113).
