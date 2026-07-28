function [pers_out, power_centers, info] = compute_persistence_channels(stft_mat, channel_power_bins, power_range, method, target_size)
% COMPUTE_PERSISTENCE_CHANNELS 多通道持续时间谱 (不同功率分箱 + 可选 resize)
%
% 对同一 STFT 用多个 power_bin 数分别做 persistence, 再统一到 target_size,
% 堆叠为多通道张量, 便于 CNN/ViT 输入 (如 224×224×3)。
%
% 输入:
%   stft_mat            - 复数 STFT [Nfreq, Ntime]
%   channel_power_bins  - 各通道功率分箱数, 标量或向量, 如 [224, 112, 32]
%   power_range         - 功率范围 [lo, hi] dB; 空则按 method 规则 (见 compute_duration_spectrum)
%   method              - 'custom' | 'matlab'
%   target_size         - (可选) 输出 [H, W]=[freq, power]; 默认 [Nfreq, max(bins)]
%
% 输出:
%   pers_out      - 单通道且无需 resize: [Nfreq, bins]
%                   多通道或需 resize: [H, W, C]
%   power_centers - 输出功率轴中心 (dB), 长度 = size(pers_out, 2) (显示用, 对应 target 功率维)
%   info          - 结构体:
%                   .channel_power_bins, .target_size, .num_channels,
%                   .resized (logical), .native_sizes {C×1 [Nf,Nb]}

    if nargin < 3, power_range = []; end
    if nargin < 4 || isempty(method), method = 'custom'; end
    if nargin < 5, target_size = []; end

    bins = double(channel_power_bins(:).');
    if isempty(bins)
        error('compute_persistence_channels: channel_power_bins 不能为空');
    end
    C = numel(bins);
    Nfreq = size(stft_mat, 1);

    if isempty(target_size)
        target_size = [Nfreq, max(bins)];
    else
        target_size = double(target_size(:).');
        if numel(target_size) ~= 2
            error('compute_persistence_channels: target_size 必须是 [H, W]');
        end
    end
    Ht = target_size(1);
    Wt = target_size(2);

    % 单通道且尺寸已匹配 → 保持旧格式 [Nfreq, bins], 无 resize 开销
    single_native = (C == 1 && Nfreq == Ht && bins(1) == Wt);

    native_sizes = cell(C, 1);
    if single_native
        [pers_out, ~, power_centers] = compute_duration_spectrum( ...
            stft_mat, bins(1), power_range, method);
        native_sizes{1} = size(pers_out);
        resized = false;
    else
        pers_out = zeros(Ht, Wt, C);
        pc_ref = [];
        for c = 1:C
            [P, ~, pc] = compute_duration_spectrum( ...
                stft_mat, bins(c), power_range, method);
            native_sizes{c} = size(P);
            if c == 1
                pc_ref = pc;
            end
            pers_out(:, :, c) = resize_persistence_map(P, target_size);
        end
        % 显示用功率轴: 与输出 W 对齐, 跨度取本样本/全局 power_range
        power_centers = build_output_power_centers(pc_ref, power_range, Wt);
        resized = any(cellfun(@(s) ~isequal(s, [Ht, Wt]), native_sizes));
        % double; 调用方再 cast single
    end

    info = struct();
    info.channel_power_bins = bins;
    info.target_size = [Ht, Wt];
    info.num_channels = C;
    info.resized = resized;
    info.native_sizes = native_sizes;
    info.is_multichannel = (C > 1);
end

function power_centers = build_output_power_centers(pc_ref, power_range, Wt)
% 构造长度为 Wt 的功率轴中心 (dB)
    if ~isempty(power_range) && numel(power_range) >= 2
        lo = power_range(1);
        hi = power_range(2);
    elseif ~isempty(pc_ref)
        % 用最细通道中心的端点近似 edges 跨度
        if numel(pc_ref) >= 2
            d = (pc_ref(2) - pc_ref(1)) / 2;
            lo = pc_ref(1) - d;
            hi = pc_ref(end) + d;
        else
            lo = pc_ref(1) - 0.5;
            hi = pc_ref(1) + 0.5;
        end
    else
        lo = 0;
        hi = 1;
    end
    if lo >= hi
        hi = lo + 1;
    end
    edges = linspace(lo, hi, Wt + 1);
    power_centers = (edges(1:end-1) + edges(2:end)) / 2;
end
