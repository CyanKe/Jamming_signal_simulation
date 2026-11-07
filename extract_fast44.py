#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Extract the 44-D fast physical-feature set from 2D_8x9_0520.

Union of the repo 22-D extractor and TAGPNet 30-D, minus:
  G1/G2 bispectrum (slow), A3 peak/mean (near A1), B5 norm-entropy (near RMS).

Reads v7.3 MAT times + STFT. Writes one npz per (JNR, split).

Usage:
  python extract_fast44.py
  python extract_fast44.py --root output/2D_8x9_0520 --splits train val test
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import h5py
import numpy as np
import pywt

FEATURE_NAMES = [
    # A time amplitude (7) — dropped A3 peak/mean
    "papr", "rms_mean", "peak_rms", "amp_var", "env_cv", "peak_pos_ratio", "zcr",
    # B higher-order / entropy (6) — dropped B5
    "skewness", "kurtosis", "shannon_entropy", "exp_entropy",
    "energy_concentration", "carrier_factor",
    # C frequency (7)
    "spec_centroid", "spec_bandwidth", "spec_flatness", "spec_peak_count",
    "spec_entropy", "spec_skew", "spec_kurt",
    # D instantaneous frequency / phase (7)
    "ifreq_mean", "ifreq_std", "ifreq_roc_std", "amp_phase_corr",
    "freq_chg_rate_ratio", "mod_bandwidth", "mod_rate",
    # E STFT (5)
    "stft_max_mean", "stft_std_mean", "stft_std_time", "stft_std_freq",
    "stft_phase_diff_std",
    # F wavelet (12)
    "wav_e_approx", "wav_e_d_coarse", "wav_e_d_mid", "wav_e_d_high",
    "wav_var", "wav_abs_mean", "wav_max",
    "wav_m2", "wav_m3", "wav_m4", "wav_scale_centroid", "wav_max_sv",
]
assert len(FEATURE_NAMES) == 44

FS = 80e6
EPS = 1e-12
WAVELET = "db4"
WAVE_LEVEL = 5
STFT_CHUNK = 256


def _complex_from_h5(ds) -> np.ndarray:
    raw = ds if isinstance(ds, np.ndarray) else ds[()]
    return np.asarray(raw["real"], dtype=np.float32) + 1j * np.asarray(
        raw["imag"], dtype=np.float32
    )


def _parse_jam(jt):
    if jt is None:
        return []
    if isinstance(jt, str):
        s = jt.strip()
        return [] if s.lower() in {"", "none", "clean", "null", "nan"} else [s]
    if isinstance(jt, (list, tuple)):
        return [str(x).strip() for x in jt if str(x).strip()]
    return [str(jt)]


def _safe_div(a, b):
    return a / np.maximum(b, EPS)


