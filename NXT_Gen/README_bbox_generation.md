# 带Bounding Box的干扰数据生成指南

## 📋 概述

本指南介绍如何在生成干扰数据时直接计算bounding box，避免事后从STFT图中检测的误差。

## 🎯 核心优势

### 传统方法的问题
```
生成数据 → 保存STFT → Python脚本检测 → 得到bounding box
```
- 误差来源：
  1. STFT参数选择影响检测结果
  2. 阈值化参数影响边界框准确性
  3. 连通域分析可能漏检或误检
  4. 多个干扰区域可能被错误合并

### 新方法的优势
```
生成数据 → 同时计算bounding box → 保存数据+bounding box
```
- 精确性：基于干扰生成参数直接计算
- 一致性：与干扰类型完全匹配
- 可靠性：避免检测算法的不确定性

## 📁 文件结构

```
NXT_Gen/
├── main_generation_with_bbox.m          # 主生成脚本（带bounding box）
├── multi_generation_with_bbox.m         # 多干扰生成函数（带bounding box）
├── generate_1dftj_jamming_with_bbox.m   # 密集假目标干扰（带bounding box）
├── generate_5ab_jamming_with_bbox.m     # 瞄准/阻塞干扰（带bounding box）
├── generate_7sj_jamming_with_bbox.m     # 扫频干扰（带bounding box）
├── generate_10smspj_jamming_with_bbox.m # 弥散谱干扰（带bounding box）
├── generate_11cij_jamming_with_bbox.m   # 切片交织干扰（带bounding box）
├── generate_15csj_jamming_with_bbox.m   # 梳状谱干扰（带bounding box）
└── README_bbox_generation.md            # 本指南
```

## 🚀 使用方法

### 1. 运行生成脚本

```matlab
% 在MATLAB中运行
cd 'D:\VScode\Jamming_signal_simulation\NXT_Gen\'
main_generation_with_bbox
```

### 2. 生成的数据文件

每个JNR级别将生成以下文件：

```
JNR_+5/
├── val_echo_stfts.mat      # STFT数据 (64×124×样本数)
├── val_echo_times.mat      # 时域信号
├── val_echo_label.mat      # 标签 (one-hot编码)
└── val_echo_bboxes.mat     # Bounding box信息 (新增)
```

### 3. Bounding Box数据格式

`val_echo_bboxes.mat` 包含 `all_bboxes` 变量，是一个cell数组：
- 每个元素对应一个样本
- 每个样本可能有多个bounding box
- 格式：`[freq_idx_min, time_idx_min, freq_idx_max, time_idx_max]`

**示例**：
```matlab
% 加载bounding box数据
load('JNR_+5/val_echo_bboxes.mat', 'all_bboxes');

% 查看第1个样本的bounding box
bboxes_sample1 = all_bboxes{1};
% 输出示例: [10, 50, 20, 80]
% 含义: 频率索引10-20，时间索引50-80
```

## 📊 Bounding Box计算原理

### 1. 密集假目标干扰 (DFTJ)

**参数**：
- 假目标数量：`k = 3`（固定）
- 假目标间隔：`delay_time = 10μs`
- 带宽：`B = 10MHz`

**计算**：
```
时域起始：pos + m × delay_samp (m = 0, 1, 2)
时域宽度：Ntau = 1600点
频域范围：[fc - B/2, fc + B/2] = [35MHz, 45MHz]
```

**输出**：3个bounding box（每个假目标一个）

### 2. 瞄准/阻塞干扰 (AB)

**参数**：
- 干扰带宽：`BJ = 20MHz`（瞄准）或 `45MHz`（阻塞）
- 中心频率：`fc = 40MHz`

**计算**：
```
时域起始：1（全PRI覆盖）
时域结束：N_total
频域范围：[fc - BJ/2, fc + BJ/2]
```

**输出**：1个bounding box（覆盖整个时域）

### 3. 扫频干扰 (SJ)

**参数**：
- 扫频周期：`T_sweep = 20~40μs`
- 扫频带宽：`B1 = 8 × BJ = 80MHz`

**计算**：
```
时域起始：1（全PRI覆盖）
时域结束：N_total
频域范围：[fc - B1/2, fc + B1/2] = [0MHz, 80MHz]
```

**输出**：1个bounding box（覆盖整个时域和频域）

### 4. 弥散谱干扰 (SMSPJ)

**参数**：
- 压缩比：`M = 4~8`
- 带宽扩展：`B × M = 40~80MHz`

**计算**：
```
时域起始：pos + delay_samp
时域宽度：Ntau = 1600点
频域范围：[fc - B×M/2, fc + B×M/2]
```

**输出**：1个bounding box（频谱弥散）

### 5. 切片交织干扰 (C&IJ)

**参数**：
- 分段数：`a × b = 4~16`
- 每段长度：`T_seg_samp = Ntau/(a×b)`

