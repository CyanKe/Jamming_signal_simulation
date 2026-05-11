function features = extract_signal_features(signal, fs, params)
% extract_signal_features - 多域信号特征提取主函数
%
% 输入:
%   signal - 输入信号（时域）
%   fs     - 采样频率
%   params - 可选参数结构体
%       .wavelet_type    - 小波类型（默认 'db4'）
%       .wavelet_level   - 小波分解层数（默认 5）
%       .bispectrum_nfft - 双谱FFT点数（默认 128）
%
% 输出:
%   features - 包含所有特征的结构体
%       .time_domain    - 时域特征
%       .freq_domain    - 频域特征
%       .bispectrum     - 双谱域特征
%       .wavelet        - 小波域特征
%       .statistical    - 统计域特征
%
% 特征列表:
%   时域: 矩偏度、矩峰度、包络起伏度、快速脉内调制识别参数(调制带宽、调制速率)
%   频域: 矩偏度、矩峰度、载波因子、加性高斯白噪声因子
%   双谱域: 双谱方差、双谱均值
%   小波域: 方差、均值、最大值、尺度重心、最大奇异值、中心矩特征(2-4阶)
%   统计域: 信息熵、指数熵、范数熵
%
% 示例:
%   fs = 100e6;
%   signal = randn(1000, 1);
%   features = extract_signal_features(signal, fs);
%
% Author: Claude Code
% Date: 2026-05-06

    %% 参数默认值
    if nargin < 3
        params = struct();
    end

    if ~isfield(params, 'wavelet_type')
        params.wavelet_type = 'db4';
    end

    if ~isfield(params, 'wavelet_level')
        params.wavelet_level = 5;
    end

    if ~isfield(params, 'bispectrum_nfft')
        params.bispectrum_nfft = 128;
    end

    %% 确保信号是列向量
    signal = signal(:)';

    %% 初始化特征结构体
    features = struct();

    %% 1. 时域特征
    features.time_domain = extract_time_domain_features(signal, fs);

    %% 2. 频域特征
    features.freq_domain = extract_freq_domain_features(signal, fs);

    %% 3. 双谱域特征
    features.bispectrum = extract_bispectrum_features(signal, fs, params.bispectrum_nfft);

    %% 4. 小波域特征
    features.wavelet = extract_wavelet_features(signal, params.wavelet_type, params.wavelet_level);

    %% 5. 统计域特征
    features.statistical = extract_statistical_features(signal);
end
