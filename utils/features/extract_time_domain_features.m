function features = extract_time_domain_features(signal, fs)
% extract_time_domain_features - 提取时域特征
%
% 输入:
%   signal - 输入信号（时域，可为复数）
%   fs     - 采样频率
%
% 输出:
%   features - 时域特征结构体
%       .skewness            - 矩偏度
%       .kurtosis            - 矩峰度
%       .envelope_variation  - 包络起伏度
%       .modulation_bandwidth - 调制带宽
%       .modulation_rate     - 调制速率

    features = struct();

    % 取实部进行处理
    signal_real = real(signal);

    %% 1. 矩偏度 (Skewness)
    mu = mean(signal_real);
    sigma = std(signal_real);
    if sigma > eps
        features.skewness = mean((signal_real - mu).^3) / (sigma^3);
    else
        features.skewness = 0;
    end

    %% 2. 矩峰度 (Kurtosis)
    if sigma > eps
        features.kurtosis = mean((signal_real - mu).^4) / (sigma^4) - 3;
    else
        features.kurtosis = 0;
    end

    %% 3. 包络起伏度 (Envelope Variation)
    % 对实信号做Hilbert变换
    envelope = abs(hilbert(signal_real));
    mean_env = mean(envelope);
    if mean_env > eps
        features.envelope_variation = std(envelope) / mean_env;
    else
        features.envelope_variation = 0;
    end

    %% 4. 快速脉内调制识别参数
    % 使用Hilbert变换提取瞬时频率
    analytic_signal = hilbert(signal_real);
    inst_phase = unwrap(angle(analytic_signal));

    % 瞬时频率
    if length(inst_phase) > 1
        inst_freq = diff(inst_phase) * fs / (2*pi);

        % 调制带宽：瞬时频率的变化范围
        features.modulation_bandwidth = max(inst_freq) - min(inst_freq);

        % 调制速率：瞬时频率的标准差与均值之比
        mean_freq = mean(abs(inst_freq));
        if mean_freq > eps
            features.modulation_rate = std(inst_freq) / mean_freq;
        else
            features.modulation_rate = 0;
        end
    else
        features.modulation_bandwidth = 0;
        features.modulation_rate = 0;
    end
end
