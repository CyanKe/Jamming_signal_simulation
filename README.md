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

## 混合干扰

支持多种干扰类型组合，如：

- `RGPO+AJ` (标签 `[3,5]`) - 距离拖引+瞄准干扰
- `DFTJ+AJ` (标签 `[1,5]`) - 密集假目标+瞄准干扰

## 代码结构

```text
├── config.m / config_example.m     # 配置文件(使用config.m)
├── load_features.py                # PyTorch 特征加载桥接脚本
├── umap_stft.py                    # UMAP 可视化脚本
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
│       ├── generate_nfmj_jamming.m
│       ├── generate_npmj_jamming.m
│       ├── generate_namj_jamming.m
│       └── generate_pulse_jamming.m
│
├── main/                           # 主入口
│   ├── main_generation_v2.m        # 主生成流程 (v2, 字符串标签)
│   ├── multi_generation_v2.m       # 干扰调度器 (v2)
│   ├── main_generation.m           # 主生成流程 (v1, 整数标签, 已废弃)
│   ├── multi_generation.m          # 干扰调度器 (v1, 已废弃)
│   ├── main_generation_CWD.m       # CWD 时频分析生成
│   ├── main_dechirp.m              # Dechirp 后处理
│   ├── main_feature_extract.m      # 特征提取入口
│   └── generate_jam_type_samples.m # 按干扰类型生成样本
│
├── utils/                          # 工具函数
│   ├── config_to_params.m          # 配置→参数结构体
│   ├── extract_signal_features.m   # 特征提取编排器
│   ├── test_feature_extraction.m   # 特征提取测试
│   ├── visualize_features_json.m   # 特征可视化
│   ├── CWD.m / CWD.md              # Choi-Williams 分布
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
└── tests/                          # 测试
    ├── test_all_deceptive_jnr.m    # 欺骗式干扰 JNR 验证
    └── test_all_suppressive_jnr.m  # 压制干扰 JNR 验证
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

---

## 数据集格式说明

### 输出文件

每个 JNR 目录下生成以下文件：

| 文件名 | 格式 | 说明 |
| :--- | :--- | :--- |
| `<dataset>_echo_times.mat` | `.mat` (v7.3) | 时域信号 |
| `<dataset>_echo_stfts.mat` | `.mat` (v7.3) | STFT 时频谱 (可选) |
| `<dataset>_echo_persistences.mat` | `.mat` (v7.3) | 持续时间谱 (可选) |
| `<dataset>_echo_features.json` | JSON | 多域特征 (可选) |
| `<dataset>_echo_metadata.json` | JSON | 样本元数据 (含标签) |
| `generation_plan.mat` / `.json` | `.mat` / JSON | 生成计划 |

其中 `<dataset>` 为 `train` / `val` / `test`，由 `cfg.output.dataset_type` 控制。

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

**多通道（当前默认，适合 CNN/ViT）**

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

**单通道（兼容旧数据 / 关闭多尺度）**

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
| `channel_power_bins` | 向量 → 多通道；`[]` / 标量 → 单通道 |
| `target_size` | 多通道输出 `[H, W]`，默认 `[224, 224]` |
| `power_range_mode` | `fixed` 全库统一功率轴；`auto` 按目录样本估算 |
| `power_range_db` | `fixed` 时的 `[lo, hi]` dB（建议 JNR 0–20 用 `[0, 70]`） |
| `method` | `custom` 行概率；`matlab` 对齐 pspectrum 百分比 |

#### `all_metadata` — 样本元数据

```json
[
  {
    "sample_idx": 1,
    "jam_types": ["DFTJ"],
    "JNR": 10,
    "pos": 1234,
    "jam_params": {
      "dftj_k": 5
    }
  }
]
```

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `sample_idx` | int | 样本序号 (1-based) |
| `jam_types` | string[] | 干扰类型缩写数组, 单一干扰如 `["DFTJ"]`, 混合干扰如 `["DFTJ","AJ"]` |
| `JNR` | float | 干噪比 (dB) |
| `pos` | int | 目标在 PRI 中的起始采样位置 |
| `jam_params` | object | 该样本的干扰生成参数 (因类型而异) |

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

**混合干扰标签**格式: `"DFTJ+AJ"` (用 `+` 连接多个缩写, 按字母序排列)。

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
