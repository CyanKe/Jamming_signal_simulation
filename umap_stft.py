#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
umap_stft.py - UMAP dimensionality reduction for STFT spectrogram or time-domain data

Usage:
    # STFT (default)
    python umap_stft.py --stft output/fine/JNR_+10/test_echo_stfts.mat --meta output/fine/JNR_+10/test_echo_metadata.json
    python umap_stft.py --dir output/fine --dataset test --jnr 0:5:20
    python umap_stft.py --dir output/fine --dataset train --jnr 0:1:20

    # Time-domain signals
    python umap_stft.py --times output/fine/JNR_+10/test_echo_times.mat --meta output/fine/JNR_+10/test_echo_metadata.json
    python umap_stft.py --dir output/fine --dataset test --jnr 0:5:20 --type times

    # Filter + PCA
    python umap_stft.py --dir output/fine --dataset train --jnr 0:20 --filter single
    python umap_stft.py --dir output/fine --dataset test --jnr 0:5:20 --type times --mode pca --pca_dim 50

Preprocessing modes (--mode):
    For STFT data:
        avg_time  - Time-averaged power spectrum, dim=Nfft (default)
        flatten   - Flatten full STFT magnitude, dim=Nfft*Ncol
        avg_freq  - Frequency-averaged, dim=Ncol
        pca       - Flatten then PCA
    For time-domain data:
        avg_time  - Direct magnitude, dim=time_points (default, same name for consistency)
        pca       - PCA pre-reduction
