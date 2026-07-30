#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
干扰信号 .mat 可视化本地服务。

按样本切片读取 v7.3 (HDF5) 输出，返回原始幅度供前端实时归一化。

启动:
    cd web_viewer
    uvicorn server:app --reload --port 8765
"""

from __future__ import annotations

import base64
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import h5py
import numpy as np
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

# 项目根目录 (web_viewer 的上一级)
ROOT = Path(__file__).resolve().parent.parent
OUTPUT_ROOT = ROOT / "output"
STATIC_DIR = Path(__file__).resolve().parent / "static"

KIND_VARS = {
    "stft": "all_stfts",
    "times": "all_times",
    "persistence": "all_persistences",
}

KIND_SUFFIX = {
    "stft": "_echo_stfts.mat",
    "times": "_echo_times.mat",
    "persistence": "_echo_persistences.mat",
}

app = FastAPI(title="Jamming Signal Viewer", version="1.0.0")


def _safe_resolve(rel_path: str) -> Path:
    """将相对 output 的路径解析为绝对路径，禁止越界。"""
    if not rel_path:
        raise HTTPException(400, "path 不能为空")
    # 允许绝对路径（仍限制在 OUTPUT_ROOT 下）或相对 output 的路径
    p = Path(rel_path)
    if p.is_absolute():
        target = p.resolve()
    else:
        # 支持 "output/xxx" 或 "xxx" 或完整文件名
        s = rel_path.replace("\\", "/")
        if s.startswith("output/"):
            s = s[len("output/") :]
        target = (OUTPUT_ROOT / s).resolve()

    try:
        target.relative_to(OUTPUT_ROOT.resolve())
    except ValueError:
        raise HTTPException(403, f"路径必须在 output/ 目录下: {rel_path}")

    if not target.exists():
        raise HTTPException(404, f"文件不存在: {target}")
    return target


def _rel_to_output(path: Path) -> str:
    return path.resolve().relative_to(OUTPUT_ROOT.resolve()).as_posix()


def _is_complex_dtype(dt: np.dtype) -> bool:
    return dt.names is not None and "real" in dt.names and "imag" in dt.names


def _sample_count_from_shape(shape: Tuple[int, ...]) -> int:
    # MATLAB 列主序 → HDF5 末维是样本维
    if not shape:
        return 0
    return int(shape[-1])


def _load_axes(f: h5py.File) -> Dict[str, Any]:
    axes: Dict[str, Any] = {}
    if "F" in f:
        axes["F"] = np.array(f["F"][:]).squeeze().astype(np.float64).tolist()
    if "T" in f:
        axes["T"] = np.array(f["T"][:]).squeeze().astype(np.float64).tolist()
    if "power_centers" in f:
        axes["power_centers"] = (
            np.array(f["power_centers"][:]).squeeze().astype(np.float64).tolist()
        )
    if "num_power_bins" in f:
        nb = np.array(f["num_power_bins"][:]).squeeze()
        axes["num_power_bins"] = int(nb) if np.ndim(nb) == 0 else nb.astype(int).tolist()
    if "channel_power_bins" in f:
        axes["channel_power_bins"] = (
            np.array(f["channel_power_bins"][:]).squeeze().astype(int).tolist()
        )
    if "target_size" in f:
        axes["target_size"] = (
            np.array(f["target_size"][:]).squeeze().astype(int).tolist()
        )
    return axes


def _metadata_path_for_mat(mat_path: Path) -> Optional[Path]:
    name = mat_path.name
    for kind, suffix in KIND_SUFFIX.items():
        if name.endswith(suffix):
            split_prefix = name[: -len(suffix)]  # e.g. "test"
            meta = mat_path.parent / f"{split_prefix}_echo_metadata.json"
            if meta.exists():
                return meta
    # fallback: same stem family
    for m in mat_path.parent.glob("*_echo_metadata.json"):
        return m
    return None


def _load_metadata_item(meta_path: Optional[Path], index: int) -> Optional[Dict[str, Any]]:
    if meta_path is None or not meta_path.exists():
        return None
    with open(meta_path, "r", encoding="utf-8") as fp:
        meta = json.load(fp)
    if index < 0 or index >= len(meta):
        return None
    return meta[index]


def _format_label(item: Optional[Dict[str, Any]]) -> str:
    if not item:
        return ""
    jt = item.get("jam_types", "?")
    if isinstance(jt, list):
        jt = "+".join(str(x) for x in jt)

    # 纯LFM信号: 使用 SNR 替代 JNR
    if jt == "clean":
        snr = item.get("SNR", "?")
        try:
            snr_s = f"{int(snr):+d}dB"
        except (TypeError, ValueError):
            snr_s = f"{snr}dB"
        return f"Clean LFM  |  SNR={snr_s}"

    jnr = item.get("JNR", "?")
    try:
        jnr_s = f"{int(jnr):+d}dB"
    except (TypeError, ValueError):
        jnr_s = f"{jnr}dB"
    return f"{jt}  |  JNR={jnr_s}"


def _encode_f32(arr: np.ndarray) -> Dict[str, Any]:
    """将 float32 数组编码为 base64，减少 JSON 体积。"""
    a = np.ascontiguousarray(arr.astype(np.float32))
    return {
        "encoding": "base64_f32",
        "shape": list(a.shape),
        "data": base64.b64encode(a.tobytes()).decode("ascii"),
    }


def _read_sample(mat_path: Path, kind: str, index: int) -> Dict[str, Any]:
    var = KIND_VARS[kind]
    with h5py.File(mat_path, "r") as f:
        if var not in f:
            raise HTTPException(400, f"文件中没有变量 {var}，可用: {list(f.keys())}")
        ds = f[var]
        n = _sample_count_from_shape(ds.shape)
        if index < 0 or index >= n:
            raise HTTPException(400, f"index 越界: {index} (0..{n-1})")

        # 末维切片 → 去掉样本维
        # stft HDF5: [Ncol, Nfft, N] → sample: [Ncol, Nfft] → 转置为 [Nfft, Ncol]
        # times HDF5: [PRI, N] → sample: [PRI]
        # persistence HDF5: [bins, Nfft, N] → sample: [bins, Nfft] → 转置为 [Nfft, bins]
        sample = ds[..., index]
        sample = np.array(sample)

        axes = _load_axes(f)

        if kind == "times":
            if _is_complex_dtype(sample.dtype):
                real = sample["real"].astype(np.float32)
                imag = sample["imag"].astype(np.float32)
                mag = np.sqrt(real * real + imag * imag)
            else:
                real = sample.astype(np.float32)
                imag = np.zeros_like(real)
                mag = np.abs(real)
            return {
                "kind": kind,
                "index": index,
                "n_samples": n,
                "mag": _encode_f32(mag),
                "real": _encode_f32(real),
                "imag": _encode_f32(imag),
                "axes": axes,
            }

        if kind == "stft":
            # 复数 STFT：返回 mag / real / imag，供前端切换
            # 单通道: 模值 / 实部 / 虚部 / 相位
            # 三通道 RGB: [模值,实部,虚部] / [相位,实部,虚部] / [模值×3]
            if _is_complex_dtype(sample.dtype):
                real = sample["real"].astype(np.float32)
                imag = sample["imag"].astype(np.float32)
                mag = np.sqrt(
                    real.astype(np.float64) ** 2 + imag.astype(np.float64) ** 2
                ).astype(np.float32)
            else:
                real = sample.astype(np.float32)
                imag = np.zeros_like(real)
                mag = np.abs(real)
            # [Ncol, Nfft] → [Nfft, Ncol]
            if mag.ndim == 2:
                mag = mag.T
                real = real.T
                imag = imag.T
            return {
                "kind": kind,
                "index": index,
                "n_samples": n,
                "mag": _encode_f32(mag),
                "real": _encode_f32(real),
                "imag": _encode_f32(imag),
                "axes": axes,
            }

        if kind == "persistence":
            arr = sample.astype(np.float32)
            # MATLAB v7.3 存 [N,H,W] → HDF5 切片 [W,H]
            #          存 [N,H,W,C] → HDF5 切片 [C,W,H]
            n_channels = 1
            if arr.ndim == 2:
                # [bins, Nfft] → [Nfft, bins]
                arr = arr.T
            elif arr.ndim == 3:
                # [C, W, H] → [H, W, C]
                arr = np.transpose(arr, (2, 1, 0))
                n_channels = int(arr.shape[2])
                # 默认返回 ch0 供现有前端 2D 显示; 全通道放 channels
                channels = arr
                arr = arr[:, :, 0]
            else:
                raise HTTPException(400, f"不支持的 persistence 维度: {arr.shape}")
            out = {
                "kind": kind,
                "index": index,
                "n_samples": n,
                "mag": _encode_f32(arr),
                "n_channels": n_channels,
                "axes": axes,
            }
            if n_channels > 1:
                # 附加全部通道 [H,W,C] 供前端切换
                out["channels"] = _encode_f32(channels)
            return out

    raise HTTPException(400, f"未知 kind: {kind}")


def open_info(mat_path: Path, kind: str) -> Dict[str, Any]:
    var = KIND_VARS[kind]
    with h5py.File(mat_path, "r") as f:
        if var not in f:
            raise HTTPException(400, f"文件中没有变量 {var}，可用: {list(f.keys())}")
        ds = f[var]
        n = _sample_count_from_shape(ds.shape)
        shape_h5 = list(ds.shape)
        dtype_str = str(ds.dtype)
        axes = _load_axes(f)

    if kind == "times":
        py_shape = [n, shape_h5[0]]
    else:
        py_shape = [n] + list(reversed(shape_h5[:-1]))

    meta_path = _metadata_path_for_mat(mat_path)
    meta_count = 0
    labels: List[str] = []
    if meta_path and meta_path.exists():
        with open(meta_path, "r", encoding="utf-8") as fp:
            meta = json.load(fp)
        meta_count = len(meta)
        for item in meta[: min(len(meta), n)]:
            labels.append(_format_label(item))

    return {
        "path": _rel_to_output(mat_path),
        "abs_path": str(mat_path),
        "kind": kind,
        "var": var,
        "n_samples": n,
        "shape_h5": shape_h5,
        "shape": py_shape,
        "dtype": dtype_str,
        "axes": axes,
        "has_metadata": meta_path is not None,
        "metadata_path": _rel_to_output(meta_path) if meta_path else None,
        "metadata_count": meta_count,
        "labels": labels,
        "size_mb": round(mat_path.stat().st_size / (1024 * 1024), 2),
    }


def scan_datasets() -> List[Dict[str, Any]]:
    """扫描 output/ 下的数据集树。"""
    if not OUTPUT_ROOT.exists():
        return []

    results: List[Dict[str, Any]] = []
    # 结构: output/{dataset}/JNR_+N/{split}_echo_*.mat  或  output/{dataset}/SNR_+N/...
    for ds_dir in sorted(OUTPUT_ROOT.iterdir()):
        if not ds_dir.is_dir() or ds_dir.name.startswith("."):
            continue
        jnr_dirs = sorted(
            [d for d in ds_dir.iterdir() if d.is_dir() and (d.name.startswith("JNR_") or d.name.startswith("SNR_"))]
        )
        if not jnr_dirs:
            # 直接在 dataset 下找 mat
            entry = _scan_dir_mats(ds_dir, dataset=ds_dir.name, jnr=None)
            if entry["files"]:
                results.append(entry)
            continue

        for jnr_dir in jnr_dirs:
            entry = _scan_dir_mats(jnr_dir, dataset=ds_dir.name, jnr=jnr_dir.name)
            if entry["files"]:
                results.append(entry)
    return results


def _scan_dir_mats(directory: Path, dataset: str, jnr: Optional[str]) -> Dict[str, Any]:
    files: List[Dict[str, Any]] = []
    for kind, suffix in KIND_SUFFIX.items():
        for mat in sorted(directory.glob(f"*{suffix}")):
            # 排除 rgb
            if "rgb" in mat.name.lower():
                continue
            m = re.match(r"^(train|val|test)_echo_", mat.name)
            split = m.group(1) if m else "unknown"
            files.append(
                {
                    "kind": kind,
                    "split": split,
                    "name": mat.name,
                    "path": _rel_to_output(mat),
                    "size_mb": round(mat.stat().st_size / (1024 * 1024), 2),
                }
            )
    return {
        "dataset": dataset,
        "jnr": jnr,
        "dir": _rel_to_output(directory),
        "files": files,
    }


@app.get("/api/health")
def health():
    return {"ok": True, "output_root": str(OUTPUT_ROOT)}


@app.get("/api/datasets")
def api_datasets():
    return {"output_root": str(OUTPUT_ROOT), "entries": scan_datasets()}


@app.get("/api/open")
def api_open(
    path: str = Query(..., description="相对 output/ 的 .mat 路径"),
    kind: str = Query(..., description="stft | times | persistence"),
):
    kind = kind.lower()
    if kind not in KIND_VARS:
        raise HTTPException(400, f"kind 必须是 {list(KIND_VARS)}")
    mat_path = _safe_resolve(path)
    if not mat_path.suffix.lower() == ".mat":
        raise HTTPException(400, "path 必须是 .mat 文件")
    info = open_info(mat_path, kind)
    return info


@app.get("/api/sample")
def api_sample(
    path: str = Query(...),
    kind: str = Query(...),
    index: int = Query(0, ge=0),
):
    kind = kind.lower()
    if kind not in KIND_VARS:
        raise HTTPException(400, f"kind 必须是 {list(KIND_VARS)}")
    mat_path = _safe_resolve(path)
    payload = _read_sample(mat_path, kind, index)
    meta_path = _metadata_path_for_mat(mat_path)
    meta_item = _load_metadata_item(meta_path, index)
    payload["meta"] = meta_item
    payload["label"] = _format_label(meta_item)
    payload["path"] = _rel_to_output(mat_path)
    return payload


@app.get("/")
def index():
    index_path = STATIC_DIR / "index.html"
    if not index_path.exists():
        raise HTTPException(500, "static/index.html 缺失")
    return FileResponse(index_path)


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("server:app", host="127.0.0.1", port=8765, reload=True)
