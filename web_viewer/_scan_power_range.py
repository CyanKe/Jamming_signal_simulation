#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Scan STFT power(dB) across all JNR/SNR folders to recommend a global power axis."""

from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path

import h5py
import numpy as np

ROOT = Path(__file__).resolve().parent.parent / "output"
MAX_SAMPLES_PER_FILE = 8
RNG = np.random.default_rng(0)


def find_stft_tasks(root: Path):
    tasks = []
    for stft in root.rglob("*_echo_stfts.mat"):
        parent = stft.parent.name
        m = re.search(r"(JNR|SNR)_([+-]?\d+)", parent)
        if not m:
            continue
        jnr = int(m.group(2))
        kind = m.group(1)  # "JNR" or "SNR"
        dataset = stft.parent.parent.name
        tasks.append((jnr, kind, dataset, stft))
    return sorted(tasks, key=lambda x: (x[0], x[1], str(x[2])))


def read_power_db_stats(path: Path, max_samples: int = MAX_SAMPLES_PER_FILE):
    with h5py.File(path, "r") as f:
        if "all_stfts" not in f:
            return None
        ds = f["all_stfts"]
        n = ds.shape[-1]
        idxs = np.linspace(0, n - 1, num=min(max_samples, n), dtype=int)
        if 0 not in idxs:
            idxs = np.unique(np.concatenate([[0], idxs]))
        chunks = []
        for i in idxs:
            s = np.array(ds[..., int(i)])
            if s.dtype.names and "real" in s.dtype.names:
                mag2 = s["real"].astype(np.float64) ** 2 + s["imag"].astype(np.float64) ** 2
            else:
                mag2 = np.abs(s.astype(np.float64)) ** 2
            pdb = 10.0 * np.log10(mag2 + np.finfo(np.float64).eps)
            chunks.append(pdb.ravel())
        allp = np.concatenate(chunks)
        if allp.size > 2_000_000:
            allp = RNG.choice(allp, size=2_000_000, replace=False)

        s0 = np.array(ds[..., 0])
        if s0.dtype.names and "real" in s0.dtype.names:
            m2 = s0["real"].astype(np.float64) ** 2 + s0["imag"].astype(np.float64) ** 2
        else:
            m2 = np.abs(s0.astype(np.float64)) ** 2
        p0 = 10.0 * np.log10(m2 + np.finfo(np.float64).eps).ravel()

        return {
            "n_file": n,
            "n_used": len(idxs),
            "min": float(allp.min()),
            "p0_1": float(np.percentile(allp, 0.1)),
            "p1": float(np.percentile(allp, 1)),
            "p5": float(np.percentile(allp, 5)),
            "p50": float(np.percentile(allp, 50)),
            "p95": float(np.percentile(allp, 95)),
            "p99": float(np.percentile(allp, 99)),
            "p99_9": float(np.percentile(allp, 99.9)),
            "max": float(allp.max()),
            "s0_p1": float(np.percentile(p0, 1)),
            "s0_max": float(p0.max()),
        }


