% ==========================================================
% DiffSTFT_Advanced.m - 高级可微短时傅里叶变换实现
% ==========================================================
% 完全对应Python实现的可微分STFT
% 支持非整数帧位置、相位校正、可变窗长
%
% 输入:
%   y          - 输入信号 (行向量或列向量)
%   fs         - 采样频率 (Hz)
%   params     - 参数结构体（可选）
%                .win_len     - 基础窗长 (默认 256)
%                .hop_len     - 步长 (默认 64)
%                .win_type    - 窗函数类型 (默认 'hann')
%                .learnable   - 是否启用可学习参数 (默认 false)
%                .frame_pos   - 指定帧位置向量 (可选)
%                .win_lengths - 每帧的窗长向量 (可选，用于自适应)
%
% 输出:
%   S          - 幅度谱矩阵 (频率 x 时间)
%   F          - 频率轴 (Hz)
%   T          - 时间轴 (s)
%   result     - 结果结构体（包含相位等详细信息）

function [S, F, T, result] = DiffSTFT_Advanced(y, fs, params)

    %% 参数初始化
    if nargin < 2
        error('必须提供输入信号和采样频率');
    end
    if nargin < 3
        params = struct();
    end

    % 默认参数
    defaults = struct(...
        'win_len', 256, ...
        'hop_len', 64, ...
        'win_type', 'hann', ...
        'learnable', false, ...
        'frame_pos', [], ...
        'win_lengths', [], ...
        'normalize', true, ...
        'phase_correction', true ...
    );

    % 合并参数
    fields = fieldnames(defaults);
    for i = 1:length(fields)
        if ~isfield(params, fields{i})
            params.(fields{i}) = defaults.(fields{i});
        end
    end

    %% 信号预处理
    y = y(:);  % 确保列向量
    N = length(y);

    %% 计算帧位置（支持非整数索引）
    if isempty(params.frame_pos)
        % 自动计算帧位置
        num_frames = floor((N - params.win_len) / params.hop_len) + 1;
        frames = (0:num_frames-1) * params.hop_len;  % 允许非整数
    else
        frames = params.frame_pos(:)';
        num_frames = length(frames);
    end

    % 整数部分和小数部分（用于相位校正）
    idx_floor = floor(frames);
    idx_frac = frames - idx_floor;

    %% FFT参数
    NFFT = params.win_len;
    num_freq = NFFT/2 + 1;

    %% 频率轴和时间轴
    F = (0:num_freq-1) * fs / NFFT;
    T = frames / fs;

    %% 初始化输出
    S = zeros(num_freq, num_frames);
    P = zeros(num_freq, num_frames);  % 相位

    %% 可学习参数
    if params.learnable
        % 初始化可学习参数（模拟PyTorch的nn.Parameter）
        if isempty(params.win_lengths)
            params.win_lengths = ones(1, num_frames) * params.win_len;
        end
        % 可学习的窗长变化因子
        win_len_factors = ones(1, num_frames);
    else
        win_len_factors = ones(1, num_frames);
    end

    %% 核心STFT计算
    for t = 1:num_frames
        % 1. 获取帧起始位置
        start_idx = idx_floor(t) + 1;  % MATLAB索引从1开始
        frac = idx_frac(t);

        % 2. 提取帧（带零填充边界处理）
        strided_x = extract_frames(y, start_idx, NFFT);

        % 3. 生成时变窗函数
        if params.learnable && ~isempty(params.win_lengths)
            actual_win_len = params.win_lengths(t);
        else
            actual_win_len = params.win_len;
        end

        window = window_function(NFFT, frac, actual_win_len, params.win_type, win_len_factors(t));

        % 4. 加窗
        tapered = strided_x .* window;

        % 5. FFT
        spectrum = fft(tapered, NFFT);

        % 6. 相位校正（补偿非整数移位）
        if params.phase_correction && frac > 0
            k = (0:NFFT-1)';
            shift = exp(2j * pi * frac * k / NFFT);
            spectrum = spectrum .* shift;
        end

        % 7. 提取单边谱
        S(:, t) = abs(spectrum(1:num_freq));
        P(:, t) = angle(spectrum(1:num_freq));
    end

    %% 归一化
    if params.normalize
        S = S ./ (sum(S(:)) + eps);
    end

    %% 输出结果结构体
    result = struct();
    result.phase = P;
    result.complex_spectrum = S .* exp(1j * P);
    result.frames = frames;
    result.idx_frac = idx_frac;
    result.params = params;
    result.win_lengths_used = params.win_lengths;

end

