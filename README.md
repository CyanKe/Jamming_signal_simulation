# 雷达干扰信号生成代码

## 干扰类型列表

### 欺骗式干扰 (Deceptive Jamming)

| 名称 | 缩写 | 说明 |
| :------: | :------: | :------: |
| 密集假目标干扰 | DFTJ | 生成多个假目标回波 |
| 间歇采样转发干扰 | ISRJ | 对信号进行间歇采样后转发 |
| 间歇采样单独干扰 | ISDJ | 间歇采样后转发单次干扰 |
| 间歇采样循环干扰 | ISCJ | 间歇采样后转发所有已采片段 |
| 间歇采样调制转发干扰 | MISRJ | 间歇采样后转发调制采样信号 |
| 距离假目标干扰 | RGPO | 距离拖引，模拟假目标移动 |
| 速度假目标干扰 | VGPO | 速度拖引，模拟假目标速度变化 |
| 弥散谱干扰 | SMSPJ | STFT表现为陡峭斜线 |
| 切片交织干扰 | CIJ | 连续转发，STFT连续分布 |
| 梳状谱干扰 | CSJ | STFT表现为密集梳齿状斜线 |

### 压制干扰 (Suppressive Jamming)

| 名称 | 缩写 | 说明 |
| :------: | :------: | :------: |
| 瞄准干扰 | AJ | 窄带瞄准式干扰 |
| 阻塞干扰 | BJ | 宽带阻塞式干扰 |
| 扫频干扰 | SJ | 频率扫描式干扰 |
| 噪声卷积干扰 | NCJ | 噪声与信号卷积 |
| 噪声乘积干扰 | NPJ | 噪声与信号相乘 |
| 噪声调频干扰 | NFMJ | 噪声调制频率 |
| 噪声调相干扰 | NPMJ | 噪声调制相位 |
| 噪声调幅干扰 | NAMJ | 噪声调制幅度 |
| 脉冲干扰 | PJ | 脉冲式干扰 |

> `RGPO` / `VGPO` 生成器保留但默认未在调度器中启用；当前 17 个基础类以
> [config_example.m](config_example.m) 的 `generation_plan` 为准（8 欺骗 + 9 压制）。

### 存储-转发选项（NCJ / NPJ）

NCJ、NPJ 支持显式的脉间更新周期 U，用于区分「每脉冲重新产生噪声」与
「整帧复用同一段存储波形」：

```matlab
cfg.signal.Np    = 16;   % 需要 > 1 才生效
cfg.jamming.ncj.U = 16;  % 16 = 整帧同一波形; 1 = 每脉冲新噪声
cfg.jamming.npj.U = 16;
```

不设置时行为与既有数据完全一致。详见 [docs/NCJ_NPJ_store_and_forward.md](docs/NCJ_NPJ_store_and_forward.md)。

## 混合干扰

支持多种干扰类型组合，标签为**字符串拼接**（如 `"DFTJ+AJ"`），不再使用整数标签：

- `DFTJ+AJ` - 密集假目标 + 瞄准干扰
- `CSJ+SJ` - 梳状谱 + 扫频干扰
- `DFTJ+DFTJ` - 同类型双分量叠加（统一数据集中的 `sameDD` / `sameSS` 类）

`cfg.generation_plan` 支持三种写法：

| 方式 | 配置项 | 说明 |
| :--- | :--- | :--- |
| 显式列举 | `generation_plan` | 逐条写 `{jam_types, sample_count}`，`jam_types` 可为字符串或 cell |
| 交叉组合 | `combo_deceptive × combo_suppressive` | 欺骗 × 压制的笛卡尔积 |
| 两两组合 | `combo_types` | 列表内任意两种干扰的 `C(n,2)` 无序对 |

> `RGPO` / `VGPO` 生成器仍保留在 `generators/deceptive/`，但在调度器中默认注释，未参与生成。

### 分量级输出（`multi_generation_v2` 第三返回值）

