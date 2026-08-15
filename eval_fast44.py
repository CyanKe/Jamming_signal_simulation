#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Train small models on the 44-D fast set and report separability.

Protocols
  official   17-way singles, official train/val/test across JNR
  pooled     17-way singles, stratified 70/30 on all singles (feature-space capacity)
  presence   single vs combo on official test (routing-relevant)

Usage:
  python eval_fast44.py
  python eval_fast44.py --fast44-dir output/2D_8x9_0520/fast44
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score
from sklearn.model_selection import train_test_split
from sklearn.neighbors import NearestCentroid
from sklearn.neural_network import MLPClassifier
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import LinearSVC

NAMES17 = [
    "DFTJ", "SMSPJ", "CSJ", "ISCJ", "ISRJ", "MISRJ", "ISDJ", "C&IJ",
    "AJ", "BJ", "SJ", "NAMJ", "NPMJ", "NFMJ", "PJ", "NCJ", "NPJ",
]
D_SET = set(NAMES17[:8])
S_SET = set(NAMES17[8:])


def load_all(fast44_dir: Path, jnrs, splits):
    packs = []
    for split in splits:
        for jnr in jnrs:
            p = fast44_dir / f"{split}_JNR{jnr}.npz"
            if not p.exists():
                raise FileNotFoundError(p)
            z = np.load(p, allow_pickle=True)
            packs.append({
                "split": split,
                "X": z["X"].astype(np.float64),
                "label": z["label"].astype(str),
                "njam": z["njam"].astype(int),
                "jnr": z["jnr"].astype(int),
            })
    names = list(np.load(fast44_dir / f"{splits[0]}_JNR{jnrs[0]}.npz")["feature_names"])
    return packs, names


def singles_mask(label, njam):
    return (njam == 1) & np.isin(label, NAMES17)


def encode(y, classes=None):
    classes = list(classes) if classes is not None else NAMES17
    idx = {c: i for i, c in enumerate(classes)}
    return np.array([idx[v] for v in y], dtype=int), classes


def fit_models():
    return {
        "nearest_centroid": make_pipeline(
            StandardScaler(), NearestCentroid()
        ),
        "logreg": make_pipeline(
            StandardScaler(),
            LogisticRegression(max_iter=400),
        ),
        "linear_svm": make_pipeline(
            StandardScaler(),
            LinearSVC(max_iter=4000, dual=False),
        ),
        "rf": RandomForestClassifier(
            n_estimators=300, max_depth=16, min_samples_leaf=2,
            n_jobs=-1, random_state=0,
        ),
        "mlp44_64_32": make_pipeline(
            StandardScaler(),
            MLPClassifier(
                hidden_layer_sizes=(64, 32),
                activation="relu",
                alpha=1e-3,
                max_iter=200,
                early_stopping=True,
                random_state=0,
            ),
        ),
    }


def eval_split(model, Xtr, ytr, Xte, yte, classes):
    model.fit(Xtr, ytr)
    pred = model.predict(Xte)
    acc = float(accuracy_score(yte, pred))
    f1 = float(f1_score(yte, pred, average="macro", zero_division=0))
    per = {}
    for i, c in enumerate(classes):
        m = yte == i
        per[c] = float((pred[m] == i).mean()) if m.any() else float("nan")
    # group: D-only vs S-only labels
    d_idx = {c: i for i, c in enumerate(classes) if c in D_SET}
    s_idx = {c: i for i, c in enumerate(classes) if c in S_SET}
    if d_idx and s_idx:
        y_g = np.array(["D" if classes[i] in D_SET else "S" for i in yte])
        p_g = np.array(["D" if classes[i] in D_SET else "S" for i in pred])
        group_acc = float((y_g == p_g).mean())
    else:
        group_acc = float("nan")
    return {"acc": acc, "macro_f1": f1, "group_DS_acc": group_acc,
            "per_class": per, "pred": pred, "yte": yte}