%% ==========================================================
% 辅助函数：从信号中提取帧（带零填充边界）
% ==========================================================
function frame = extract_frames(y, start_idx, win_len)
    N = length(y);
    frame = zeros(win_len, 1);

    for i = 1:win_len
        idx = start_idx + i - 1;
        if idx >= 1 && idx <= N
            frame(i) = y(idx);
        end
        % 超出边界保持为零
    end
end

%% ==========================================================
% 辅助函数：生成时变窗函数
% ==========================================================
function window = window_function(N, idx_frac, actual_win_len, win_type, win_len_factor)
    % 根据窗长参数生成汉宁窗，窗长可变
    % 对应Python代码中的_window_function方法

    % 计算每个采样点相对于窗中心的偏移
    base = (0:N-1)' - idx_frac;  % [N, 1]

    % 约束后的窗长
    win_len = round(actual_win_len * win_len_factor);
    win_len = max(win_len, 16);  % 最小窗长
    win_len = min(win_len, N);   % 最大窗长

    % 根据窗类型生成窗函数
    switch lower(win_type)
        case 'hann'
            % 汉宁窗公式（支持窗长变化）
            window = 0.5 - 0.5 * cos(2 * pi * (base + (win_len - N + 1)/2) / win_len);

        case 'hamming'
            window = 0.54 - 0.46 * cos(2 * pi * base / (win_len - 1));

        case 'gaussian'
            sigma = 0.4;  % 标准差参数
            window = exp(-0.5 * ((base - (N-1)/2) / (sigma * (win_len-1)/2)).^2);

        otherwise
            window = 0.5 - 0.5 * cos(2 * pi * base / win_len);
    end

    % 将超出窗长范围的系数置零
    mask = (base < -(win_len-1)/2) | (base > (win_len-1)/2);
    window(mask) = 0;

    % 归一化保持能量
    window = window / (sum(abs(window)) + eps);
end

%% ==========================================================
% 自适应分解模块：迭代优化
% ==========================================================
function [components, residual, info] = adaptive_decompose(y, fs, max_components, win_len, hop_len)
    % 基于可微STFT的自适应信号分解
    % 将信号分解为多个分量

    if nargin < 4
        win_len = 256;
    end
    if nargin < 5
        hop_len = 64;
    end
    if nargin < 3
        max_components = 5;
    end

    y = y(:);
    residual = y;
    components = [];
    info = struct();

    for comp_idx = 1:max_components
        if norm(residual) / norm(y) < 0.01
            break;  % 残差足够小，停止分解
        end

        % 对残差进行STFT
        params = struct('win_len', win_len, 'hop_len', hop_len, 'learnable', true);
        [S, F, T, result] = DiffSTFT_Advanced(residual, fs, params);

        % 找到能量最大的频率分量
        [max_val, max_freq_idx] = max(sum(S, 2));
        dominant_freq = F(max_freq_idx);

        % 提取该频率分量
        [component, recon_info] = extract_frequency_component(residual, fs, ...
            dominant_freq, win_len, hop_len);

        % 更新残差
        residual = residual - component;
        components = [components, component];

        % 记录信息
        info(comp_idx).dominant_freq = dominant_freq;
        info(comp_idx).energy = max_val;
        info(comp_idx).recon_info = recon_info;
    end

    info.num_components = comp_idx;
end

%% ==========================================================
% 提取特定频率分量
% ==========================================================
function [component, info] = extract_frequency_component(y, fs, freq, win_len, hop_len)
    y = y(:);
    N = length(y);

    % STFT
    params = struct('win_len', win_len, 'hop_len', hop_len, 'phase_correction', true);
    [S, F, T, result] = DiffSTFT_Advanced(y, fs, params);

    num_frames = size(S, 2);
    component = zeros(N, 1);

    % 频率索引
    [~, target_freq_idx] = min(abs(F - freq));

    % 创建频率掩码（窄带）
    bandwidth = 2;  % Hz
    freq_mask = abs(F - freq) <= bandwidth;

    % 对每一帧进行逆变换
    frame_pos = round(T * fs);
    window = hann(win_len);

    for t = 1:num_frames
        % 创建滤波后的频谱
        filtered_spectrum = zeros(size(S, 1), 1);
        filtered_spectrum(freq_mask) = result.complex_spectrum(freq_mask, t);

        % 逆FFT
        time_frame = ifft(filtered_spectrum, win_len);

        % 重叠相加
        start_idx = max(1, frame_pos(t) + 1);
        end_idx = min(N, start_idx + win_len - 1);
        actual_len = end_idx - start_idx + 1;

        component(start_idx:end_idx) = component(start_idx:end_idx) + ...
            real(time_frame(1:actual_len)) .* window(1:actual_len);
    end

    info.freq = freq;
    info.freq_mask = freq_mask;
    info.S_filtered = S(freq_mask, :);
