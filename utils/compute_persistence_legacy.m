function [P, power_centers, info] = compute_persistence_legacy(stfts, num_power_bins)
% compute_persistence_legacy - 旧版单通道持续时间谱（Persistence Spectrum）
%
% 这是 main_generation_v2.m 在合并前的实现，保留为 cfg.persistence.method = 'legacy'：
%   - 单通道，功率维 num_power_bins 级（默认 64）
%   - 全局功率范围取**第一个样本**的 1%..100% 分位，两端各加 3 dB 余量
%   - 逐样本直方图统计，功率轴所有样本共用
%
% 输入:
%   stfts           - [N, Nfft, N_cols] 复数 STFT（spectrogram 的 'centered' 输出）
%   num_power_bins  - 可选，功率分级数，默认 64
%
% 输出:
%   P               - [N, Nfft, num_power_bins] 持续时间谱
%   power_centers   - 功率轴中心（dB），长度 num_power_bins
%   info            - 结构体：num_power_bins / power_range_db / power_range_mode
%
% 说明: 与 'custom'/'matlab' 路径相比，本路径没有多通道、没有 target_size 重采样，
%       也不支持 power_range_mode 的 'auto'。保留它是为了复现已有的 64-bin 数据集。

    if nargin < 2 || isempty(num_power_bins)
        num_power_bins = 64;
    end

    [n_samples, Nfft, ~] = size(stfts);

    pow_db1 = 10 * log10(abs(squeeze(stfts(1, :, :))).^2 + eps);
    pwr_lo  = prctile(pow_db1(:), 1);     % 1% 分位，避开噪声毛刺
    pwr_hi  = prctile(pow_db1(:), 100);   % 上界
    margin  = 3;                          % ±3 dB 余量，覆盖样本间差异

    global_pwr_range = [pwr_lo - margin, pwr_hi + margin];

    P = zeros(n_samples, Nfft, num_power_bins);
    power_centers = [];
    for i = 1:n_samples
        [P(i, :, :), ~, power_centers] = compute_duration_spectrum( ...
            squeeze(stfts(i, :, :)), num_power_bins, global_pwr_range);
    end

    info = struct( ...
        'num_power_bins',    num_power_bins, ...
        'power_range_db',    global_pwr_range, ...
        'power_range_mode',  'legacy_global_from_first_sample');
end