`multi_generation_v2(jam_types, params, JNR, N, cfg)` 现在额外返回 `components`，
按样本记录各干扰分量与回波/噪声，便于构造分量级数据集或做可加性分析：

| 字段 | 说明 |
| :--- | :--- |
| `components(m).jams` | cell 数组，各干扰分量（`clean` 不计入） |
| `components(m).types` / `.roles` | 分量类型及其角色 `D` / `S` |
| `components(m).component_params` | 每个分量的 `jam_info` |
| `components(m).E` | 经随机相位与 SNR 缩放的回波 |
| `components(m).W` | 单位功率复高斯噪声 |

可选第 6 参数 `fixed` 用于**配对诊断**：传入 `.B/.taup/.sweep_dir/.pos/.white_noise/.random_phase`
时复用同一条回波与噪声实现。对应 metadata 新增 `component_params` 与 `roles` 字段。

## 代码结构

```text
├── config.m / config_example.m     # 配置文件(使用config.m)
├── load_features.py                # PyTorch 22 维特征加载桥接
├── stft_rgb_dataset.py             # STFT RGB 色图 PyTorch 数据集
├── view_rgb_colormaps.py           # RGB 色图交互浏览
├── extract_fast44.py               # 44 维快集提取 (times + STFT)
├── eval_fast44.py                  # 44 维小模型可分性评测
├── eval_fast44_loo.py              # 44 维留一(LOO)诊断
├── umap_stft.py                    # UMAP 可视化脚本
├── docs/                           # 说明文档
│   ├── FAST44.md                   # 44 维使用说明与运行结论
│   ├── persistence_methods.md      # 持久谱 legacy/custom/matlab 三种方法
│   └── NCJ_NPJ_store_and_forward.md
├── generators/                     # 信号生成器
│   ├── base/                       # 基础信号
│   │   └── generate_0base_signal.m
│   ├── deceptive/                  # 欺骗式干扰 (10种)
│   │   ├── generate_dftj_jamming.m
│   │   ├── generate_isrj_jamming.m
│   │   ├── generate_isdj_jamming.m
│   │   ├── generate_iscj_jamming.m
│   │   ├── generate_misrj_jamming.m
│   │   ├── generate_rgpo_jamming.m
│   │   ├── generate_vgpo_jamming.m
│   │   ├── generate_smspj_jamming.m
│   │   ├── generate_cij_jamming.m
│   │   └── generate_csj_jamming.m
│   └── suppressive/               # 压制干扰 (9种)
│       ├── generate_ab_jamming.m
│       ├── generate_sj_jamming.m
│       ├── generate_ncj_jamming.m
│       ├── generate_npj_jamming.m
│       ├── generate_ncj_sf_jamming.m  # 存储-转发变体
│       ├── generate_npj_sf_jamming.m
│       ├── generate_nfmj_jamming.m
│       ├── generate_npmj_jamming.m
│       ├── generate_namj_jamming.m
│       └── generate_pulse_jamming.m
│
├── main/                           # 主入口
│   ├── main_generation_v2.m        # 主生成流程 (v2, 字符串标签)
│   ├── multi_generation_v2.m       # 干扰调度器 (v2, 返回分量)
│   ├── main_generation_unified.m   # 统一数据集（分量级, 170 类）
│   ├── main_generation.m           # 主生成流程 (v1, 整数标签, 已废弃)
│   ├── multi_generation.m          # 干扰调度器 (v1, 已废弃)
│   ├── main_generation_CWD.m       # CWD 时频分析生成
│   ├── main_dechirp.m              # Dechirp 后处理
│   ├── main_feature_extract.m      # 特征提取入口
│   └── generate_jam_type_samples.m # 按干扰类型生成样本
│
├── utils/                          # 工具函数
│   ├── config_to_params.m          # 配置→参数结构体
│   ├── sample_lfm_params.m         # 样本级 LFM 参数随机化
│   ├── extract_signal_features.m   # 特征提取编排器
│   ├── test_feature_extraction.m   # 特征提取测试
│   ├── visualize_features_json.m   # 特征可视化
│   ├── convert_times_to_stft.m     # 时域 → STFT
│   ├── compute_persistence_legacy.m      # legacy 64-bin 持久谱
│   ├── compute_persistence_channels.m    # 多通道持久谱
│   ├── compute_duration_spectrum.m       # 持续时间谱
│   ├── resolve_persistence_channel_config.m
│   ├── resolve_custom_power_range.m
│   ├── resize_persistence_map.m
│   ├── convert_stft_to_persistence.m     # STFT → 持久谱
│   ├── apply_colormap_to_stft.m / convert_stft_to_rgb.m  # RGB 色图
│   ├── CWD.m / CWD.md              # Choi-Williams 分布
│   ├── convert_times_to_tfr.m      # 后处理 WVD/PWVD/SPWVD/CWD (每类1样本, 256→224)
│   ├── convert_times_to_wvd.m      # 时域 → WVD
│   ├── benchmark_wvd_cost.m        # WVD 族开销实测
│   ├── DiffSTFT.m                  # 差分 STFT
│   ├── DiffSTFT_Advanced.m         # 高级差分 STFT
│   ├── demo_DiffSTFT.m             # DiffSTFT 演示
│   ├── choiwilliams.m              # Choi-Williams 分布实现
│   ├── convertLabelsToOneHot.m     # 标签独热编码
│   ├── gen_modulation_phase.m      # 调制相位生成
│   ├── gen_square_wave.m           # 方波生成
│   ├── process_rdm.m               # 距离-多普勒图
│   ├── process_rdm_with_keystone.m # Keystone 变换 RDM
│   ├── generate_features_from_times.m  # 从时域信号提取特征
│   └── features/                   # 5个域特征提取器
│       ├── extract_time_domain_features.m
│       ├── extract_freq_domain_features.m
│       ├── extract_statistical_features.m
│       ├── extract_wavelet_features.m
│       └── extract_bispectrum_features.m
│
├── web_viewer/                     # 本地 Web 可视化 (FastAPI + Plotly)
│   ├── server.py
│   └── README.md                   # STFT/Persistence/WVD 族浏览说明
│
└── tests/                          # 测试
    ├── test_all_deceptive_jnr.m    # 欺骗式干扰 JNR 验证
    ├── test_all_suppressive_jnr.m  # 压制干扰 JNR 验证
    ├── test_combo_jnr.m            # 混合干扰功率验证
    ├── test_ncj_npj_sf.m           # NCJ/NPJ 存储-转发验证
    └── test_sf_dispatch.m          # 存储-转发调度验证
```

