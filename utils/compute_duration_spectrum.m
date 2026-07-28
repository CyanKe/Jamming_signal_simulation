function [persistence_spectrum, power_edges, power_centers] = compute_duration_spectrum(stft_mat, num_power_bins, power_range, method)
% COMPUTE_DURATION_SPECTRUM 从STFT复数矩阵计算持续时间谱 (Persistence Spectrum)
%
% 对每个频率点统计其幅度在不同功率分级上的出现频率，
% 将 (Nfreq × Ntime) 的STFT转换为 (Nfreq × num_power_bins) 的持续时间谱。
%
% 输入:
%   stft_mat        - STFT复数矩阵, 尺寸 [Nfreq, Ntime]
%   num_power_bins  - 功率分级数, 输出列数
%   power_range     - (可选) 功率范围 [min_dB, max_dB]
%                     custom: 空则用本样本 min/max
%                     matlab: 空则用本样本 min/max + 5% cushion (对齐 pspectrum)
%   method          - (可选) 'custom'(默认) | 'matlab'
%                     'custom': 行概率归一化 (每频率行和为1), power_centers 为 dB
%                     'matlab': 对齐 pspectrum("persistence"):
%                              功率轴 = min/max(dB)+5%跨度边距;
%                              值 = 计数/时间窗数*100 (百分比 0-100);
%                              power_centers 仍返回 dB (便于 imagesc; 官方 pwr 为线性)
%
% 输出:
%   persistence_spectrum - 持续时间谱, 尺寸 [Nfreq, num_power_bins]
%   power_edges          - 功率轴边界 (dB), 尺寸 [1, num_power_bins+1]
%   power_centers        - 功率轴中心 (dB), 尺寸 [1, num_power_bins]

    if nargin < 3 || isempty(power_range)
        power_range = [];
    end
    if nargin < 4 || isempty(method)
        method = 'custom';
    end
    method = lower(char(method));
    if ~ismember(method, {'custom', 'matlab'})
        error('compute_duration_spectrum: method 必须是 ''custom'' 或 ''matlab'', 收到: %s', method);
    end

    Nfreq = size(stft_mat, 1);
    Ntime = size(stft_mat, 2);

    % 1. 功率谱 (dB) — 与 pspectrum persistence 内部一致用 10*log10(power)
    mag_dB = 10 * log10(abs(stft_mat).^2 + eps);

    % 2. 功率轴范围
    if isempty(power_range)
        min_p = min(mag_dB(:));
        max_p = max(mag_dB(:));
        if strcmp(method, 'matlab')
            % 官方: 上下各扩 5% 跨度, 使图像上下留白
            cushion = 0.05 * abs(max_p - min_p);
            if cushion == 0
                cushion = 0.01 * max(abs(min_p), 1);  % 退化保护 (类似官方 ±1%)
            end
            min_p = min_p - cushion;
            max_p = max_p + cushion;
        end
    else
        min_p = power_range(1);
        max_p = power_range(2);
    end

    if min_p >= max_p
        max_p = min_p + 1;
    end

    % 3. 均匀分箱 (dB)
    power_edges = linspace(min_p, max_p, num_power_bins + 1);
    power_centers = (power_edges(1:end-1) + power_edges(2:end)) / 2;

    % 4. 直方图
    bin_idx = discretize(mag_dB, power_edges);         % 超出 edges -> NaN
    valid = ~isnan(bin_idx);
    [row_sub, ~] = find(valid);
    counts_2d = accumarray([row_sub, bin_idx(valid)], 1, [Nfreq, num_power_bins]);

    % 5. 归一化
    if strcmp(method, 'matlab')
        % 官方: 占全部时间窗的百分比 (0-100), 非按频率行归一化
        if Ntime > 0
            persistence_spectrum = 100 * (counts_2d ./ Ntime);
        else
            persistence_spectrum = zeros(Nfreq, num_power_bins);
        end
    else
        % 自定义: 每个频率行归一化为概率 (行和为1)
        row_sums = sum(counts_2d, 2);
        persistence_spectrum = counts_2d ./ row_sums;
        persistence_spectrum(row_sums == 0, :) = 0;
    end
end
