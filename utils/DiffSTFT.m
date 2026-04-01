% ==========================================================
% DiffSTFT.m - 基于可微短时傅里叶变换的非平稳信号自适应分解
% ==========================================================
% 参考Python实现的可微分STFT，支持非整数帧位置和可变窗长
%
% 输入:
%   y          - 输入信号 (行向量或列向量)
%   fs         - 采样频率 (Hz)
%   win_len    - 窗长 (可选，默认 256)
%   hop_len    - 步长 (可选，默认 win_len/4)
%   win_type   - 窗函数类型: 'hann', 'hamming', 'gaussian' (可选，默认 'hann')
%   adaptive   - 是否启用自适应窗长 (可选，默认 false)
%
% 输出:
%   S          - 幅度谱矩阵 (频率 x 时间)
%   F          - 频率轴 (Hz)
%   T          - 时间轴 (s)
%   phase      - 相位谱矩阵 (可选输出)

function [S, F, T, phase] = DiffSTFT(y, fs, win_len, hop_len, win_type, adaptive)
    % 参数校验和默认值
    if nargin < 2
        error('必须提供输入信号和采样频率');
    end
    if nargin < 3 || isempty(win_len)
        win_len = 256;
    end
    if nargin < 4 || isempty(hop_len)
        hop_len = floor(win_len / 4);
    end
    if nargin < 5 || isempty(win_type)
        win_type = 'hann';
    end
    if nargin < 6 || isempty(adaptive)
        adaptive = false;
    end

    % 确保信号为列向量
    y = y(:);
    N = length(y);

    % 计算帧数和帧位置（允许非整数索引）
    num_frames = floor((N - win_len) / hop_len) + 1;
    frame_pos = (0:num_frames-1) * hop_len;  % 帧起始位置

    % 整数部分和小数部分（用于相位校正）
    idx_floor = floor(frame_pos);
    idx_frac = frame_pos - idx_floor;

    % 输出频率点数
    NFFT = win_len;
    num_freq = NFFT/2 + 1;

    % 初始化输出矩阵
    S = zeros(num_freq, num_frames);
    phase = zeros(num_freq, num_frames);

    % 频率轴和时间轴
    F = (0:num_freq-1) * fs / NFFT;
    T = frame_pos / fs;

    % 对每一帧进行处理
    for frame_idx = 1:num_frames
        % 获取帧起始位置
        start_idx = idx_floor(frame_idx) + 1;  % MATLAB索引从1开始
        frac = idx_frac(frame_idx);

        % 提取帧（带零填充边界处理）
        frame = extract_frame(y, start_idx, NFFT);

        % 生成窗函数（支持自适应窗长）
        if adaptive
            window = adaptive_window(NFFT, frac, frame_idx, num_frames);
        else
            window = create_window(NFFT, win_type, frac);
        end

        % 加窗
        windowed_frame = frame .* window;

        % FFT
        spectrum = fft(windowed_frame, NFFT);

        % 相位校正（补偿非整数移位）
        if frac > 0
            % 相位校正因子
            k = (0:NFFT-1)';
            phase_correction = exp(2j * pi * frac * k / NFFT);
            spectrum = spectrum .* phase_correction;
        end

        % 取前一半频率（实信号）
        S(:, frame_idx) = abs(spectrum(1:num_freq));
        phase(:, frame_idx) = angle(spectrum(1:num_freq));
    end
end

% ==========================================================
% 辅助函数：提取帧（带零填充）
% ==========================================================
function frame = extract_frame(y, start_idx, win_len)
    N = length(y);
    frame = zeros(win_len, 1);

    for i = 1:win_len
        idx = start_idx + i - 1;
        if idx >= 1 && idx <= N
            frame(i) = y(idx);
        end
        % 超出边界的部分保持为零
    end
end