## 使用方式

```matlab
cfg = config();  % 加载配置(需要把config_example.m转成config.m)
run('main/main_generation_v2.m');  % 执行生成
```

修改 `config.m` 中的参数可调整：

- 各数据集 (train/val/test) 的生成计划
- 干噪比 (JNR)
- 干扰带宽等特定参数

### 验证与后处理

```matlab
% JNR / 功率校验
run('tests/test_all_deceptive_jnr.m')
run('tests/test_all_suppressive_jnr.m')
run('tests/test_combo_jnr.m')
run('tests/test_ncj_npj_sf.m')

% 基于已生成的 all_times 后处理
main_dechirp                       % dechirp + STFT
main_feature_extract               % 重新提取 22 维多域特征
convert_times_to_tfr('output/<dir>/JNR_+10')   % WVD/PWVD/SPWVD/CWD
```

### 纯LFM信号（无干扰）

如需生成纯LFM信号（仅回波+噪声，无干扰），在 `config.m` 中设置：

```matlab
cfg.clean_lfm.enabled = true;          % 启用纯LFM生成
cfg.clean_lfm.SNR_values = -10:5:10;   % SNR 扫描范围 (dB)
cfg.clean_lfm.SAMPLE_NUM = 200;        % 每个 SNR 值的样本数
```

纯LFM信号保存到 `SNR_<value>/` 子目录（与 `JNR_<value>/` 并列），文件格式与干扰信号一致，可配置的参数包括：

