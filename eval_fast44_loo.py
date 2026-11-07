#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Leave-one-class-out diagnostic on the 44-D fast set: can the 44-dim features
serve as ZSL class attributes, and do they separate the LOO twin collapses?

For each held-out class k (17 runs):
  - prototypes a_c = mean of class c's train+val 44-dim (a_k is KNOWN — the ZSL
    assumption, same as the deep model always having T_k in the text bank)
  - evaluate on k's TEST singles:
    * RAW prototype  : nearest class-mean prototype in standardized 44-dim
    * LDA prototype  : LDA projection fit on the 16 SEEN classes, then nearest
                       prototype in the projected space (learned mapping)
  - collapse target = the class whose prototype wins most of k's singles

Also reproduces the full closed-set nearest-centroid confusion (sanity, ~66%).
Deep-model reference column = single-class top-1 diagonal from the RadarDINO
LOO single-confusion matrices (held-out class recognized as itself).

Usage:
  python eval_fast44_loo.py
  python eval_fast44_loo.py --fast44-dir C:/output/output/2D_8x9_0520/fast44
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.preprocessing import StandardScaler

from eval_fast44 import NAMES17, D_SET, S_SET, concat, load_all

EPS = 1e-12

# Deep model single-class top-1 diagonal (held-out recognized as itself),
# from scripts/eval_loo.py --single-confusion on fusion_dinotxt_wsp_time.
DEEP_SINGLE_TOP1 = {
    "DFTJ": 0.80, "SMSPJ": 0.86, "CSJ": 0.94, "ISCJ": 0.92, "ISRJ": 0.00,
    "MISRJ": 0.82, "ISDJ": 0.16, "C&IJ": 0.00, "AJ": 0.77, "BJ": 0.16,
    "SJ": 0.00, "NAMJ": 0.00, "NPMJ": 0.05, "NFMJ": 0.98, "PJ": 1.00,
    "NCJ": 0.90, "NPJ": 0.00,
}


def nearest_idx(X, protos):
    """Row argmin Euclidean distance to prototypes; returns (idx, dist)."""
    P = np.stack(list(protos.values()))
    d = ((X[:, None, :] - P[None, :, :]) ** 2).sum(-1)  # (N, n_cls)
    return d.argmin(1), d.min(1)


