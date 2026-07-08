function [persistence_spectrum, power_edges, power_centers] = compute_duration_spectrum(stft_mat, num_power_bins, power_range)
% COMPUTE_DURATION_SPECTRUM 从STFT复数矩阵计算持续时间谱 (Persistence Spectrum)
%
% 对每个频率点统计其幅度在不同功率分级上的出现频率(概率)，
% 将 (Nfreq × Ntime) 的STFT转换为 (Nfreq × num_power_bins) 的持续时间谱。
%
% 输入:
%   stft_mat        - STFT复数矩阵, 尺寸 [Nfreq, Ntime]
%   num_power_bins  - 功率分级数, 输出列数
%   power_range     - (可选) 功率范围 [min_dB, max_dB], 默认自动从数据获取
%
% 输出:
%   persistence_spectrum - 持续时间谱, 尺寸 [Nfreq, num_power_bins]
%                          (归一化到 [0,1], 每一行和为1)
%   power_edges     - 功率轴边界, 尺寸 [1, num_power_bins+1]
%   power_centers   - 功率轴中心, 尺寸 [1, num_power_bins]

    if nargin < 3 || isempty(power_range)
        power_range = [];
    end

    Nfreq = size(stft_mat, 1);

    % 1. 计算功率谱 (dB)
    mag_dB = 10 * log10(abs(stft_mat).^2 + eps);

    % 2. 确定功率轴范围
    if isempty(power_range)
        min_p = min(mag_dB(:));
        max_p = max(mag_dB(:));
    else
        min_p = power_range(1);
        max_p = power_range(2);
    end

    % 确保 min_p < max_p
    if min_p >= max_p
        max_p = min_p + 1;
    end

    % 3. 生成功率分级边界
    power_edges = linspace(min_p, max_p, num_power_bins + 1);
    power_centers = (power_edges(1:end-1) + power_edges(2:end)) / 2;

    % 4. 向量化统计直方图 (probability归一化)
    % 使用 discretize + accumarray 替代逐行 histcounts 循环
    % 消除 Nfreq 次 histcounts 调用的 MATLAB 解释器开销
    bin_idx = discretize(mag_dB, power_edges);         % [Nfreq, Ntime] -> bin 索引
    valid = ~isnan(bin_idx);                           % 超出 edges 范围的值 -> NaN
    [row_sub, ~] = find(valid);                        % 频率行索引 (列主序展平)
    counts_2d = accumarray([row_sub, bin_idx(valid)], 1, [Nfreq, num_power_bins]);
    row_sums = sum(counts_2d, 2);
    persistence_spectrum = counts_2d ./ row_sums;      % 行归一化 -> 概率
    persistence_spectrum(row_sums == 0, :) = 0;        % 保护全零行
end