def main():
    tasks = find_stft_tasks(ROOT)
    print(f"ROOT = {ROOT}")
    print(f"Total STFT files: {len(tasks)}")
    print("JNR set:", sorted({t[0] for t in tasks}))
    print("Datasets:", sorted({t[2] for t in tasks}))
    print()

    by_jnr = defaultdict(list)
    rows = []

    for jnr, kind, ds, path in tasks:
        rel = path.relative_to(ROOT).as_posix()
        print(f"  scanning {kind}={jnr:+d} {rel} ...", flush=True)
        try:
            st = read_power_db_stats(path)
        except Exception as e:
            print(f"    FAIL: {e}")
            continue
        if st is None:
            print("    skip: no all_stfts")
            continue
        st["jnr"] = jnr
        st["dataset"] = ds
        st["path"] = rel
        by_jnr[jnr].append(st)
        rows.append(st)
        print(
            f"    n={st['n_file']} used={st['n_used']} "
            f"p1={st['p1']:.1f} p99={st['p99']:.1f} max={st['max']:.1f} "
            f"s0_p1={st['s0_p1']:.1f} s0_max={st['s0_max']:.1f}"
        )

    if not rows:
        print("No data.")
        return

    print()
    print("=" * 100)
    print("Per-JNR aggregate (min of lows / max of highs across files at that JNR)")
    hdr = (
        f"{'JNR':>6} {'#f':>3} {'min':>7} {'p1':>7} {'p5':>7} {'p50':>7} "
        f"{'p95':>7} {'p99':>7} {'p99.9':>7} {'max':>7} "
        f"{'s0p1+3':>8} {'s0mx+3':>8}"
    )
    print(hdr)
    for jnr in sorted(by_jnr):
        items = by_jnr[jnr]

        def ag(key, fn):
            return fn([x[key] for x in items])

        print(
            f"{jnr:+6d} {len(items):3d} "
            f"{ag('min', min):7.1f} {ag('p1', min):7.1f} {ag('p5', min):7.1f} "
            f"{ag('p50', np.median):7.1f} {ag('p95', max):7.1f} {ag('p99', max):7.1f} "
            f"{ag('p99_9', max):7.1f} {ag('max', max):7.1f} "
            f"{ag('s0_p1', min) + 3:8.1f} {ag('s0_max', max) + 3:8.1f}"
        )

    print()
    print("=" * 100)
    print("GLOBAL summary")
    jnrs = sorted(by_jnr)
    print(f"  files={len(rows)}  JNR levels={jnrs}")
    print(f"  min(p1) across files     = {min(x['p1'] for x in rows):.2f} dB")
    print(f"  max(p1) across files     = {max(x['p1'] for x in rows):.2f} dB")
    print(f"  min(s0_p1)               = {min(x['s0_p1'] for x in rows):.2f} dB")
    print(f"  max(s0_p1)               = {max(x['s0_p1'] for x in rows):.2f} dB")
    print(f"  min(max)                 = {min(x['max'] for x in rows):.2f} dB")
    print(f"  max(max)                 = {max(x['max'] for x in rows):.2f} dB")
    print(f"  min(s0_max)              = {min(x['s0_max'] for x in rows):.2f} dB")
    print(f"  max(s0_max)              = {max(x['s0_max'] for x in rows):.2f} dB")
    print(f"  min(p5)                  = {min(x['p5'] for x in rows):.2f} dB")
    print(f"  max(p99.9)               = {max(x['p99_9'] for x in rows):.2f} dB")

    # Per-JNR current-style range (s0_p1+3, s0_max+3) — how much they disagree
    print()
    print("Current-style per-JNR range if using s0: [s0_p1+3, s0_max+3] (min/max over files at JNR)")
    for jnr in jnrs:
        items = by_jnr[jnr]
        lo = min(x["s0_p1"] for x in items) + 3
        hi = max(x["s0_max"] for x in items) + 3
        print(f"  JNR={jnr:+3d}: [{lo:7.1f}, {hi:7.1f}]  span={hi-lo:5.1f} dB")

    g_lo_s0 = min(x["s0_p1"] for x in rows) + 3
    g_hi_s0 = max(x["s0_max"] for x in rows) + 3
    g_lo_p1 = min(x["p1"] for x in rows) + 3
    g_hi_max = max(x["max"] for x in rows) + 3
    # noise-cut style: use higher lo (like +margin on p1) from LOWEST jnr's p1
    # signal-preserve hi: highest max across all
    lo_noise_cut = min(x["p1"] for x in rows) + 3  # same as g_lo_p1
    # more aggressive noise cut like user intent: use median of p1s + 3 or max of p1 among low JNR
    low_jnr = min(jnrs)
    high_jnr = max(jnrs)
    lo_from_low_jnr = min(x["p1"] for x in by_jnr[low_jnr]) + 3
    hi_from_high_jnr = max(x["max"] for x in by_jnr[high_jnr]) + 3
    # even: use p5 of lowest jnr as floor for less empty, or p1+5 more cut
    lo_p1_plus5 = min(x["p1"] for x in rows) + 5
    lo_p5_plus3 = min(x["p5"] for x in rows) + 3

    print()
    print("=" * 100)
    print("RECOMMENDED fixed global power_range_db options")
    print(f"  A conservative (cover all, weak noise cut):")
    print(f"     [{min(x['p1'] for x in rows):.1f}, {max(x['max'] for x in rows) + 3:.1f}]")
    print(f"  B match your style (+3 on both ends of global p1/max):")
    print(f"     [{g_lo_p1:.1f}, {g_hi_max:.1f}]")
    print(f"  C your style but from s0 only (closer to current code):")
    print(f"     [{g_lo_s0:.1f}, {g_hi_s0:.1f}]")
    print(f"  D low-JNR noise floor + high-JNR peak (good multi-JNR train):")
    print(f"     [{lo_from_low_jnr:.1f}, {hi_from_high_jnr:.1f}]  (from JNR {low_jnr:+d} p1+3 .. JNR {high_jnr:+d} max+3)")
    print(f"  E stronger noise cut (p1+5 .. max+3):")
    print(f"     [{lo_p1_plus5:.1f}, {g_hi_max:.1f}]")
    print(f"  F rounded practical defaults:")
    for lo, hi in [
        (np.floor(g_lo_p1 / 5) * 5, np.ceil(g_hi_max / 5) * 5),
        (np.floor(lo_from_low_jnr / 5) * 5, np.ceil(hi_from_high_jnr / 5) * 5),
        (np.floor(lo_p1_plus5 / 5) * 5, np.ceil(g_hi_max / 5) * 5),
    ]:
        print(f"     [{lo:.0f}, {hi:.0f}]  span={hi-lo:.0f} dB")


if __name__ == "__main__":
    main()