**计算**：
```
时域起始：pos + delay_samp (每个分段)
时域宽度：T_seg_samp
频域范围：[fc - B/2, fc + B/2]
```

**输出**：多个bounding box（每个分段一个）

### 6. 梳状谱干扰 (CSJ)

**参数**：
- 梳齿数：`M = 3~10`
- 频率间隔：`delta_f = Q × B = 0.5~1.0MHz`
- 总带宽：`(M-1) × delta_f`

**计算**：
```
时域起始：pos
时域宽度：Ntau = 1600点
频域范围：[fc - (M-1)×delta_f/2, fc + (M-1)×delta_f/2]
```

**输出**：1个bounding box（覆盖所有梳齿）

## 📈 Bounding Box统计

### 每个样本的bounding box数量

| 干扰类型 | 中文名 | bounding box数量 | 说明 |
|---------|--------|-----------------|------|
| DFTJ | 密集假目标 | 3 | 每个假目标一个 |
| ISRJ | 间歇采样 | 1~4 | 取决于转发次数 |
| AB | 瞄准/阻塞 | 1 | 全时域覆盖 |
| SJ | 扫频 | 1 | 全时域覆盖 |
| SMSPJ | 弥散谱 | 1 | 单个脉冲 |
| C&IJ | 切片交织 | 4~16 | 每个分段一个 |
| CSJ | 梳状谱 | 1 | 覆盖所有梳齿 |

### Bounding box坐标范围

**STFT图像尺寸**：64频点 × 124时点

**坐标转换**：
- 频率索引：`0 ~ 63`
- 时间索引：`0 ~ 123`

**示例**：
```matlab
% DFTJ干扰的bounding box
bbox = [freq_idx_min, time_idx_min, freq_idx_max, time_idx_max]
% 例如: [10, 50, 20, 80]
% 表示: 频率索引10-20，时间索引50-80
```

## 🎨 可视化Bounding Box

### MATLAB可视化脚本

创建 `visualize_bboxes.m`：

```matlab
function visualize_bboxes(stft_file, bbox_file, sample_idx)
    % 加载数据
    load(stft_file, 'all_stfts');
    load(bbox_file, 'all_bboxes');

    % 获取单个样本
    stft_data = squeeze(all_stfts(sample_idx, :, :));
    bboxes = all_bboxes{sample_idx};

    % 显示STFT
    figure;
    imagesc(abs(stft_data));
    axis xy;
    xlabel('时间索引');
    ylabel('频率索引');
    title(sprintf('样本 %d 的STFT和Bounding Box', sample_idx));
    colormap(jet);

    % 绘制bounding box
    hold on;
    for i = 1:size(bboxes, 1)
        bbox = bboxes(i, :);
        % bbox格式: [freq_min, time_min, freq_max, time_max]
        rectangle('Position', ...
            [bbox(2), bbox(1), bbox(4)-bbox(2), bbox(3)-bbox(1)], ...
            'EdgeColor', 'r', 'LineWidth', 2);
    end
    hold off;
end
```

### 使用示例

```matlab
% 可视化第1个样本
visualize_bboxes('JNR_+5/val_echo_stfts.mat', ...
                 'JNR_+5/val_echo_bboxes.mat', 1);
```

## 🔄 转换为YOLO格式

### Python转换脚本

创建 `convert_bbox_to_yolo.py`：

```python
import h5py
import numpy as np
import os

def convert_bbox_to_yolo(stft_file, bbox_file, output_dir):
    """将MATLAB bounding box转换为YOLO格式"""

    # 加载数据
    with h5py.File(stft_file, 'r') as f:
        all_stfts = f['all_stfts'][:]

    with h5py.File(bbox_file, 'r') as f:
        all_bboxes = f['all_bboxes'][:]

    # STFT尺寸
    n_freq, n_time = all_stfts.shape[1], all_stfts.shape[2]

    # 创建输出目录
    images_dir = os.path.join(output_dir, 'images')
    labels_dir = os.path.join(output_dir, 'labels')
    os.makedirs(images_dir, exist_ok=True)
    os.makedirs(labels_dir, exist_ok=True)

    # 转换每个样本
    for i in range(all_stfts.shape[0]):
        # 保存图像
        stft_data = all_stfts[i, :, :]
        magnitude = np.abs(stft_data)
        normalized = (magnitude - magnitude.min()) / (magnitude.max() - magnitude.min())
        image_uint8 = (normalized * 255).astype(np.uint8)

        import cv2
        image_path = os.path.join(images_dir, f'sample_{i:06d}.png')
        cv2.imwrite(image_path, image_uint8)

        # 转换bounding box为YOLO格式
        bboxes = all_bboxes[i]
        yolo_labels = []

        if bboxes.size > 0:
            for bbox in bboxes:
                # bbox格式: [freq_min, time_min, freq_max, time_max]
                freq_min, time_min, freq_max, time_max = bbox

                # 计算YOLO格式
                x_center = (time_min + time_max) / 2 / n_time
                y_center = (freq_min + freq_max) / 2 / n_freq
                width = (time_max - time_min) / n_time
                height = (freq_max - freq_min) / n_freq

                # class_id = 0 (干扰)
                yolo_labels.append([0, x_center, y_center, width, height])

        # 保存标签
        label_path = os.path.join(labels_dir, f'sample_{i:06d}.txt')
        with open(label_path, 'w') as f:
            for label in yolo_labels:
                f.write(f'{label[0]} {label[1]:.6f} {label[2]:.6f} {label[3]:.6f} {label[4]:.6f}\n')

    print(f'转换完成: {output_dir}')

# 使用示例
convert_bbox_to_yolo(
    stft_file='JNR_+5/val_echo_stfts.mat',
    bbox_file='JNR_+5/val_echo_bboxes.mat',
    output_dir='output/yolo_dataset'
)
```