def full_prototype_cm(Xte_s, yte_int, protos, n):
    pred, _ = nearest_idx(Xte_s, protos)
    cm = np.zeros((n, n), dtype=int)
    for t, p in zip(yte_int, pred):
        cm[t, p] += 1
    return cm, np.array([cm[i, i] / cm[i].sum() if cm[i].sum() else 0.0 for i in range(n)])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fast44-dir", type=str, default="C:/output/output/2D_8x9_0520/fast44")
    ap.add_argument("--jnrs", type=str, default="0,5,10,15,20")
    args = ap.parse_args()
    jnrs = [int(x) for x in args.jnrs.split(",")]
    fast44 = Path(args.fast44_dir)

    packs, names = load_all(fast44, jnrs, ("train", "val", "test"))
    n_per = len(jnrs)
    tr_packs = packs[0:n_per]
    val_packs = packs[n_per:2 * n_per]
    te_packs = packs[2 * n_per:3 * n_per]
    Xtr, ytr, _, _ = concat(tr_packs + val_packs, None, singles_only=True)   # train+val singles
    Xte, yte, _, _ = concat(te_packs, "test", singles_only=True)              # test singles
    ytr_i = np.array([NAMES17.index(c) for c in ytr])
    yte_i = np.array([NAMES17.index(c) for c in yte])

    scaler = StandardScaler().fit(Xtr)
    Xtr_s, Xte_s = scaler.transform(Xtr), scaler.transform(Xte)

    # ---- full closed-set nearest-centroid (sanity ~66%) ----
    protos_all = {c: Xtr_s[ytr == c].mean(0) for c in NAMES17}
    cm, diag = full_prototype_cm(Xte_s, yte_i, protos_all, 17)
    print(f"[sanity] full closed-set nearest-centroid acc = {diag.mean():.3f} (expect ~0.66)")

    # ---- per-held-out: RAW prototype vs LDA projection ----
    rows = []
    n_comp = min(15, len(NAMES17) - 2)
    for k in NAMES17:
        k_i = NAMES17.index(k)
        seen = [c for c in NAMES17 if c != k]
        seen_i = np.array([NAMES17.index(c) for c in seen])
        m_tr = np.isin(ytr_i, seen_i)
        m_te = yte_i == k_i

        # raw prototype among all 17 (a_k known)
        pred_raw, _ = nearest_idx(Xte_s[m_te], protos_all)
        acc_raw = float((pred_raw == k_i).mean())
        collapse_raw = NAMES17[int(np.bincount(pred_raw, minlength=17).argmax())]

        # LDA fit on 16 seen classes (never sees k)
        lda = LinearDiscriminantAnalysis(n_components=n_comp)
        lda.fit(Xtr_s[m_tr], ytr_i[m_tr])
        protos_lda = {c: lda.transform(protos_all[c][None, :])[0] for c in NAMES17}
        Xte_lda = lda.transform(Xte_s[m_te])
        pred_lda, _ = nearest_idx(Xte_lda, protos_lda)
        acc_lda = float((pred_lda == k_i).mean())
        collapse_lda = NAMES17[int(np.bincount(pred_lda, minlength=17).argmax())]

        rows.append({
            "held_out": k, "group": "D" if k in D_SET else "S",
            "n_test": int(m_te.sum()),
            "proto_acc": round(acc_raw, 3), "proto_collapse": collapse_raw,
            "lda_acc": round(acc_lda, 3), "lda_collapse": collapse_lda,
            "deep_single_top1": DEEP_SINGLE_TOP1[k],
        })
        print(f"  {k:5s} proto={acc_raw:.3f}(->{collapse_raw}) "
              f"LDA={acc_lda:.3f}(->{collapse_lda}) deep={DEEP_SINGLE_TOP1[k]:.2f}")

    # ---- summary ----
    mean_p = float(np.mean([r["proto_acc"] for r in rows]))
    mean_l = float(np.mean([r["lda_acc"] for r in rows]))
    mean_d = float(np.mean([r["deep_single_top1"] for r in rows]))
    print(f"\nmean: proto={mean_p:.3f}  LDA={mean_l:.3f}  deep_single_top1={mean_d:.3f}")
    twin = {k: r for k, r in [(r["held_out"], r) for r in rows]
            if r["held_out"] in ("ISRJ", "C&IJ", "NAMJ", "NPMJ", "SJ", "NPJ")}
    print("twin pairs (44-dim learned mapping vs deep):")
    for pair in (("ISRJ", "C&IJ"), ("NAMJ", "NPMJ"), ("SJ", "NPJ")):
        a, b = twin[pair[0]], twin[pair[1]]
        print(f"  {pair[0]}: proto={a['proto_acc']:.2f}->{a['proto_collapse']}, "
              f"LDA={a['lda_acc']:.2f}->{a['lda_collapse']}, deep={a['deep_single_top1']:.2f} | "
              f"{pair[1]}: proto={b['proto_acc']:.2f}->{b['proto_collapse']}, "
              f"LDA={b['lda_acc']:.2f}->{b['lda_collapse']}, deep={b['deep_single_top1']:.2f}")

    out = fast44.parent / "fast44_loo_report.json"
    out.write_text(json.dumps({
        "mean": {"proto": mean_p, "lda": mean_l, "deep_single_top1": mean_d},
        "rows": rows,
        "note": "proto = class-mean prototype (raw attr space); LDA = projection fit on 16 seen classes + "
                "prototype; deep_single_top1 = RadarDINO LOO single-confusion diagonal.",
    }, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"saved -> {out}")


if __name__ == "__main__":
    main()