% ==========================================================
% 辅助函数：创建窗函数（支持非整数移位的相位校正）
% ==========================================================
function window = create_window(N, win_type, frac)
    % 基础窗函数
    switch lower(win_type)
        case 'hann'
            window = hann(N);
        case 'hamming'
            window = hamming(N);
        case 'gaussian'
            window = gausswin(N, 2.5);
        otherwise
            window = hann(N);
    end

    % 如果有小数偏移，调整窗函数位置
    if frac > 0
        % 通过插值调整窗函数
        window = interp1(linspace(0, 1, N), window, linspace(0, 1, N) + frac/N, 'linear', 'extrap')';
    end

    % 归一化保持能量
    window = window / sqrt(sum(window.^2));
end

% ==========================================================
% 辅助函数：自适应窗函数（窗长可变）
% ==========================================================
function window = adaptive_window(N, frac, frame_idx, num_frames)
    % 根据帧位置动态调整窗长
    % 在信号中心区域使用较长窗，在边缘区域使用较短窗

    % 计算窗长变化因子（0.5到1.0之间）
    center_pos = num_frames / 2;
    distance_from_center = abs(frame_idx - center_pos) / center_pos;
    win_len_factor = 0.5 + 0.5 * (1 - distance_from_center);

    % 计算实际窗长
    actual_win_len = round(N * win_len_factor);
    actual_win_len = max(actual_win_len, 16);  % 最小窗长

    % 创建基础Hanning窗
    base_window = hann(actual_win_len);

    % 居中放置到N长度的窗中
    window = zeros(N, 1);
    start_pos = floor((N - actual_win_len) / 2) + 1;
    end_pos = start_pos + actual_win_len - 1;
    window(start_pos:end_pos) = base_window;

    % 相位校正（小数偏移）
    if frac > 0
        n = (0:N-1)';
        phase_shift = exp(2j * pi * frac * n / N);
        window = abs(window .* phase_shift);
    end

    % 归一化
    window = window / sqrt(sum(window.^2));
end

% ==========================================================
% 特征学习模块：自适应分解与特征提取
% ==========================================================
function [features, S, F, T] = extract_features(y, fs, params)
    % 基于可微STFT的自适应特征提取
    %
    % 输入:
    %   y        - 输入信号
    %   fs       - 采样频率
    %   params   - 参数结构体（可选）
    %              .win_len    - 窗长
    %              .hop_len    - 步长
    %              .adaptive   - 是否自适应
    %              .n_components - 特征分量数
    %
    % 输出:
    %   features - 提取的特征矩阵
    %   S, F, T  - 时频谱及轴

    % 默认参数
    if nargin < 3
        params = struct();
    end
    if ~isfield(params, 'win_len')
        params.win_len = 256;
    end
    if ~isfield(params, 'hop_len')
        params.hop_len = floor(params.win_len / 4);
    end
    if ~isfield(params, 'adaptive')
        params.adaptive = true;
    end
    if ~isfield(params, 'n_components')
        params.n_components = 10;
    end

    % 计算可微STFT
    [S, F, T] = DiffSTFT(y, fs, params.win_len, params.hop_len, 'hann', params.adaptive);

    % 特征提取
    features = struct();

    % 1. 时频能量分布
    features.energy_distribution = S.^2;

    % 2. 瞬时频率（通过相位导数估计）
    features.instantaneous_freq = estimate_instantaneous_freq(S, F);

    % 3. 频谱质心
    features.spectral_centroid = compute_spectral_centroid(S, F);

    % 4. 频谱带宽
    features.spectral_bandwidth = compute_spectral_bandwidth(S, F, features.spectral_centroid);

    % 5. 频谱平坦度
    features.spectral_flatness = compute_spectral_flatness(S);

    % 6. 频谱滚降点
    features.spectral_rolloff = compute_spectral_rolloff(S, F, 0.85);

    % 7. 主频分量
    [~, max_idx] = max(S, [], 1);
    features.dominant_freq = F(max_idx);

    % 8. 能量集中频带
    features.energy_bands = compute_energy_bands(S, F, fs);

    % 9. 时频熵
    features.tf_entropy = compute_tf_entropy(S);

    % 10. 调制特征
    features.modulation_features = compute_modulation_features(S, F, T);
