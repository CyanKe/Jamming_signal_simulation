#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
load_features.py - 在PyTorch中加载特征JSON文件

用法:
    python load_features.py --features_path output/20us_multi/JNR_+10/test_echo_features.json
    python load_features.py --features_path output/20us_multi/JNR_+10/test_echo_features.json --metadata_path output/20us_multi/JNR_+10/test_echo_metadata.json
"""

import json
import argparse
from pathlib import Path

import torch
from torch.utils.data import Dataset, DataLoader


def load_features_json(json_path):
    """加载特征JSON文件，返回特征字典列表"""
    with open(json_path, 'r', encoding='utf-8') as f:
        features = json.load(f)
    print(f'加载特征文件: {json_path}')
    print(f'样本数: {len(features)}')
    return features


def load_metadata_json(json_path):
    """加载metadata JSON文件，返回标签列表"""
    with open(json_path, 'r', encoding='utf-8') as f:
        metadata = json.load(f)
    print(f'加载元数据文件: {json_path}')
    return metadata


def features_to_tensor(features, feature_keys=None):
    """将特征字典列表转换为PyTorch张量

    参数:
        features: JSON解析后的特征列表
        feature_keys: 要提取的特征键名列表，None表示全部

    返回:
        torch.Tensor, shape = [num_samples, num_features]
    """
    if feature_keys is None:
        feature_keys = [
            # 时域
            'time_domain.skewness',
            'time_domain.kurtosis',
            'time_domain.envelope_variation',
            'time_domain.modulation_bandwidth',
            'time_domain.modulation_rate',
            # 频域
            'freq_domain.spectral_skewness',
            'freq_domain.spectral_kurtosis',
            'freq_domain.carrier_factor',
            'freq_domain.awgn_factor',
            # 双谱域
            'bispectrum.bispectrum_variance',
            'bispectrum.bispectrum_mean',
            # 小波域
            'wavelet.variance',
            'wavelet.mean',
            'wavelet.max',
            'wavelet.scale_centroid',
            'wavelet.max_singular_value',
            'wavelet.central_moment_2',
            'wavelet.central_moment_3',
            'wavelet.central_moment_4',
            # 统计域
            'statistical.shannon_entropy',
            'statistical.exponential_entropy',
            'statistical.norm_entropy',
        ]

    batch = []
    for f in features:
        row = []
        for key in feature_keys:
            parts = key.split('.')
            val = f
            for p in parts:
                val = val[p]
            row.append(val)
        batch.append(row)

    return torch.tensor(batch, dtype=torch.float32), feature_keys


def get_labels_from_metadata(metadata):
    """仃metadata中提取标签"""
    jam_types_list = []
    for m in metadata:
        jt = m.get('jam_types', '')
        if isinstance(jt, list):
            jt = '+'.join(jt)
        jam_types_list.append(jt)
    return jam_types_list


def encode_labels(labels):
    """将字符串标签编码为整数"""
    unique_labels = sorted(set(labels))
    label_to_idx = {l: i for i, l in enumerate(unique_labels)}
    encoded = [label_to_idx[l] for l in labels]
    return torch.tensor(encoded, dtype=torch.long), label_to_idx


class SignalFeatureDataset(Dataset):
    """信号特征PyTorch Dataset"""

    def __init__(self, features_path, metadata_path=None):
        self.features = load_features_json(features_path)
        self.feature_tensor, self.feature_keys = features_to_tensor(self.features)

        self.labels = None
        self.label_map = None
        if metadata_path and Path(metadata_path).exists():
            metadata = load_metadata_json(metadata_path)
            labels_str = get_labels_from_metadata(metadata)
            self.labels, self.label_map = encode_labels(labels_str)
            print(f'标签映射: {self.label_map}')

        print(f'特征张量形状: {self.feature_tensor.shape}')

    def __len__(self):
        return len(self.features)

    def __getitem__(self, idx):
        x = self.feature_tensor[idx]
        if self.labels is not None:
            y = self.labels[idx]
            return x, y
        return x


def main():
    parser = argparse.ArgumentParser(description='加载特征JSON文件到PyTorch')
    parser.add_argument('--features_path', type=str, required=True,
                        help='特征JSON文件路径')
    parser.add_argument('--metadata_path', type=str, default=None,
                        help='元数据JSON文件路径')
    parser.add_argument('--batch_size', type=int, default=32,
                        help='批次大小')
    parser.add_argument('--info', action='store_true', default=True,
                        help='打印特征统计信息')
    args = parser.parse_args()

    dataset = SignalFeatureDataset(args.features_path, args.metadata_path)
    dataloader = DataLoader(dataset, batch_size=args.batch_size, shuffle=True)

    if args.info:
        X = dataset.feature_tensor
        print(f'\n特征统计:')
        print(f'  形状: {X.shape}')
        print(f'  范围: [{X.min().item():.4f}, {X.max().item():.4f}]')
        print(f'  均值: {[f"{v:.4f}" for v in X.mean(dim=0).tolist()]}')
        print(f'  标准差: {[f"{v:.4f}" for v in X.std(dim=0).tolist()]}')

    print(f'\nDataLoader示例:')
    for batch in dataloader:
        if isinstance(batch, (list, tuple)):
            X_batch, y_batch = batch
            print(f'  特征批次: {X_batch.shape}')
            print(f'  标签批次: {y_batch.shape}')
            print(f'  标签值: {y_batch.tolist()}')
        else:
            X_batch = batch
            print(f'  特征批次: {X_batch.shape}')
        break

    num_features = dataset.feature_tensor.shape[1]
    num_classes = len(dataset.label_map) if dataset.label_map else 2

    model = torch.nn.Sequential(
        torch.nn.Linear(num_features, 64),
        torch.nn.ReLU(),
        torch.nn.Dropout(0.3),
        torch.nn.Linear(64, 32),
        torch.nn.ReLU(),
        torch.nn.Linear(32, num_classes),
    )
    print(f'\n示例: 构建MLP分类器')
    print(f'  输入特征数: {num_features}')
    print(f'  输出类别数: {num_classes}')
    print(f'  MLP结构:')
    print(f'    {model}')


if __name__ == '__main__':
    main()
