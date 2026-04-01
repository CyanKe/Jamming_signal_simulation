# 雷达干扰信号生成代码

## 干扰类型列表

### 欺骗式干扰 (Deceptive Jamming)

| 标签 | 名称 | 缩写 | 说明 |
|------|------|------|------|
| 1 | 密集假目标干扰 | DFTJ | 生成多个假目标回波 |
| 2 | 间歇采样转发干扰 | ISRJ | 对信号进行间歇采样后转发 |
| 3 | 距离假目标干扰 | RGPO | 距离拖引，模拟假目标移动 |
| 4 | 速度假目标干扰 | VGPO | 速度拖引，模拟假目标速度变化 |
| 10 | 弥散谱干扰 | SMSPJ | STFT表现为陡峭斜线 |
| 11 | 切片交织干扰 | CIJ | 连续转发，STFT连续分布 |
| 15 | 梳状谱干扰 | CSJ | STFT表现为密集梳齿状斜线 |

### 压制干扰 (Suppressive Jamming)

| 标签 | 名称 | 缩写 | 说明 |
|------|------|------|------|
| 5 | 瞄准干扰 | AJ | 窄带瞄准式干扰 |
| 6 | 阻塞干扰 | BJ | 宽带阻塞式干扰 |
| 7 | 扫频干扰 | SJ | 频率扫描式干扰 |
| 8 | 噪声卷积干扰 | NCJ | 噪声与信号卷积 |
| 9 | 噪声乘积干扰 | NPJ | 噪声与信号相乘 |
| 12 | 噪声调频干扰 | NFMJ | 噪声调制频率 |
| 13 | 噪声调相干扰 | NPMJ | 噪声调制相位 |
| 14 | 噪声调幅干扰 | NAMJ | 噪声调制幅度 |
| 16 | 脉冲干扰 | PJ | 脉冲式干扰 |

## 混合干扰

支持多种干扰类型组合，如：
- `RGPO+AJ` (标签 `[3,5]`) - 距离拖引+瞄准干扰
- `DFTJ+AJ` (标签 `[1,5]`) - 密集假目标+瞄准干扰

## 代码结构

```
generators/
├── base/                 # 基础信号
│   └── generate_0base_signal.m
├── deceptive/            # 欺骗式干扰
│   ├── generate_1dftj_jamming.m
│   ├── generate_2isrj_jamming.m
│   ├── generate_3rgpo_jamming.m
│   ├── generate_4vgpo_jamming.m
│   ├── generate_10smspj_jamming.m
│   ├── generate_11cij_jamming.m
│   └── generate_15csj_jamming.m
└── suppressive/          # 压制干扰
    ├── generate_5ab_jamming.m
    ├── generate_7sj_jamming.m
    ├── generate_8ncj_jamming.m
    ├── generate_9npj_jamming.m
    ├── generate_12nfmj_jamming.m
    ├── generate_13npmj_jammingr.m
    ├── generate_14namj_jammingr.m
    └── generate_16pulse_jamming.m
```

## 使用方式

```matlab
cfg = config();  % 加载配置
run('main/main_generation_v2.m');  % 执行生成
```

修改 `config.m` 中的参数可调整：
- 各数据集 (train/val/test) 的生成计划
- 干噪比 (JNR)
- 干扰带宽等特定参数