| 参数 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `cfg.clean_lfm.enabled` | `false` | 是否启用纯LFM生成 |
| `cfg.clean_lfm.SNR_values` | `-10:5:10` | SNR 扫描值 (dB)，可为标量或向量 |
| `cfg.clean_lfm.SAMPLE_NUM` | `100` | 每个 SNR 值的样本数 |

---

## 数据集格式说明

### 输出文件

数据按 SNR/JNR 分目录存储：

```text
output/<dirname>/
├── JNR_+0/              # 干扰信号（按干噪比分目录）
│   ├── test_echo_times.mat
│   ├── test_echo_stfts.mat
│   └── ...
├── JNR_+5/
│   └── ...
├── SNR_-10/             # 纯LFM信号（按信噪比分目录，可选）
│   ├── test_echo_times.mat
│   ├── test_echo_stfts.mat
│   └── ...
└── SNR_+0/
    └── ...
```

每个 JNR/SNR 目录下生成以下文件：

| 文件名 | 格式 | 说明 |
| :--- | :--- | :--- |
| `<dataset>_echo_times.mat` | `.mat` (v7.3) | 时域信号 |
| `<dataset>_echo_stfts.mat` | `.mat` (v7.3) | STFT 时频谱 (可选) |
| `<dataset>_echo_persistences.mat` | `.mat` (v7.3) | 持续时间谱 (可选) |
| `<dataset>_echo_stfts_rgb.mat` | `.mat` (v7.3) | 多 colormap RGB 图像，变量 `rgb_<name>` (可选) |
| `<dataset>_echo_features.json` | JSON | 多域特征 (可选) |
| `<dataset>_echo_metadata.json` | JSON | 样本元数据 (含标签) |
| `generation_plan.mat` / `.json` | `.mat` / JSON | 生成计划 |

其中 `<dataset>` 为 `train` / `val` / `test`，由 `cfg.output.dataset_type` 控制。

时域与 STFT 以 `-v7.3 -nocompression` 保存以降低读取 IO，持久谱与 RGB 用 `-v7.3`。
RGB 色图由 `cfg.output.save_stft_rgb` 控制，每种 colormap 保存为独立变量
`rgb_parula`、`rgb_jet` 等。

### 变量说明

#### `all_times` — 时域信号

```text
变量名: all_times
类型:   single
形状:   [SAMPLE_NUM × PRI_samp]
说明:   每行为一个样本的复基带时域信号 (I/Q)
```

#### `all_stfts` — STFT 时频谱

```text
变量名: all_stfts
类型:   single
形状:   [SAMPLE_NUM × Nfft × N_cols]
说明:   spectrogram() 输出, Nfft=128, Hamming窗
频率轴: F (centered, Hz)
时间轴: T (s)
```

#### `all_persistences` — 持续时间谱 (Persistence Spectrum)

由 STFT 功率 (dB) 在频率 × 功率 二维上做直方图得到。默认 `method='custom'`：每频率行归一化为概率（行和为 1）；功率轴由 `power_range_mode` 决定（推荐 `fixed` + `[0, 70]` dB，便于跨 JNR 训练）。

##### 多通道（当前默认，适合 CNN/ViT）

```text
变量名: all_persistences
类型:   single
形状:   [SAMPLE_NUM × H × W × C]   典型 [N × 224 × 224 × 3]
说明:   C 个功率分箱尺度各自做 persistence，再统一 resize 到 target_size
通道:   channel_power_bins = [224, 112, 32]
        ch1: 原生 224×224；ch2: 224×112 → 上采样；ch3: 224×32 → 上采样
配置:   cfg.persistence.channel_power_bins / target_size
功率轴: power_centers (dB)，长度 = W（与输出功率维对齐，跨度 = power_range_db）
频率轴: F (Hz)，长度 = Nfft（显示时若 H=Nfft 可直接对应）
同文件: channel_power_bins, target_size, num_power_bins (=max bins),
        power_range_mode, power_range_db, persistence_method, F
```

