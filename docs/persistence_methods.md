# 持续时间谱（Persistence Spectrum）三种方法

日期：2026-11-07　对应实现：`main_generation_v2.m` + `utils/compute_persistence_legacy.m`

合并分支 `5cac8db1` 时保留了两套实现，由 `cfg.persistence.method` 切换。

| method | 输出形状 | 功率轴 | 说明 |
|---|---|---|---|
| `'legacy'` | `[N, Nfft, 64]` | 由**首样本**的 1%..100% 分位 + ±3 dB 余量确定，全库共用 | 合并前的实现，用于复现既有 64-bin 数据集 |
| `'custom'` | 单通道 `[N, Nfft, bins]`；多通道 `[N, H, W, C]` | `power_range_mode = 'fixed'` 用 `power_range_db`；`'auto'` 按首样本估算 | 默认，支持 `channel_power_bins = [224,112,32]` 多通道 |
| `'matlab'` | 同上 | 逐样本 | 用 MATLAB 内建持久谱，功率轴每样本可能不同，额外保存 `all_power_centers` |

## 兼容性

`main_generation_v2.m` 开头会补全缺失字段：

- 没有 `cfg.persistence`（旧版 `config.m`）→ 自动按 `method = 'legacy'`、64 bin 处理，
  输出与合并前完全一致；
- 没有 `cfg.clean_lfm` → 视为 `enabled = false`。

新增字段（`config_example.m` 里都有）：

```matlab
cfg.persistence.method = 'custom';            % 'legacy' | 'custom' | 'matlab'
cfg.persistence.legacy_num_power_bins = 64;   % 仅 legacy 生效
cfg.clean_lfm.enabled = false;
cfg.clean_lfm.SNR_values = -5:5:20;
cfg.clean_lfm.SAMPLE_NUM = 50;
```

## 冒烟验证

三条分支都用 2 样本实跑通过（`NCJ`，JNR = 0 dB）：

| method | 配置 | 实际输出 |
|---|---|---|
| `legacy` | — | `[2 224 64]`，功率轴 `[-5.8, 42.7] dB` |
| `custom` 单通道 | `num_power_bins = 224`, `power_range_db = [0 70]` | `[2 224 224]` |
| `custom` 多通道 | `channel_power_bins = [224 112 32]` | `[2 224 224 3]` |

注意 `main_generation_v2.m` 开头有 `clear`，所以方法必须写在 `config.m` 里，
不能用脚本预先设置 workspace 变量。