"""

import argparse
import json
import re
import h5py
import numpy as np
from pathlib import Path
import matplotlib.pyplot as plt
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
import umap
import warnings
warnings.filterwarnings('ignore', category=UserWarning, module='umap')

JAM_TYPE_COLORS = {
    'DFTJ': '#1f77b4', 'ISRJ': '#ff7f0e', 'SMSPJ': '#2ca02c',
    'CIJ': '#d62728', 'CSJ': '#9467bd',
    'MISRJ': '#FFB6C1','ISCJ': '#000080','ISDJ': '#FFD700',
    'AJ': '#8c564b', 'BJ': '#e377c2', 'SJ': '#7f7f7f',
    'NCJ': '#bcbd22', 'NPJ': '#17becf', 'NFMJ': '#aec7e8',
    'NPMJ': '#ffbb78', 'NAMJ': '#98df8a', 'PJ': '#c5b0d5',
}


def parse_jnr_range(spec):
    """
    Parse JNR specification into list of integer values.
    "10" -> [10]; "0 5 10" -> [0,5,10]; "0:5:20" -> [0,5,10,15,20]; "0:20" -> [0,1,...,20]
    """
    spec = spec.strip()
    if re.match(r'^-?\d+:-?\d+:-?\d+$', spec):
        start, step, end = (int(x) for x in spec.split(':'))
        return list(range(start, end + 1, step))
    if re.match(r'^-?\d+:-?\d+$', spec):
        start, end = (int(x) for x in spec.split(':'))
        step = 1 if start <= end else -1
        return list(range(start, end + step, step))
    if ' ' in spec:
        return [int(x) for x in spec.split()]
    return [int(spec)]


# ============================================================
# Data loaders
# ============================================================

def load_mat_complex(mat_path, var_name):
    """Load v7.3 .mat as complex array, transposed to samples-first."""
    with h5py.File(mat_path, 'r') as f:
        data = f[var_name]
        arr = data[:]
        arr_cpx = arr['real'] + 1j * arr['imag']
        arr_cpx = arr_cpx.astype(np.complex64)
        # MATLAB storage is column-major: [dim2, dim1, dim3, ...]
        # Reverse dims to get (samples, ...)
        arr_cpx = np.transpose(arr_cpx, tuple(range(arr_cpx.ndim - 1, -1, -1)))
    return arr_cpx


def load_stft(mat_path):
    """Load STFT .mat, return (N, freq, time) magnitude."""
    arr = load_mat_complex(mat_path, 'all_stfts')
    return np.abs(arr)


def load_times(mat_path):
    """Load time-domain .mat, return (N, time_points) magnitude."""
    arr = load_mat_complex(mat_path, 'all_times')
    return np.abs(arr)


def load_stft_rgb(mat_path, colormap_name=None):
    """Load RGB colormap STFT data from *_echo_stfts_rgb.mat.

    Args:
        mat_path: Path to *_echo_stfts_rgb.mat (v7.3 HDF5 format).
        colormap_name: Specific colormap to load (e.g., 'jet', 'parula'),
                       or None to load all available colormaps as a dict.

    Returns:
        If colormap_name is str: np.ndarray [N, H, W, 3] uint8
        If colormap_name is None: dict {name: np.ndarray [N, H, W, 3] uint8}

    Dimension handling:
        MATLAB stores [Samples, H, W, 3] in column-major order.
        HDF5 on disk: [3, W, H, Samples].
        h5py reads as: [3, W, H, Samples].
        Transpose to:   [Samples, H, W, 3] via np.transpose(arr, (3, 2, 1, 0)).
    """
    with h5py.File(mat_path, 'r') as f:
        if colormap_name is not None:
            var_name = f'rgb_{colormap_name}'
            if var_name not in f:
                available = sorted([k[4:] for k in f.keys() if k.startswith('rgb_')])
                raise KeyError(
                    f"Colormap '{colormap_name}' not found in {mat_path}. "
                    f"Available: {available}"
                )
            arr = f[var_name][:]
            # HDF5 storage order (MATLAB column-major): [3, W, H, N]
            # Transpose to Python: [N, H, W, 3]
            arr = np.transpose(arr, (3, 2, 1, 0))
            return np.array(arr, dtype=np.uint8)
        else:
            result = {}
            for key in f.keys():
                if key.startswith('rgb_'):
                    cmap_name = key[4:]  # strip 'rgb_' prefix
                    arr = f[key][:]
                    arr = np.transpose(arr, (3, 2, 1, 0))
                    result[cmap_name] = np.array(arr, dtype=np.uint8)
            return result


def list_rgb_colormaps(mat_path):
    """List available colormap names in a *_echo_stfts_rgb.mat file.

    Args:
        mat_path: Path to *_echo_stfts_rgb.mat

    Returns:
        Sorted list of colormap name strings (e.g., ['gray', 'hot', 'jet', 'parula', 'turbo'])
    """
    with h5py.File(mat_path, 'r') as f:
        return sorted([k[4:] for k in f.keys() if k.startswith('rgb_')])


def load_persistence(mat_path):
    """Load persistence spectrum .mat (real-valued), return (N, freq, power_bins)."""
    with h5py.File(mat_path, 'r') as f:
        data = f['all_persistences']
        arr = data[:]
        # MATLAB stores column-major; transpose to (samples, ...)
        arr = np.transpose(arr, tuple(range(arr.ndim - 1, -1, -1)))
    return np.array(arr, dtype=np.float32)


def normalize_label(raw_label):
    return raw_label.replace('C&IJ', 'CIJ')


def load_metadata(json_path):
    with open(json_path, 'r', encoding='utf-8') as f:
        metadata = json.load(f)
    labels = []
    for item in metadata:
        jt = item['jam_types']
        if isinstance(jt, list):
            labels.append(normalize_label('+'.join(sorted(jt))))
        else:
            labels.append(normalize_label(jt))
    return labels


# ============================================================
# Preprocessing
# ============================================================

def preprocess(data, mode, pca_dim, data_type):
    """Preprocess data for UMAP. Returns features array."""
    n_samples = data.shape[0]

    if data_type == 'stft' or data_type == 'persistence':
        _, n_freq, n_time = data.shape
        if mode == 'avg_time':
            features = np.mean(data, axis=2)
            desc = f'time-avg, dim={n_freq}'
        elif mode == 'avg_freq':
            features = np.mean(data, axis=1)
            desc = f'freq-avg, dim={n_time}'
        elif mode == 'flatten':
            features = data.reshape(n_samples, -1)
            desc = f'flatten, dim={n_freq * n_time}'
        elif mode == 'pca':
            flat = data.reshape(n_samples, -1)
            flat_std = StandardScaler().fit_transform(flat)
            pca = PCA(n_components=min(pca_dim, n_samples, flat.shape[1]), random_state=42)
            features = pca.fit_transform(flat_std)
            desc = (f'PCA({flat.shape[1]}->{pca.n_components_}), '
                    f'var={pca.explained_variance_ratio_.sum():.2%}')
        else:
            raise ValueError(f'Unknown mode for {data_type}: {mode}')
    else:  # times
        _, n_time = data.shape
        if mode == 'avg_time':
            features = data  # already 2D
            desc = f'direct, dim={n_time}'
        elif mode == 'pca':
            data_std = StandardScaler().fit_transform(data)
            pca = PCA(n_components=min(pca_dim, n_samples, n_time), random_state=42)
            features = pca.fit_transform(data_std)
            desc = (f'PCA({n_time}->{pca.n_components_}), '
                    f'var={pca.explained_variance_ratio_.sum():.2%}')
        else:
            raise ValueError(f'Unknown mode for times: {mode}')

    print(f'  Preprocess: {desc}')
    return features


# ============================================================
# Visualization
# ============================================================

def plot_umap(embedding, labels, title_info, save_path=None):
    """Plot UMAP scatter: color = jam type."""
    single_cats = sorted(
        {l for l in labels if '+' not in l},
        key=lambda x: list(JAM_TYPE_COLORS.keys()).index(x) if x in JAM_TYPE_COLORS else 999,
    )
    composite_cats = sorted({l for l in labels if '+' in l})
    n_single = len(single_cats)
    n_composite = len(composite_cats)
    cmap = plt.cm.tab20

    _, axes = plt.subplots(1, 2, figsize=(22, 10))

    # --- Left: single colored, composite gray ---
    ax = axes[0]
    ax.set_facecolor('#f5f5f5')
    composite_mask = np.array(['+' in l for l in labels])
    if composite_mask.any():
        ax.scatter(embedding[composite_mask, 0], embedding[composite_mask, 1],
                   c='#dddddd', s=6, alpha=0.35, marker='o',
                   label=f'Composite ({composite_mask.sum()})', edgecolors='none')
    for cat in single_cats:
        mask = np.array([l == cat for l in labels])
        if mask.any():
            color = JAM_TYPE_COLORS.get(cat, '#999999')
            ax.scatter(embedding[mask, 0], embedding[mask, 1],
                       c=[color], s=18, alpha=0.85, label=f'{cat} ({mask.sum()})',
                       edgecolors='white', linewidth=0.3)
    ax.set_title(f'UMAP ({n_single} single colored, {n_composite} composite gray)',
                 fontsize=14, fontweight='bold')
    ax.set_xlabel('UMAP 1'); ax.set_ylabel('UMAP 2')
    ax.legend(loc='upper left', fontsize=7, ncol=2, framealpha=0.9,
              bbox_to_anchor=(1.0, 1.0))

    # --- Right: all categories individually colored ---
    ax = axes[1]
    ax.set_facecolor('#f5f5f5')
    all_cats = single_cats + composite_cats
    for cat in all_cats:
        mask = np.array([l == cat for l in labels])
        if not mask.any():
            continue
        if cat in JAM_TYPE_COLORS:
            color = JAM_TYPE_COLORS[cat]
        else:
            gi = composite_cats.index(cat)
            color = cmap(gi / max(n_composite, 1))
        ax.scatter(embedding[mask, 0], embedding[mask, 1],
                   c=[color], s=14, alpha=0.8, label=f'{cat} ({mask.sum()})',
                   edgecolors='white', linewidth=0.2)
    ax.set_title(f'UMAP ({n_single} single + {n_composite} composite = {len(all_cats)} classes)',
                 fontsize=14, fontweight='bold')
    ax.set_xlabel('UMAP 1'); ax.set_ylabel('UMAP 2')
    ncol = 3 if len(all_cats) > 30 else 2
    ax.legend(loc='upper left', fontsize=5, ncol=ncol, framealpha=0.85,
              bbox_to_anchor=(1.0, 1.0))

    plt.suptitle(title_info, fontsize=16, fontweight='bold', y=1.02)
    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f'  Saved: {save_path}')
    else:
        plt.show()


# ============================================================
# Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(description='UMAP dimensionality reduction for STFT/time-domain data')
    # Single-file mode
    parser.add_argument('--stft', type=str, default=None, help='Single STFT .mat path')
    parser.add_argument('--times', type=str, default=None, help='Single time-domain .mat path')
    parser.add_argument('--persistence', type=str, default=None, help='Single persistence .mat path')
    parser.add_argument('--meta', type=str, default=None, help='Single metadata .json path')
    # Multi-JNR mode
    parser.add_argument('--dir', type=str, default=None, help='Base output directory')
    parser.add_argument('--dataset', type=str, default='test', help='Dataset split name')
    parser.add_argument('--jnr', type=str, default=None, help='JNR spec: 10, 0:5:20, 0:20')
    parser.add_argument('--type', type=str, default='stft', choices=['stft', 'times', 'persistence'],
                        help='Data type: stft (default), times, or persistence')
    # Common
    parser.add_argument('--mode', type=str, default='avg_time',
                        help='Preprocessing mode (default: avg_time; for times: avg_time=pca)')
    parser.add_argument('--pca_dim', type=int, default=50, help='PCA target dim')
    parser.add_argument('--filter', type=str, default='all',
                        choices=['all', 'single', 'composite'])
    parser.add_argument('--n_neighbors', type=int, default=30, help='UMAP n_neighbors')
    parser.add_argument('--min_dist', type=float, default=0.3, help='UMAP min_dist')
    parser.add_argument('--seed', type=int, default=42, help='Random seed')
    parser.add_argument('--save', type=str, default=None, help='Output image path')
    parser.add_argument('--save_embedding', type=str, default=None, help='Save embedding .npy')
    args = parser.parse_args()

    # ============================================================
    # 1. Load data
    # ============================================================
    all_data = []
    all_labels = []
    data_type = args.type

    if args.dir and args.jnr:
        jnr_list = parse_jnr_range(args.jnr)
        if data_type == 'stft':
            suffix = 'stfts'; loader = load_stft
        elif data_type == 'persistence':
            suffix = 'persistences'; loader = load_persistence
        else:
            suffix = 'times'; loader = load_times
        print(f'\n{"=" * 60}')
        print(f'Data type: {data_type}')
        print(f'Directory: {args.dir}')
        print(f'Dataset:   {args.dataset}')
        print(f'JNR:       {jnr_list}')

        loaded_jnr = []
        for jnr in jnr_list:
            jnr_str = f'+{jnr}' if jnr >= 0 else str(jnr)
            data_path = Path(args.dir) / f'JNR_{jnr_str}' / f'{args.dataset}_echo_{suffix}.mat'
            meta_path = Path(args.dir) / f'JNR_{jnr_str}' / f'{args.dataset}_echo_metadata.json'

            if not data_path.exists():
                print(f'  [SKIP] {data_path} not found')
                continue
            if not meta_path.exists():
                print(f'  [SKIP] {meta_path} not found')
                continue

            print(f'  JNR={jnr_str}: {data_path.name} ...', end=' ')
            data = loader(str(data_path))
            labels = load_metadata(str(meta_path))
            assert data.shape[0] == len(labels), \
                f'Samples mismatch: {data.shape[0]} vs {len(labels)}'
            all_data.append(data)
            all_labels.extend(labels)
            loaded_jnr.append(jnr_str)
            print(f'{len(labels)} samples')

        if not all_data:
            print('ERROR: No valid data found.')
            return
        all_data = np.concatenate(all_data, axis=0)
        print(f'  Total: {len(all_labels)} samples, shape={all_data.shape} from JNR=[{", ".join(loaded_jnr)}]')

    else:
        # Single-file mode: determine source from --stft, --times, or --persistence
        if args.stft and args.meta:
            data_path, meta_path = args.stft, args.meta
            data_type = 'stft'
            loader = load_stft
        elif args.times and args.meta:
            data_path, meta_path = args.times, args.meta
            data_type = 'times'
            loader = load_times
        elif args.persistence and args.meta:
            data_path, meta_path = args.persistence, args.meta
            data_type = 'persistence'
            loader = load_persistence
        else:
            parser.error('Use --stft/--meta, --times/--meta, --persistence/--meta, or --dir/--jnr')

        print(f'\n{"=" * 60}')
        print(f'Data type: {data_type}')
        print(f'Data:  {data_path}')
        print(f'Meta:  {meta_path}')
        all_data = loader(str(data_path))
        all_labels = load_metadata(str(meta_path))
        assert all_data.shape[0] == len(all_labels)
        print(f'  Total: {len(all_labels)} samples, shape={all_data.shape}')

    # ============================================================
    # 2. Filter
    # ============================================================
    if args.filter == 'single':
        mask = np.array(['+' not in l for l in all_labels])
    elif args.filter == 'composite':
        mask = np.array(['+' in l for l in all_labels])
    else:
        mask = np.ones(len(all_labels), dtype=bool)

    all_data = all_data[mask]
    all_labels = [l for l, m in zip(all_labels, mask) if m]
    unique_labels = sorted(set(all_labels))
    print(f'  Filter: {args.filter} -> {len(all_labels)} samples, {len(unique_labels)} classes')

    # ============================================================
    # 3. Preprocess
    # ============================================================
    print(f'\n  Preprocessing (mode={args.mode}, type={data_type})...')
    features = preprocess(all_data, args.mode, args.pca_dim, data_type)

    # ============================================================
    # 4. UMAP
    # ============================================================
    n_neighbors = min(args.n_neighbors, len(all_labels) - 1)
    print(f'\n  UMAP (n_neighbors={n_neighbors}, min_dist={args.min_dist})...')
    reducer = umap.UMAP(
        n_neighbors=n_neighbors,
        min_dist=args.min_dist,
        n_components=2,
        metric='euclidean',
        random_state=args.seed,
        verbose=True,
    )
    embedding = reducer.fit_transform(features)
    print(f'  Embedding: {embedding.shape}')

    # ============================================================
    # 5. Save embedding
    # ============================================================
    if args.save_embedding:
        np.save(args.save_embedding, embedding)
        np.savez(args.save_embedding.replace('.npy', '_meta.npz'),
                 labels=np.array(all_labels))
        print(f'  Embedding saved: {args.save_embedding}')

    # ============================================================
    # 6. Visualize
    # ============================================================
    save_path = args.save
    if save_path is None:
        if args.dir:
            out_dir = Path(args.dir)
            jnr_tag = 'JNR_' + args.jnr.replace(':', '_').replace(' ', '_')
            save_path = str(out_dir / f'umap_{args.type}_{args.dataset}_{jnr_tag}_{args.mode}.png')
        else:
            out_dir = Path(data_path).parent
            stem = Path(data_path).stem
            save_path = str(out_dir / f'umap_{stem}_{args.mode}.png')

    title_info = f'UMAP ({data_type}) | mode={args.mode} | {len(all_labels)} samples, {len(unique_labels)} classes'
    plot_umap(embedding, all_labels, title_info, save_path=save_path)


if __name__ == '__main__':
    main()
