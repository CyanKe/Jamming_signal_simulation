# 信号特征提取 - 使用说明

## 一、特征提取流程

```
信号生成 (main_generation_v2.m)
    ↓
多域特征提取 (extract_signal_features.m)
    ↓
保存为 JSON (test_echo_features.json)
    ↓
Python 加载 (load_features.py → PyTorch Tensor)
```

---

## 二、特征列表 (22个)

### 1. 时域特征 (5个)

| 特征名 | 字段 | 说明 |
|--------|------|------|
| 矩偏度 | `time_domain.skewness` | 三阶中心矩/标准差³，衡量分布不对称性 |
| 矩峰度 | `time_domain.kurtosis` | 四阶中心矩/标准差⁴ − 3，衡量分布尖锐度 |
| 包络起伏度 | `time_domain.envelope_variation` | Hilbert包络的标准差/均值 |
| 调制带宽 | `time_domain.modulation_bandwidth` | 瞬时频率的最大变化范围 (Hz) |
| 调制速率 | `time_domain.modulation_rate` | 瞬时频率的变异系数 |

### 2. 频域特征 (4个)

| 特征名 | 字段 | 说明 |
|--------|------|------|
| 频谱偏度 | `freq_domain.spectral_skewness` | 频谱的三阶矩 |
| 频谱峰度 | `freq_domain.spectral_kurtosis` | 频谱的四阶矩 |
| 载波因子 | `freq_domain.carrier_factor` | 载波附近能量/总能量 |
| AWGN因子 | `freq_domain.awgn_factor` | 频谱平坦度，衡量噪声含量 |

### 3. 双谱域特征 (2个)

| 特征名 | 字段 | 说明 |
|--------|------|------|
| 双谱方差 | `bispectrum.bispectrum_variance` | 双谱的方差 |
| 双谱均值 | `bispectrum.bispectrum_mean` | 双谱的均值 |

### 4. 小波域特征 (8个)

| 特征名 | 字段 | 说明 |
|--------|------|------|
| 方差 | `wavelet.variance` | 小波系数的方差 |
| 均值 | `wavelet.mean` | 小波系数的绝对均值 |
| 最大值 | `wavelet.max` | 小波系数的绝对值最大值 |
| 尺度重心 | `wavelet.scale_centroid` | 各尺度能量的加权中心 |
| 最大奇异值 | `wavelet.max_singular_value` | 小波系数矩阵SVD最大奇异值 |
| 二阶中心矩 | `wavelet.central_moment_2` | 小波系数的二阶矩 |
| 三阶中心矩 | `wavelet.central_moment_3` | 小波系数的三阶矩 |
| 四阶中心矩 | `wavelet.central_moment_4` | 小波系数的四阶矩 |

### 5. 统计域特征 (3个)

| 特征名 | 字段 | 说明 |
|--------|------|------|
| 信息熵 | `statistical.shannon_entropy` | Shannon熵 |
| 指数熵 | `statistical.exponential_entropy` | 指数型熵 |
| 范数熵 | `statistical.norm_entropy` | L2范数/√N |

---

## 三、特征生成 (MATLAB)

### 单独测试

运行测试脚本查看各干扰类型的特征值：

```matlab
>> test_feature_extraction
```

输出：
- 控制台打印各信号的特征值
- Figure窗口显示特征对比柱状图和波形图
- `utils/test_features_output.json` 保存测试结果

### 批量生成

在配置文件中设置好生成计划，运行主程序：

```matlab
>> main_generation_v2
```

输出目录结构：

```
output/
└── 20us_multi/
    └── JNR_+10/
        ├── test_echo_stfts.mat        % STFT时频谱
        ├── test_echo_times.mat        % 时域信号
        ├── test_echo_metadata.json    % 样本元数据（含干扰类型标签）
        ├── test_echo_features.json    % 多域特征
        └── generation_plan.json       % 生成计划
```

---

## 四、特征保存格式 (JSON)

