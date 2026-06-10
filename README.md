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