def plot_confusion(cm, classes, title, path):
    fig, ax = plt.subplots(figsize=(8.2, 7.2))
    cmn = cm / np.maximum(cm.sum(1, keepdims=True), 1)
    im = ax.imshow(cmn, vmin=0, vmax=1, cmap="Blues")
    ax.set_xticks(range(len(classes)))
    ax.set_yticks(range(len(classes)))
    ax.set_xticklabels(classes, rotation=90, fontsize=7)
    ax.set_yticklabels(classes, fontsize=7)
    ax.set_xlabel("predicted")
    ax.set_ylabel("true")
    ax.set_title(title)
    fig.colorbar(im, ax=ax, fraction=0.046)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def plot_tsne(X, y, classes, title, path, n_max=2500):
    from sklearn.manifold import TSNE
    rng = np.random.RandomState(0)
    if len(X) > n_max:
        # stratified subsample
        keep = []
        for i in range(len(classes)):
            idx = np.where(y == i)[0]
            k = max(1, int(round(n_max * len(idx) / len(y))))
            keep.append(rng.choice(idx, size=min(k, len(idx)), replace=False))
        keep = np.concatenate(keep)
        X, y = X[keep], y[keep]
    Z = StandardScaler().fit_transform(np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0))
    emb = TSNE(n_components=2, perplexity=30, init="pca",
               learning_rate="auto", random_state=0).fit_transform(Z)
    fig, ax = plt.subplots(figsize=(7.2, 6.0))
    cmap = plt.colormaps["tab20"].resampled(len(classes))
    for i, c in enumerate(classes):
        m = y == i
        ax.scatter(emb[m, 0], emb[m, 1], s=8, alpha=0.7,
                   color=cmap(i), label=c)
    ax.legend(fontsize=6, markerscale=1.6, ncol=2, loc="best", frameon=False)
    ax.set_title(title)
    ax.set_xticks([])
    ax.set_yticks([])
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def plot_bars(per_class, title, path):
    keys = list(per_class.keys())
    vals = [per_class[k] for k in keys]
    colors = ["#2563EB" if k in D_SET else "#D97706" for k in keys]
    fig, ax = plt.subplots(figsize=(8.0, 3.4))
    ax.bar(keys, vals, color=colors)
    ax.set_ylim(0, 1.05)
    ax.set_ylabel("recall")
    ax.set_title(title)
    ax.tick_params(axis="x", rotation=90, labelsize=7)
    ax.axhline(1 / len(keys), color="0.5", ls="--", lw=0.8, label="chance")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def concat(packs, split=None, singles_only=False):
    sel = [p for p in packs if split is None or p["split"] == split]
    X = np.concatenate([p["X"] for p in sel], 0)
    label = np.concatenate([p["label"] for p in sel], 0)
    njam = np.concatenate([p["njam"] for p in sel], 0)
    jnr = np.concatenate([p["jnr"] for p in sel], 0)
    X = np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0)
    if singles_only:
        m = singles_mask(label, njam)
        return X[m], label[m], njam[m], jnr[m]
    return X, label, njam, jnr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--fast44-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "output" / "2D_8x9_0520" / "fast44",
    )
    ap.add_argument("--jnrs", nargs="+", type=int, default=[0, 5, 10, 15, 20])
    args = ap.parse_args()
    out = args.fast44_dir
    fig_dir = out / "eval_plots"
    fig_dir.mkdir(parents=True, exist_ok=True)

    packs, feat_names = load_all(out, args.jnrs, ["train", "val", "test"])
    report = {"feature_names": feat_names, "jnrs": args.jnrs, "protocols": {}}

    # ---- official 17-way singles ----
    Xtr, ytr_s, _, _ = concat(packs, "train", singles_only=True)
    Xva, yva_s, _, _ = concat(packs, "val", singles_only=True)
    Xte, yte_s, _, _ = concat(packs, "test", singles_only=True)
    ytr, classes = encode(ytr_s)
    yva, _ = encode(yva_s)
    yte, _ = encode(yte_s)
    Xtr_all = np.concatenate([Xtr, Xva], 0)
    ytr_all = np.concatenate([ytr, yva], 0)
    print(f"official singles  train+val={len(ytr_all)}  test={len(yte)}")

    official = {}
    models = fit_models()
    best_name, best_acc = None, -1
    best_pred = None
    for name, clf in models.items():
        r = eval_split(clf, Xtr_all, ytr_all, Xte, yte, classes)
        official[name] = {k: r[k] for k in ("acc", "macro_f1", "group_DS_acc", "per_class")}
        print(f"  official/{name:16s}  acc={r['acc']:.3f}  f1={r['macro_f1']:.3f}  "
              f"D/S={r['group_DS_acc']:.3f}")
        if r["acc"] > best_acc:
            best_acc, best_name, best_pred = r["acc"], name, r["pred"]
    report["protocols"]["official_17way"] = {
        "n_train": int(len(ytr_all)), "n_test": int(len(yte)),
        "chance": 1 / 17, "models": official, "best": best_name,
    }
    cm = confusion_matrix(yte, best_pred, labels=list(range(17)))
    plot_confusion(cm, classes, f"Official 17-way  {best_name}  acc={best_acc:.3f}",
                   fig_dir / "official_confusion.png")
    plot_bars(official[best_name]["per_class"],
              f"Official per-class recall  {best_name}",
              fig_dir / "official_per_class.png")

    # ---- pooled capacity 70/30 ----
    Xp, yp_s, _, _ = concat(packs, None, singles_only=True)
    yp, _ = encode(yp_s)
    Xa, Xb, ya, yb = train_test_split(
        Xp, yp, test_size=0.30, random_state=0, stratify=yp
    )
    print(f"pooled singles    train={len(ya)}  test={len(yb)}")
    pooled = {}
    models = fit_models()
    best_name, best_acc, best_pred = None, -1, None
    for name, clf in models.items():
        r = eval_split(clf, Xa, ya, Xb, yb, classes)
        pooled[name] = {k: r[k] for k in ("acc", "macro_f1", "group_DS_acc", "per_class")}
        print(f"  pooled/{name:16s}  acc={r['acc']:.3f}  f1={r['macro_f1']:.3f}  "
              f"D/S={r['group_DS_acc']:.3f}")
        if r["acc"] > best_acc:
            best_acc, best_name, best_pred = r["acc"], name, r["pred"]
    report["protocols"]["pooled_17way"] = {
        "n_train": int(len(ya)), "n_test": int(len(yb)),
        "chance": 1 / 17, "models": pooled, "best": best_name,
    }
    cm = confusion_matrix(yb, best_pred, labels=list(range(17)))
    plot_confusion(cm, classes, f"Pooled 70/30  {best_name}  acc={best_acc:.3f}",
                   fig_dir / "pooled_confusion.png")
    plot_bars(pooled[best_name]["per_class"],
              f"Pooled per-class recall  {best_name}",
              fig_dir / "pooled_per_class.png")
    plot_tsne(Xb, yb, classes, "t-SNE of 44-D singles (pooled test)",
              fig_dir / "pooled_tsne.png")

    # ---- single vs combo on official test ----
    Xte_all, lab_te, njam_te, _ = concat(packs, "test", singles_only=False)
    y_bin = (njam_te >= 2).astype(int)  # 1 = combo
    Xtr_b = np.concatenate([
        concat(packs, "train", False)[0],
        concat(packs, "val", False)[0],
    ], 0)
    ytr_b = np.concatenate([
        (concat(packs, "train", False)[2] >= 2).astype(int),
        (concat(packs, "val", False)[2] >= 2).astype(int),
    ], 0)
    # train is all singles → presence head cannot learn combo from official train.
    # Diagnostic: 70/30 on test only.
    Xa, Xb, ya, yb = train_test_split(
        Xte_all, y_bin, test_size=0.30, random_state=0, stratify=y_bin
    )
    presence = {}
    models = {
        "logreg": make_pipeline(StandardScaler(), LogisticRegression(max_iter=400)),
        "rf": RandomForestClassifier(n_estimators=300, max_depth=12, n_jobs=-1, random_state=0),
        "mlp": make_pipeline(StandardScaler(), MLPClassifier(
            hidden_layer_sizes=(32,), max_iter=200, early_stopping=True, random_state=0)),
    }
    print("presence (single vs combo, 70/30 on test)")
    for name, clf in models.items():
        clf.fit(Xa, ya)
        pred = clf.predict(Xb)
        acc = float(accuracy_score(yb, pred))
        rec_s = float(((pred == 0) & (yb == 0)).sum() / max((yb == 0).sum(), 1))
        rec_c = float(((pred == 1) & (yb == 1)).sum() / max((yb == 1).sum(), 1))
        presence[name] = {"acc": acc, "single_recall": rec_s, "combo_recall": rec_c}
        print(f"  presence/{name:8s}  acc={acc:.3f}  single={rec_s:.3f}  combo={rec_c:.3f}")
    report["protocols"]["presence_single_vs_combo"] = {
        "note": "70/30 on test; official train has no combos",
        "n_train": int(len(ya)), "n_test": int(len(yb)),
        "base_rate_combo": float(y_bin.mean()),
        "models": presence,
    }

    (out / "eval_report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print("wrote", out / "eval_report.json")
    print("plots in", fig_dir)


if __name__ == "__main__":
    main()