end

%% ==========================================================
% 特征学习模块：自动特征提取
% ==========================================================
function features = learn_features(S, F, T, fs)
    % 从时频谱中学习特征
    %
    % 输入:
    %   S  - 幅度谱矩阵 (频率 x 时间)
    %   F  - 频率轴 (Hz)
    %   T  - 时间轴 (s)
    %   fs - 采样频率
    %
    % 输出:
    %   features - 特征结构体

    features = struct();

    %% 1. 时域特征
    % 能量包络
    energy_envelope = sum(S.^2, 1);
    features.energy_envelope = energy_envelope;

    % 能量统计量
    features.energy_mean = mean(energy_envelope);
    features.energy_std = std(energy_envelope);
    features.energy_max = max(energy_envelope);

    %% 2. 频域特征
    % 平均频谱
    mean_spectrum = mean(S, 2);
    features.mean_spectrum = mean_spectrum;

    % 频谱质心
    mean_spectrum_norm = mean_spectrum / (sum(mean_spectrum) + eps);
    features.spectral_centroid = sum(F .* mean_spectrum_norm);

    % 频谱带宽
    features.spectral_bandwidth = sqrt(sum(((F - features.spectral_centroid).^2) .* mean_spectrum_norm));

    % 频谱平坦度
    geo_mean = exp(mean(log(mean_spectrum + eps)));
    features.spectral_flatness = geo_mean / (mean(mean_spectrum) + eps);

    % 频谱滚降点
    cumsum_spectrum = cumsum(mean_spectrum);
    features.spectral_rolloff_85 = F(find(cumsum_spectrum >= 0.85 * sum(mean_spectrum), 1, 'first'));
    features.spectral_rolloff_95 = F(find(cumsum_spectrum >= 0.95 * sum(mean_spectrum), 1, 'first'));

    %% 3. 时频域特征
    % 时频熵
    P = S ./ (sum(S(:)) + eps);
    P(P > 0) = P(P > 0) .* log2(P(P > 0));
    features.tf_entropy = -sum(P(:));

    % 时频稀疏度
    features.sparsity = sum(S(:).^2) / (sum(S(:))^2 + eps);

    % 时频能量集中度
    [max_energy, max_idx] = max(S(:));
    [freq_idx, time_idx] = ind2sub(size(S), max_idx);
    features.peak_freq = F(freq_idx);
    features.peak_time = T(time_idx);

    %% 4. 瞬时特征
    % 瞬时频率
    S_normalized = S ./ (sum(S, 1) + eps);
    features.instantaneous_freq = F' * S_normalized;

    % 瞬时带宽
    for t = 1:length(T)
        spectrum_t = S(:, t) / (sum(S(:, t)) + eps);
        features.instantaneous_bandwidth(t) = sqrt(sum(((F - features.instantaneous_freq(t)).^2) .* spectrum_t));
    end

    %% 5. 调制特征
    % 计算调制谱（频谱的频谱）
    if size(S, 2) > 1
        modulation_spectrum = abs(fft(S, [], 2));
        dt = mean(diff(T));
        mod_freq = (0:size(S,2)-1) / (size(S,2) * dt);

        % 低频调制能量
        low_mod_mask = mod_freq < 50;
        features.modulation_energy_low = sum(modulation_spectrum(:, low_mod_mask), 'all');

        % 高频调制能量
        high_mod_mask = mod_freq >= 50 & mod_freq < 200;
        features.modulation_energy_high = sum(modulation_spectrum(:, high_mod_mask), 'all');
    end

    %% 6. 分量特征
    % 主要频率分量
    [sorted_energy, sorted_idx] = sort(mean_spectrum, 'descend');
    features.num_significant_components = sum(sorted_energy > 0.01 * max(sorted_energy));
    features.dominant_frequencies = F(sorted_idx(1:min(5, length(sorted_idx))));

    %% 7. 动态特征
    % 频谱通量（相邻帧的变化）
    if size(S, 2) > 1
        spectral_flux = sqrt(sum(diff(S, 1, 2).^2, 1));
        features.spectral_flux_mean = mean(spectral_flux);
        features.spectral_flux_max = max(spectral_flux);
    end

    % 频谱滚降变化率
    if size(S, 2) > 1
        rolloff_t = zeros(1, size(S, 2));
        for t = 1:size(S, 2)
            cum_t = cumsum(S(:, t));
            rolloff_t(t) = F(find(cum_t >= 0.85 * sum(S(:, t)), 1, 'first'));
        end
        features.rolloff_rate = mean(abs(diff(rolloff_t))) / mean(diff(T));
    end
end