# 干扰信号 .mat 可视化 Web

本地 HTML 界面：加载 `output/` 下的 STFT / Persistence / 时域 `.mat`，按样本浏览，并**实时调节归一化参数**。

## 依赖

```bash
pip install -r requirements.txt
```

需要：`fastapi`, `uvicorn`, `h5py`, `numpy`。

## 启动

在项目根目录或本目录：

```bash
cd D:\VScode\Jamming_signal_simulation\web_viewer
uvicorn server:app --host 127.0.0.1 --port 8765
```

浏览器打开：http://127.0.0.1:8765

## 功能

| 项目 | 说明 |
|------|------|
| 数据源 | 自动扫描 `output/{dataset}/JNR_*/` |
| 类型 | `*_echo_stfts.mat` / `*_echo_persistences.mat` / `*_echo_times.mat` |
| 样本 | 滑条 / ← → 键切换；显示 metadata 标签与 jam_params |
| 归一化 | dB (`20*log10`) / linear；百分位 lo/hi；固定绝对范围跨样本对比 |
| Colormap | Jet / Hot / Turbo / Viridis / Gray 等（Plotly） |

归一化逻辑对齐 MATLAB `utils/apply_colormap_to_stft.m`：

```
mag → (dB 或 linear) → (mag - lo) / (hi - lo) clip 到 [0,1] → colormap
```

## API

- `GET /api/datasets` — 数据集树
- `GET /api/open?path=...&kind=stft|times|persistence` — 打开文件信息
- `GET /api/sample?path=...&kind=...&index=0` — 单样本原始幅度（base64 float32）

路径限制在项目 `output/` 下，按 HDF5 末维切片读取，**不会整文件加载进内存**。

## 小数据验证建议

- `output/know/JNR_+10` — 少量 STFT + times
- `output/persistence2/JNR_+0` — 含 persistence