训练时单样本即为 `224×224×3`；PyTorch 常用 `permute` 成 `(C, H, W)`。

##### 单通道（兼容旧数据 / 关闭多尺度）

```text
变量名: all_persistences
类型:   single
形状:   [SAMPLE_NUM × Nfft × num_power_bins]   如 [N × 224 × 224]
说明:   单尺度功率直方图；channel_power_bins=[] 或标量时输出此格式
配置:   cfg.persistence.num_power_bins（默认 224）
功率轴: power_centers (dB)
频率轴: F (Hz)
```

| 配置项 | 含义 |
| :--- | :--- |
| `method` | `custom` 行概率（默认）；`matlab` 对齐 pspectrum 百分比；`legacy` 旧版 64-bin 单通道 |
| `channel_power_bins` | 向量 → 多通道；`[]` / 标量 → 单通道（`legacy` 下忽略） |
| `target_size` | 多通道输出 `[H, W]`，默认 `[224, 224]` |
| `power_range_mode` | `fixed` 全库统一功率轴；`auto` 按目录样本估算 |
| `power_range_db` | `fixed` 时的 `[lo, hi]` dB（建议 JNR 0–20 用 `[0, 70]`） |
| `legacy_num_power_bins` | 仅 `method='legacy'` 生效，默认 `64` |

三种方法的输出与兼容性差异见 [docs/persistence_methods.md](docs/persistence_methods.md)：`legacy`
输出 `[N, Nfft, 64]`，功率轴由首样本分位数确定，用于复现合并前数据集；`custom` 输出单通道
`[N, Nfft, bins]` 或多通道 `[N, H, W, C]`；`matlab` 额外保存逐样本的 `all_power_centers`。

#### `all_metadata` — 样本元数据

```json
[
  {
    "sample_idx": 1,
    "jam_types": ["DFTJ"],
    "JNR": 10,
    "SNR": -5,
    "pos": 1234,
    "B": 12500000,
    "taup": 2.3e-05,
    "mu": 5.43e11,
    "sweep_dir": 1,
    "jam_params": {
      "dftj_k": 5
    },
    "roles": ["D"],
    "component_params": [
      { "type": "DFTJ", "jam_info": { "k": 5, "JNR_actual": 9.98 } }
    ]
  }
]
```

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `sample_idx` | int | 样本序号 (1-based) |
| `jam_types` | string[] | 干扰类型缩写数组，单一干扰如 `["DFTJ"]`，混合干扰如 `["DFTJ","AJ"]`，纯LFM为 `"clean"` |
| `JNR` | float | 干噪比 (dB)，纯LFM时为 `NaN` |
| `SNR` | float | 信噪比 (dB)，仅纯LFM样本含此字段 |
| `pos` | int | 目标在 PRI 中的起始采样位置 |
| `B` | float | LFM 带宽 (Hz) |
| `taup` | float | LFM 脉宽 (s) |
| `mu` | float | LFM 调频斜率 (Hz/s) |
| `sweep_dir` | int | 扫频方向 (`1`=上扫, `-1`=下扫) |
| `jam_params` | object | 该样本的干扰生成参数 (因类型而异，纯LFM为空 `{}`) |
| `roles` | string[] | 各干扰分量角色，`D`=欺骗 / `S`=压制（`clean` 不计入） |
| `component_params` | object[] | 每个分量的 `{type, jam_info}`，与 `roles` 对齐 |

#### `all_features` — 多域特征

```json
[
  {
    "time_domain": { "skewness": 0.12, "kurtosis": 3.45, ... },
    "freq_domain": { "spectral_skewness": 0.34, ... },
    "bispectrum": { "bispectrum_variance": 0.001, ... },
    "wavelet": { "variance": 0.56, "mean": 1.23, ... },
    "statistical": { "shannon_entropy": 2.34, ... }
  }
]
```

包含 5 个域共 22 维特征 (详见 `load_features.py:46-75`)。

#### 时频表示 — WVD / PWVD / SPWVD / CWD