def features_from_times(sig: np.ndarray) -> np.ndarray:
    """sig: (N, T) complex64. Returns (N, 32) time+freq+phase+wavelet (A–D, F)."""
    n, t = sig.shape
    amp = np.abs(sig).astype(np.float64)
    x = np.real(sig).astype(np.float64)

    peak = amp.max(axis=1)
    mean_a = amp.mean(axis=1)
    rms = np.sqrt((amp ** 2).mean(axis=1))
    var_a = amp.var(axis=1)
    papr = _safe_div(peak, mean_a)
    rms_mean = _safe_div(rms, mean_a)
    peak_rms = _safe_div(peak, rms)
    env_cv = _safe_div(amp.std(axis=1), mean_a)
    peak_pos = amp.argmax(axis=1).astype(np.float64) / max(t - 1, 1)
    zcr = np.mean((x[:, 1:] * x[:, :-1]) < 0, axis=1)

    mu = x.mean(axis=1, keepdims=True)
    sd = x.std(axis=1)
    xc = x - mu
    skew = _safe_div((xc ** 3).mean(axis=1), sd ** 3)
    kurt = _safe_div((xc ** 4).mean(axis=1), sd ** 4) - 3.0

    shannon = np.zeros(n)
    exp_ent = np.zeros(n)
    for i in range(n):
        hist, _ = np.histogram(x[i], bins=min(100, max(t // 10, 2)), density=False)
        p = hist.astype(np.float64)
        p = p / max(p.sum(), EPS)
        p = p[p > 0]
        shannon[i] = -(p * np.log2(p)).sum()
        exp_ent[i] = -(p * np.exp(p - 1.0)).sum()

    spec = np.abs(np.fft.rfft(x, axis=1))
    nfft = spec.shape[1]
    freqs = np.fft.rfftfreq(t, d=1.0 / FS)
    power = spec ** 2
    p_norm = _safe_div(power, power.sum(axis=1, keepdims=True))
    centroid = (p_norm * freqs).sum(axis=1)
    bandwidth = np.sqrt(((freqs[None, :] - centroid[:, None]) ** 2 * p_norm).sum(axis=1))
    geo = np.exp(np.mean(np.log(spec + EPS), axis=1))
    flatness = _safe_div(geo, spec.mean(axis=1))
    spec_ent = -(p_norm * np.log(p_norm + EPS)).sum(axis=1)
    herfindahl = (p_norm ** 2).sum(axis=1)

    peak_idx = spec.argmax(axis=1)
    carrier = np.zeros(n)
    n_peaks = np.zeros(n)
    thr = spec.max(axis=1, keepdims=True) * 0.3
    for i in range(n):
        lo = max(0, int(peak_idx[i]) - 5)
        hi = min(nfft, int(peak_idx[i]) + 6)
        carrier[i] = power[i, lo:hi].sum() / max(power[i].sum(), EPS)
        s = spec[i]
        local = (s[1:-1] > s[:-2]) & (s[1:-1] > s[2:]) & (s[1:-1] > thr[i, 0])
        n_peaks[i] = local.sum()

    sm = spec.mean(axis=1, keepdims=True)
    ss = spec.std(axis=1)
    spec_skew = _safe_div(((spec - sm) ** 3).mean(axis=1), ss ** 3)
    spec_kurt = _safe_div(((spec - sm) ** 4).mean(axis=1), ss ** 4) - 3.0

    phase = np.unwrap(np.angle(sig), axis=1)
    inst_f = np.diff(phase, axis=1) * FS / (2.0 * np.pi)
    ifreq_mean = inst_f.mean(axis=1)
    ifreq_std = inst_f.std(axis=1)
    roc = np.diff(inst_f, axis=1)
    ifreq_roc_std = roc.std(axis=1)
    ph_c = phase - phase.mean(axis=1, keepdims=True)
    am_c = amp - amp.mean(axis=1, keepdims=True)
    amp_phase_corr = _safe_div(
        (am_c * ph_c).mean(axis=1), am_c.std(axis=1) * ph_c.std(axis=1)
    )
    abs_mean_f = np.abs(ifreq_mean)
    freq_chg_rate_ratio = _safe_div(ifreq_roc_std, abs_mean_f)
    mod_bw = inst_f.max(axis=1) - inst_f.min(axis=1)
    mod_rate = _safe_div(ifreq_std, np.abs(inst_f).mean(axis=1))

    wav = _wavelet_block(x)

    cols = [
        papr, rms_mean, peak_rms, var_a, env_cv, peak_pos, zcr,
        skew, kurt, shannon, exp_ent, herfindahl, carrier,
        centroid, bandwidth, flatness, n_peaks, spec_ent, spec_skew, spec_kurt,
        ifreq_mean, ifreq_std, ifreq_roc_std, amp_phase_corr,
        freq_chg_rate_ratio, mod_bw, mod_rate,
    ]
    # 27 + 12 wavelet = 39; STFT 5 added later → 44
    return np.column_stack(cols + [wav])


def _wavelet_block(x: np.ndarray) -> np.ndarray:
    """(N, T) -> (N, 12) db4 level-5 features."""
    n = x.shape[0]
    out = np.zeros((n, 12), dtype=np.float64)
    for i in range(n):
        max_level = pywt.dwt_max_level(x.shape[1], WAVELET)
        level = min(WAVE_LEVEL, max_level)
        coeffs = pywt.wavedec(x[i], WAVELET, level=level)
        # coeffs: [cA, cD_level, ..., cD1]
        approx = coeffs[0]
        details = coeffs[1:]  # coarse → fine
        energies = np.array([np.sum(c ** 2) for c in coeffs], dtype=np.float64)
        tot = energies.sum() + EPS
        # F1 approx; F2 coarsest detail; F3 mid details; F4 finest 1–2
        e_approx = energies[0] / tot
        e_coarse = energies[1] / tot if len(energies) > 1 else 0.0
        if len(energies) >= 4:
            e_mid = energies[2:-2].sum() / tot
            e_high = energies[-2:].sum() / tot
        elif len(energies) == 3:
            e_mid = energies[2] / tot
            e_high = 0.0
        else:
            e_mid = 0.0
            e_high = 0.0

        all_d = np.concatenate(details) if details else approx
        mu = all_d.mean()
        var = all_d.var()
        m2 = np.mean((all_d - mu) ** 2)
        m3 = np.mean((all_d - mu) ** 3)
        m4 = np.mean((all_d - mu) ** 4)

        det_e = np.array([np.sum(c ** 2) for c in details], dtype=np.float64)
        if det_e.sum() > 0:
            scales = np.arange(1, len(details) + 1, dtype=np.float64)
            centroid = (scales * det_e).sum() / det_e.sum()
        else:
            centroid = 0.0

        max_len = max(c.size for c in details) if details else 1
        mat = np.zeros((max_len, max(len(details), 1)), dtype=np.float64)
        for j, c in enumerate(details):
            mat[: c.size, j] = c
        try:
            sv = np.linalg.svd(mat, compute_uv=False)
            max_sv = float(sv[0]) if sv.size else 0.0
        except np.linalg.LinAlgError:
            max_sv = 0.0

        out[i] = [
            e_approx, e_coarse, e_mid, e_high,
            var, np.mean(np.abs(all_d)), np.max(np.abs(all_d)),
            m2, m3, m4, centroid, max_sv,
        ]
    return out


def features_from_stft(stft: np.ndarray) -> np.ndarray:
    """stft: (N, Tfr, F) complex. Returns (N, 5)."""
    mag = np.abs(stft)
    mean = mag.mean(axis=(1, 2))
    mx = mag.max(axis=(1, 2))
    std = mag.std(axis=(1, 2))
    # axis1 = time frames (225), axis2 = frequency (224)
    std_time = mag.std(axis=1).mean(axis=1)
    std_freq = mag.std(axis=2).mean(axis=1)
    phase = np.angle(stft)
    dphi = np.diff(np.unwrap(phase, axis=1), axis=1)
    phase_diff_std = dphi.std(axis=(1, 2))
    return np.column_stack([
        _safe_div(mx, mean),
        _safe_div(std, mean),
        std_time,
        std_freq,
        phase_diff_std,
    ])


def extract_split(times_path: Path, stft_path: Path, meta_path: Path, jnr: int):
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    with h5py.File(times_path, "r") as f:
        times = _complex_from_h5(f["all_times"])  # (T, N)
    times = np.ascontiguousarray(times.T)  # (N, T)
    n = times.shape[0]
    if len(meta) != n:
        n = min(n, len(meta))
        times = times[:n]
        meta = meta[:n]

    print(f"    times {times.shape} → A–D+F", flush=True)
    feat_tfw = features_from_times(times)
    del times

    print(f"    stft chunked → E", flush=True)
    stft_feat = np.zeros((n, 5), dtype=np.float64)
    with h5py.File(stft_path, "r") as f:
        ds = f["all_stfts"]
        for sl in range(0, n, STFT_CHUNK):
            sr = min(n, sl + STFT_CHUNK)
            chunk = _complex_from_h5(ds[:, :, sl:sr])  # (Tfr, F, B)
            chunk = np.transpose(chunk, (2, 0, 1))  # (B, Tfr, F)
            stft_feat[sl:sr] = features_from_stft(chunk)

    X = np.concatenate([feat_tfw, stft_feat], axis=1)
    assert X.shape[1] == 44, X.shape

    labels, njam = [], []
    for m in meta:
        jt = _parse_jam(m.get("jam_types", []))
        labels.append("+".join(jt) if jt else "CLEAN")
        njam.append(len(jt))

    return {
        "X": X.astype(np.float32),
        "label": np.array(labels),
        "njam": np.array(njam, dtype=np.int16),
        "jnr": np.full(n, int(jnr), dtype=np.int16),
        "sample_idx": np.array([m.get("sample_idx", i) for i, m in enumerate(meta)]),
        "feature_names": np.array(FEATURE_NAMES),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent / "output" / "2D_8x9_0520",
    )
    ap.add_argument("--splits", nargs="+", default=["train", "val", "test"])
    ap.add_argument("--jnrs", nargs="+", type=int, default=[0, 5, 10, 15, 20])
    args = ap.parse_args()

    out_dir = args.root / "fast44"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "feature_names.json").write_text(
        json.dumps(FEATURE_NAMES, indent=2), encoding="utf-8"
    )

    for jnr in args.jnrs:
        jdir = args.root / f"JNR_+{jnr}"
        if not jdir.is_dir():
            print(f"skip missing {jdir}")
            continue
        for split in args.splits:
            dest = out_dir / f"{split}_JNR{jnr}.npz"
            if dest.exists():
                print(f"exists {dest.name}, skip")
                continue
            times_p = jdir / f"{split}_echo_times.mat"
            stft_p = jdir / f"{split}_echo_stfts.mat"
            meta_p = jdir / f"{split}_echo_metadata.json"
            if not (times_p.exists() and stft_p.exists() and meta_p.exists()):
                print(f"missing files for {split} JNR={jnr}")
                continue
            print(f"=== {split} JNR=+{jnr} ===", flush=True)
            pack = extract_split(times_p, stft_p, meta_p, jnr)
            np.savez_compressed(dest, **pack)
            print(f"    saved {dest.name} X={pack['X'].shape}", flush=True)

    print("done", out_dir)


if __name__ == "__main__":
    main()