## 📋 完整工作流程

### 1. 生成数据（MATLAB）

```matlab
% 运行主生成脚本
cd 'D:\VScode\Jamming_signal_simulation\NXT_Gen\'
main_generation_with_bbox
```

### 2. 验证数据

```matlab
% 加载并检查数据
load('JNR_+5/val_echo_stfts.mat', 'all_stfts');
load('JNR_+5/val_echo_bboxes.mat', 'all_bboxes');

fprintf('STFT数据形状: %s\n', mat2str(size(all_stfts)));
fprintf('样本数: %d\n', length(all_bboxes));

% 检查第一个样本
bboxes1 = all_bboxes{1};
fprintf('样本1的bounding box数量: %d\n', size(bboxes1, 1));
```

### 3. 可视化检查

```matlab
% 可视化前5个样本
for i = 1:5
    visualize_bboxes('JNR_+5/val_echo_stfts.mat', ...
                     'JNR_+5/val_echo_bboxes.mat', i);
    pause(2);
end
```

### 4. 转换为YOLO格式（Python）

```bash
cd d:\VScode\project_JR\src\yolo
python convert_bbox_to_yolo.py
```

### 5. 训练YOLO模型

```bash
# 使用转换后的数据训练
yolo train data=output/yolo_dataset/data.yaml model=yolov8n.pt epochs=100
```

## 🎯 Bounding Box准确性优势

### 与传统方法对比

| 指标 | 传统方法（事后检测） | 新方法（生成时计算） |
|------|-------------------|-------------------|
| **准确性** | 依赖阈值参数 | 基于干扰参数直接计算 |
| **一致性** | 可能因参数变化 | 完全一致 |
| **漏检率** | 可能漏检弱干扰 | 100%检测 |
| **误检率** | 可能误检噪声 | 0%误检 |
| **多干扰处理** | 可能合并错误 | 独立计算 |
| **参数敏感性** | 高（阈值、面积等） | 低（仅依赖干扰参数） |

### 示例对比

**密集假目标干扰 (DFTJ)**：

传统方法：
```
STFT图 → 阈值化 → 连通域分析 → 可能合并为1个bbox
```

新方法：
```
参数计算 → 3个独立bbox → 每个假目标精确位置
```

## 🔧 自定义扩展

### 添加新的干扰类型

1. 创建新的生成函数：`generate_XXtype_with_bbox.m`
2. 在 `multi_generation_with_bbox.m` 中添加case
3. 在 `main_generation_with_bbox.m` 的 `generation_plan` 中添加

### 修改bounding box计算

在生成函数中修改：
```matlab
% 计算bounding box
x_min = ...;  % 时域起始
x_max = ...;  % 时域结束
y_min = ...;  % 频域起始（Hz）
y_max = ...;  % 频域结束（Hz）

bbox_info = [x_min, y_min, x_max, y_max];
```

## 📝 注意事项

1. **坐标系统**：
   - 时域：采样点索引（1 ~ N_total）
   - 频域：频率值（Hz）
   - STFT图像：频率索引（0 ~ 63），时间索引（0 ~ 123）

2. **边界处理**：
   - 确保bounding box不超出信号范围
   - 处理边界情况（起始/结束位置）

3. **多干扰叠加**：
   - 多个干扰的bounding box会叠加
   - 在YOLO训练时，重叠区域会被正确处理

4. **数据验证**：
   - 建议可视化检查bounding box
   - 确保与干扰类型匹配

## 🚀 下一步

1. ✅ 运行 `main_generation_with_bbox.m` 生成数据
2. ✅ 检查生成的bounding box文件
3. ✅ 可视化验证bounding box准确性
4. ✅ 转换为YOLO格式
5. ✅ 训练YOLO模型

---

**优势总结**：
- ✅ 精确性：基于干扰参数直接计算
- ✅ 一致性：避免检测算法的不确定性
- ✅ 可靠性：100%检测，0%误检
- ✅ 灵活性：支持多种干扰类型
- ✅ 可扩展：易于添加新干扰类型