标准主流程只产出 STFT 与持久谱；WVD 族与 CWD 由后处理脚本从已生成的 `all_times` 转换：

```matlab
addpath('utils')
convert_times_to_tfr('output/<dir>/JNR_+10', 'force', true)
convert_times_to_tfr('output/<dir>/JNR_+10', 'modes', {'wvd','spwvd'}, ...
                     'lag_len', 256, 'native_size', 256, 'target_size', [224 224])
```

- 默认每种干扰类型取 1 个样本（`per_class=1`），lag 窗 256（MATLAB `wvd` 要求奇数，偶数自动 `-1`）
- 原生 `256×256` → resize `224×224`
- 输出与 `*_echo_times.mat` 同目录：`<dataset>_echo_wvds.mat` / `pwvds` / `spwvds` / `cwds`，
  变量分别为 `all_wvds`、`all_pwvds`、`all_spwvds`、`all_cwds`（实数 `[N, 224, 224]`）
- 实测开销可用 `benchmark_wvd_cost('output/<dir>/JNR_+10', 'max_classes', 3)`
- `web_viewer` 可直接浏览上述四种 `.mat`，见 [web_viewer/README.md](web_viewer/README.md)

#### 44 维快集特征

`extract_fast44.py` 在原 22 维多域特征基础上并入 TAGPNet 30 维物理统计，去掉双谱与近重复项，
得到 44 维快集；`eval_fast44.py` / `eval_fast44_loo.py` 提供线性/树/小 MLP/最近质心以及留一(LOO)诊断。
字段清单与实测结论见 [docs/FAST44.md](docs/FAST44.md)、[docs/fast44_feature_names.json](docs/fast44_feature_names.json)。

```bash
python extract_fast44.py --root output/<dir> --splits train val test --jnrs 0 5 10 15 20
python eval_fast44.py
```

### 标签体系

#### 干扰类型缩写与类别

**欺骗式干扰 (Deceptive)** — 8 种:

| 索引 | 缩写 | 中文名称 | 生成函数 |
| :---: | :---: | :--- | :--- |
| 1 | `CSJ` | 梳状谱干扰 | `generate_csj_jamming` |
| 2 | `DFTJ` | 密集假目标干扰 | `generate_dftj_jamming` |
| 3 | `ISRJ` | 间歇采样转发干扰 | `generate_isrj_jamming` |
| 4 | `ISCJ` | 间歇采样循环干扰 | `generate_iscj_jamming` |
| 5 | `MISRJ` | 间歇采样调制转发干扰 | `generate_misrj_jamming` |
| 6 | `ISDJ` | 间歇采样单独干扰 | `generate_isdj_jamming` |
| 7 | `C&IJ` | 切片交织干扰 | `generate_cij_jamming` |
| 8 | `SMSPJ` | 弥散谱干扰 | `generate_smspj_jamming` |

**压制干扰 (Suppressive)** — 9 种:

| 索引 | 缩写 | 中文名称 | 生成函数 |
| :---: | :---: | :--- | :--- |
| 9 | `AJ` | 瞄准干扰 | `generate_ab_jamming` |
| 10 | `BJ` | 阻塞干扰 | `generate_ab_jamming` |
| 11 | `SJ` | 扫频干扰 | `generate_sj_jamming` |
| 12 | `PJ` | 脉冲干扰 | `generate_pulse_jamming` |
| 13 | `NCJ` | 噪声卷积干扰 | `generate_ncj_jamming` |
| 14 | `NPJ` | 噪声乘积干扰 | `generate_npj_jamming` |
| 15 | `NFMJ` | 噪声调频干扰 | `generate_nfmj_jamming` |
| 16 | `NPMJ` | 噪声调相干扰 | `generate_npmj_jamming` |
| 17 | `NAMJ` | 噪声调幅干扰 | `generate_namj_jamming` |