end

% ==========================================================
% 估计瞬时频率
% ==========================================================
function inst_freq = estimate_instantaneous_freq(S, F)
    [~, num_frames] = size(S);

    inst_freq = zeros(1, num_frames);
    for i = 1:num_frames
        % 加权平均频率
        spectrum = S(:, i);
        spectrum = spectrum / (sum(spectrum) + eps);
        inst_freq(i) = sum(F .* spectrum);
    end
end

% ==========================================================
% 计算频谱质心
% ==========================================================
function centroid = compute_spectral_centroid(S, F)
    spectrum = mean(S, 2);
    spectrum = spectrum / (sum(spectrum) + eps);
    centroid = sum(F .* spectrum);
end

% ==========================================================
% 计算频谱带宽
% ==========================================================
function bandwidth = compute_spectral_bandwidth(S, F, centroid)
    spectrum = mean(S, 2);
    spectrum = spectrum / (sum(spectrum) + eps);
    bandwidth = sqrt(sum(((F - centroid).^2) .* spectrum));
end

% ==========================================================
% 计算频谱平坦度
% ==========================================================
function flatness = compute_spectral_flatness(S)
    spectrum = mean(S, 2);
    spectrum = spectrum + eps;  % 避免log(0)

    % 几何平均 / 算术平均
    geo_mean = exp(mean(log(spectrum)));
    arith_mean = mean(spectrum);

    flatness = geo_mean / (arith_mean + eps);
end

% ==========================================================
% 计算频谱滚降点
% ==========================================================
function rolloff = compute_spectral_rolloff(S, F, threshold)
    spectrum = mean(S, 2);
    total_energy = sum(spectrum);
    cumulative_energy = cumsum(spectrum);

    rolloff_idx = find(cumulative_energy >= threshold * total_energy, 1, 'first');
    if isempty(rolloff_idx)
        rolloff_idx = length(F);
    end

    rolloff = F(rolloff_idx);
end

% ==========================================================
% 计算能量频带分布
% ==========================================================
function bands = compute_energy_bands(S, F, fs)
    % 定义频带边界（Hz）
    band_edges = [0, 100, 200, 500, 1000, 2000, 5000, fs/2];
    num_bands = length(band_edges) - 1;

    bands = zeros(num_bands, 1);
    for i = 1:num_bands
        freq_mask = (F >= band_edges(i)) & (F < band_edges(i+1));
        bands(i) = sum(mean(S(freq_mask, :), 2));
    end

    % 归一化
    bands = bands / (sum(bands) + eps);
end

% ==========================================================
% 计算时频熵
% ==========================================================
function entropy = compute_tf_entropy(S)
    % 归一化为概率分布
    P = S ./ (sum(S(:)) + eps);

    % 计算熵
    P = P(P > 0);  % 去除零值
    entropy = -sum(P .* log2(P));
end

% ==========================================================
% 计算调制特征
% ==========================================================
function mod_features = compute_modulation_features(S, F, T)
    % 计算频谱的频谱（调制谱）
    num_freq = size(S, 1);
    num_frames = size(S, 2);

    % 调制频率分辨率
    if num_frames > 1
        dt = mean(diff(T));
        mod_fs = 1 / dt;
        mod_freq = (0:num_frames-1) * mod_fs / num_frames;

        % 计算调制谱
        mod_spectrum = abs(fft(S, [], 2));

        % 提取低频调制成分（0-50Hz）
        mod_band = mod_freq < 50;
        mod_features = mean(mod_spectrum(:, mod_band), 2);
    else
        mod_features = zeros(num_freq, 1);
    end
end