```json
[
  {
    "time_domain": {
      "skewness": 0.0123,
      "kurtosis": -0.4567,
      "envelope_variation": 0.5678,
      "modulation_bandwidth": 1234567.0,
      "modulation_rate": 0.2345
    },
    "freq_domain": {
      "spectral_skewness": 1.2345,
      "spectral_kurtosis": 2.3456,
      "carrier_factor": 0.1234,
      "awgn_factor": 0.5678
    },
    "bispectrum": {
      "bispectrum_variance": 123.456,
      "bispectrum_mean": 45.678
    },
    "wavelet": {
      "variance": 0.5678,
      "mean": 0.1234,
      "max": 2.3456,
      "scale_centroid": 3.2,
      "max_singular_value": 12.345,
      "central_moment_2": 0.5678,
      "central_moment_3": 0.0123,
      "central_moment_4": 0.8901
    },
    "statistical": {
      "shannon_entropy": 4.5678,
      "exponential_entropy": -0.2345,
      "norm_entropy": 0.7890
    }
  },
  ...
]
```

---

## 五、Python 加载 (PyTorch)

### 安装依赖

```bash
pip install torch numpy
```

### 快速加载

```bash
# 仅特征
python load_features.py --features_path output/20us_multi/JNR_+10/test_echo_features.json

# 特征 + 标签
python load_features.py \
    --features_path output/20us_multi/JNR_+10/test_echo_features.json \
    --metadata_path output/20us_multi/JNR_+10/test_echo_metadata.json
```

### 代码示例

```python
from load_features import SignalFeatureDataset, features_to_tensor
from torch.utils.data import DataLoader

# 创建Dataset
dataset = SignalFeatureDataset(
    features_path='output/20us_multi/JNR_+10/test_echo_features.json',
    metadata_path='output/20us_multi/JNR_+10/test_echo_metadata.json'
)

# DataLoader
loader = DataLoader(dataset, batch_size=32, shuffle=True)

for X_batch, y_batch in loader:
    print(X_batch.shape)  # [32, 22]
    print(y_batch.shape)  # [32]
```

### 自定义特征选择

```python
from load_features import load_features_json, features_to_tensor

features = load_features_json('path/to/features.json')

# 只选择部分特征
keys = [
    'time_domain.skewness',
    'time_domain.kurtosis',
    'freq_domain.carrier_factor',
    'freq_domain.awgn_factor',
    'statistical.shannon_entropy',
]
X, _ = features_to_tensor(features, feature_keys=keys)
print(X.shape)  # [N, 5]
```

---

## 六、完整训练示例

```python
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from load_features import SignalFeatureDataset

# 1. 加载数据
train_set = SignalFeatureDataset(
    features_path='output/20us_multi/JNR_+10/test_echo_features.json',
    metadata_path='output/20us_multi/JNR_+10/test_echo_metadata.json'
)
train_loader = DataLoader(train_set, batch_size=32, shuffle=True)

# 2. 定义模型
model = nn.Sequential(
    nn.Linear(22, 64),
    nn.ReLU(),
    nn.Dropout(0.3),
    nn.Linear(64, 32),
    nn.ReLU(),
    nn.Linear(32, len(train_set.label_map)),
)

# 3. 训练
criterion = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

for epoch in range(50):
    for X, y in train_loader:
        pred = model(X)
        loss = criterion(pred, y)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
    print(f'Epoch {epoch+1}, Loss: {loss.item():.4f}')
```

---

## 七、相关文件索引

| 文件 | 作用 |
|------|------|
| `utils/extract_signal_features.m` | 主特征提取函数 |
| `utils/features/extract_time_domain_features.m` | 时域特征 |
| `utils/features/extract_freq_domain_features.m` | 频域特征 |
| `utils/features/extract_bispectrum_features.m` | 双谱域特征 |
| `utils/features/extract_wavelet_features.m` | 小波域特征 |
| `utils/features/extract_statistical_features.m` | 统计域特征 |
| `utils/test_feature_extraction.m` | MATLAB测试脚本 |
| `utils/visualize_features_json.m` | 特征可视化 |
| `load_features.py` | Python/PyTorch加载 |
| `main/main_generation_v2.m` | 主生成程序（已集成特征提取） |

---

## 八、注意事项

1. **复数信号处理**：所有特征提取函数内部会自动取 `real(signal)` 处理
2. **双谱计算**：使用间接法（三阶累积量→2D FFT），速度较慢，`nfft` 参数可调（默认128）
3. **小波基**：默认使用 db4，可通过 `params.wavelet_type` 修改
4. **特征归一化**：PyTorch训练前建议对特征做标准化处理
5. **JSON序列化**：MATLAB的 `jsonencode` 可能对大数值使用科学计数法，Python解析时需注意