> **注意**: 上述索引基于 `config_example.m` 中 `generation_plan` 的顺序。标签在 metadata 中以**字符串缩写**存储 (`jam_types` 字段), 不使用整数索引。若需整数标签, 可按此表映射, 或从 `generation_plan` 的顺序推导。

**混合干扰标签**格式: `"DFTJ+AJ"` (用 `+` 连接多个缩写, 顺序与 `generation_plan` 中的写法一致)。

**纯LFM标签**: `jam_types` 为 `"clean"`，表示无干扰样本。在分类任务中可作为第 18 类（"无干扰"），或用于 SNR 敏感性分析。

### PyTorch 数据加载

使用 `load_features.py` 加载特征数据:

```python
from load_features import SignalFeatureDataset
from torch.utils.data import DataLoader

dataset = SignalFeatureDataset(
    features_path='output/<date>/JNR_+10/train_echo_features.json',
    metadata_path='output/<date>/JNR_+10/train_echo_metadata.json'
)
dataloader = DataLoader(dataset, batch_size=32, shuffle=True)
```

标签从 metadata 的 `jam_types` 字段自动提取, `encode_labels()` 按字母序编码为整数, 映射表存储在 `dataset.label_map` 中。

---

## 统一数据集（分量级，170 类）

`main/main_generation_unified.m` 是独立于 `main_generation_v2.m` 的另一条入口，直接调用
`multi_generation_v2` 的第三返回值 `components`，把每个样本拆成可加的分量文件保存。
适合研究「干扰分量可加性 / 配对诊断 / 多标签组合」，不适合直接替代常规 JNR 数据集。

```matlab
main_generation_unified('smoke')   % 少量单元测试 → unified_20261118_smoke
main_generation_unified('full')    % 全量 → E:/GPCN_v2_data/unified_20261118
```

> 脚本顶部的 `root_path` / `out_root` 为硬编码路径，换机器时先修改这两处。

### 类别构成（170 类）

| 类别组 | 数量 | 命名示例 |
| :--- | :---: | :--- |
| 单干扰 `single` | 17 | `DFTJ`、`NCJ` |
| 欺骗×欺骗 `DD` | C(8,2)=28 | `DFTJ+CSJ` |
| 压制×压制 `SS` | C(9,2)=36 | `AJ+PJ` |
| 欺骗×压制 `DS` | 8×9=72 | `DFTJ+AJ` |
| 同类型双分量 `sameDD` / `sameSS` | 8 + 9 | `DFTJ+DFTJ`、`PJ+PJ` |

其中 44 个 **key cell**（`×PJ`、`×NCJ` 两列，以及 `ISDJ/ISRJ/SMSPJ/C&IJ` 四行 × 其余 7 个压制）
在 test 中生成更多样本。

### 目录与 split

```text
unified_20261118/
├── class_order.json              # 类别顺序、kind、key 标记、legacy 89 类映射
├── protocol.json                 # fs/PRI/窗口/SNR/JNR 范围/样本数/混合语义
├── generation.log
├── JNR_+0/{train,val,test}/<class_name>.mat|.json
├── JNR_+5/...
└── paired_diagnostic/JNR_+{0,20,50}/echo_XXXX.mat|.json
```

- **train/val**：JNR = `0:5:20`，仅 17 个单干扰类（`N_train=100`，`N_val=20`）
- **test**：JNR = `-10:5:50`，全部 170 类（普通类 `N_test=100`，key cell `N_key=200`）
- 每个 `(split, JNR, class)` 一个 `.mat` + 一个 `.json`；主集不重放，每个 cell 使用唯一 seed，
  样本内回波/噪声只属于该样本
- `paired_diagnostic/`：300 条回波实现 × 17 单类 × 3 个 JNR，**按设计共享 E/W**，仅用于诊断

### 分量 `.mat` 字段

