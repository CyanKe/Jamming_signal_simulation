# NCJ / NPJ 的存储-转发（store-and-forward）选项

日期：2026-11-07　对应实现：`generate_ncj_sf_jamming.m` / `generate_npj_sf_jamming.m`

## 1. 为什么需要这个开关

### 现状

原生成器对每个样本只产生**一个 PRI 的干扰模板**，然后复制到 `Np` 个脉冲：

```matlab
jam_pri = zeros(1, PRI_samp);
% ... 在一个 PRI 内生成干扰 ...
pure_jam(m,:) = repmat(jam_pri, 1, Np);
```

当 `cfg.signal.Np = 1`（当前配置）时，`repmat` 是空操作，样本就是一个 PRI，
**跨脉冲相干性根本不存在，也无法从数据里验证**。

当 `Np > 1` 时，`repmat` 意味着**整帧所有脉冲共用同一段波形**——这本身
就是 `U = Np` 的存储-转发。

### 这个属性为什么重要

噪声卷积干扰（NCJ）与噪声乘积干扰（NPJ）在文献里常被描述为「兼具压制与欺骗」。
这句话成立与否取决于**脉间关系**，而单 PRI 波形统计完全相同：

| 实现方式 | 脉间相关 | MTD 相干增益 | 雷达端表现 |
|---|---:|---:|---|
| 每个 PRI 重新产生噪声（`U = 1`） | ≈ 0.02–0.06 | 0 dB | 只有压制 |
| 整帧复用同一段波形（`U = Np`） | 1.000 | 10·log10(Np) | 压制 + 相干假峰 |

实测（`tests/test_ncj_npj_sf.m`，Np=16）：

| U | 1 | 2 | 4 | 8 | 16 |
|---|---:|---:|---:|---:|---:|
| 脉间相关（均值） | 0.060 | 0.117 | 0.248 | 0.514 | 1.000 |
| MTD 相干增益 | 0.05 | 3.42 | 6.14 | 9.11 | 12.04 dB |
| 理论 10log10(min(U,Np)) | 0 | 3.01 | 6.02 | 9.03 | 12.04 dB |

增益与理论值偏差 ≤ 0.4 dB。

## 2. 怎么用

`config.m`（或 `config_example.m` 里的模板）中：

```matlab
cfg.signal.Np = 16;          % 需要 > 1 才生效
cfg.jamming.ncj.U = 16;      % 16 = 整帧同一波形；1 = 每脉冲新噪声
cfg.jamming.npj.U = 16;
% 可选：块内每脉冲相位漂移（rad），模拟 DRFM 相位漂移，会削弱相干积累
% cfg.jamming.ncj.drift_per_pulse = 0.2;
```

不设 `U` 或 `Np = 1` 时，调度器自动走原生成器，输出与既有数据集完全一致。

`multi_generation_v2` 的开关逻辑：

```matlab
if sf_enabled(cfg, 'ncj', params)      % 需要 cfg.jamming.ncj.U 存在且 Np > 1
    ...generate_ncj_sf_jamming...
else
    ...generate_ncj_jamming...          % 原路径
end
```

生成的 metadata 会多出 `ncj_U` / `ncj_n_blocks`（或 `npj_*`），便于事后筛选。

## 3. 与原生成的差异（只有一处）

新版本对**整帧**做精确功率归一化：`RMS = Aj = 10^(JNR/20)`。

原 `generate_ncj_jamming` 没有帧级归一化，因此其实际功率等于
`Aj × (切片 std / 全段 std)`，逐样本有约 ±0.2 dB 的随机偏差
（实测 Np=1 时 +0.19 dB）。`generate_npj_jamming` 因为片段被精确归一化到
std=1，偏差可忽略（+0.001 dB）。

所以 Np=1 时两者**波形完全相同（相关系数 = 1.000000000000）、幅度相差一个常数**。
若需要与旧数据集逐位对齐，把两个 SF 函数末尾的归一化那三行去掉即可。

## 4. 验证

```matlab
cd tests
test_ncj_npj_sf      % 生成器级：形状一致 / 功率 / 占空比 / 脉间相关 / MTD 增益
test_sf_dispatch     % 调度级：开关是否按 Np 和 U 正确生效
```

`test_ncj_npj_sf` 的检查项：

1. Np=1 时与原生成器形状一致（corr = 1）
2. 整帧 RMS 恒等于 Aj（误差 < 1e-9）
3. 时间占空比 = `Ntau/PRI_samp`（实测 0.200）
4. `U=1` 脉间相关 < 0.15；`U=Np` 脉间相关 = 1.000
5. MTD 相干增益 = `10log10(min(U,Np))`（偏差 < 1 dB）

## 5. 与下游流程的关系

`Np > 1` 时 `generate_0base_signal` 已支持（`N_total = Np*PRI_samp`），
生成器层没有问题；但后续的 STFT / 持久谱 / 特征提取当前按单 PRI 设计
（`main_generation_v2.m` 里大量使用 `all_times(i, 1:params.PRI_samp)`）。
因此：

- **单 PRI 识别任务**：保持 `Np = 1`，本次改动不影响任何既有结果；
- **脉间效能评估**：设 `Np > 1` 并用 `U` 扫参，可以从生成器直接拿到
  CPI 级信号，配合外部处理链（匹配滤波 → MTD → CFAR）评估。

## 6. 参考

- NCJ 的支撑段正好等于一个脉宽（`jam_kernel = lfm`，原作者把门控 `squa` 注释掉了），
  实测占空比 17%（`Ntau/PRI_samp`），故其突发只覆盖 PRI 的一小段。
- 这与 `AJ` 等铺满整个 PRI 的压制干扰在时频图上完全不同，也与
  `PJ`（周期性脉冲）不同。