| 变量 | 形状 (MATLAB) | 说明 |
| :--- | :--- | :--- |
| `J1r` / `J1i` | `[N_total, N] single` | 第 1 个干扰分量实部/虚部 |
| `J2r` / `J2i` | `[N_total, N] single` | 第 2 个干扰分量（双分量类才有） |
| `Er` / `Ei` | `[2400, N] single` | 回波，按 `Epos/Elen` 定位并零填充到 `E_max=2400` |
| `Epos` / `Elen` | `[1, N] uint16` | 回波段在 PRI 中的起点与长度 |
| `Wr` / `Wi` | `[N_total, N] single` | 单位功率复高斯噪声 |
| `class_name` / `class_index` | — | 类名与 0-based 类索引 |
| `split` / `jnr` / `n_components` / `seed` / `protocol_version` | — | 生成元信息 |

混合关系为 `rx = sum(jam components) + E + W`。h5py 读取后数组为 `(N, T)`（样本在前）。
`*.json` metadata 逐样本记录 `measured_component_jnr_db`（每分量 JNR）、
`measured_total_jnr_db`、`measured_snr_db`、`E_pos/E_len`、`echo_id/noise_id`。
注意 JNR 语义是**逐分量**的：总 JNR = 分量 JNR + `10log10(n_components)`。

`paired_diagnostic` 的 `.mat` 用 `Jr/Ji` 保存 17 个单类分量（`[8000, 17]`），
`Er/Ei/Epos/Elen/Wr/Wi` 同样带出，便于同一回波下比较不同干扰。

---

## 添加新干扰类型

如需添加新的干扰类型, 按以下步骤操作:

### 1. 创建生成器函数

在 `generators/deceptive/` 或 `generators/suppressive/` 下创建 `generate_<缩写>_jamming.m`:

```matlab
function [pure_jam, rx, jam_info] = generate_xxx_jamming(tx, params, mode)
% GENERATE_XXX_JAMMING - <干扰名称>
%
% 输入:
%   tx     - 基带发射信号
%   params - 参数结构体 (含 fs, fc, B, taup, JNR, PRI_samp 等)
%   mode   - 1=仅返回干扰信号, 2=返回干扰+目标回波, 3=返回干扰信息
%
% 输出:
%   pure_jam  - 纯干扰信号 (mode 1,2)
%   rx        - 干扰+目标回波+噪声 (mode 2)
%   jam_info  - 干扰参数字典 (mode 3, 用于 metadata)
```

**约定**:

- 缩写使用**大写字母**, 长度 2–5 个字符
- `pure_jam` 的长度必须与 `tx` 一致 (`params.N_total`)
- `jam_info` 为 struct 数组, 包含该干扰的关键参数 (会写入 metadata)

### 2. 在调度器中注册

编辑 [main/multi_generation_v2.m](main/multi_generation_v2.m), 在 `switch jam_type` 中添加新 case:

```matlab
case 'XXX'  % XXX - <干扰名称>
    jam_params = params;
    jam_params.JNR = current_jnr;
    [pure_jam, ~, jam_info] = generate_xxx_jamming(tx, jam_params, 1);
    metadata(m).jam_params.xxx_param1 = jam_info(1).param1;
```

调度器会在 `switch` 之后自动把 `pure_jam` 记入 `components(m).jams`（`clean` 除外）。
新增**欺骗式**类型时还需把它加入 `is_deceptive_type()` 的 `D` 列表，否则 `roles` 会被记为 `S`。

### 3. 在配置中声明

编辑 `config.m` (从 `config_example.m` 复制):

```matlab
% 将新类型加入对应列表
cfg.jamming.deceptive_types = {..., 'XXX'};   % 欺骗式
% 或
cfg.jamming.suppressive_types = {..., 'XXX'}; % 压制

% 如有特定参数, 添加:
cfg.jamming.xxx.param1 = <默认值>;

% 加入生成计划:
cfg.generation_plan = {
    ...
    'XXX', cfg.generation.SAMPLE_NUM_S;
};
```

### 4. 更新类别数

如果新增类型改变了基础类别总数 (当前为 17), 更新:

```matlab
cfg.jamming.numClasses = <新总数>;
```

### 5. 更新 README 标签表

在本文档的"标签体系"表格中添加新行。
