function features = extract_freq_domain_features(signal, fs)
% extract_freq_domain_features - 提取频域特征
%
% 输入:
%   signal - 输入信号（时域，可为复数）
%   fs     - 采样频率
%
% 输出:
%   features - 频域特征结构体
%       .spectral_skewness - 频谱矩偏度
%       .spectral_kurtosis - 频谱矩峰度
%       .carrier_factor    - 载波因子
%       .awgn_factor       - 加性高斯白噪声因子

    features = struct();

    %% 计算频谱
    N = length(signal);
    spectrum = abs(fft(real(signal)));
    spectrum = spectrum(1:floor(N/2));

    %% 1. 频谱矩偏度 (Spectral Skewness)
    spec_mean = mean(spectrum);
    spec_std = std(spectrum);
    if spec_std > eps
        features.spectral_skewness = mean((spectrum - spec_mean).^3) / (spec_std^3);
    else
        features.spectral_skewness = 0;
    end

    %% 2. 频谱矩峰度 (Spectral Kurtosis)
    if spec_std > eps
        features.spectral_kurtosis = mean((spectrum - spec_mean).^4) / (spec_std^4) - 3;
    else
        features.spectral_kurtosis = 0;
    end

    %% 3. 载波因子 (Carrier Factor)
    [max_val, max_idx] = max(spectrum);
    carrier_band = max(1, max_idx-5) : min(length(spectrum), max_idx+5);
    total_energy = sum(spectrum.^2);
    if total_energy > eps
        features.carrier_factor = sum(spectrum(carrier_band).^2) / total_energy;
    else
        features.carrier_factor = 0;
    end

    %% 4. 加性高斯白噪声因子 (AWGN Factor)
    % 使用频谱平坦度估计噪声含量
    % 平坦度越高，噪声含量越高
    spectrum_pos = spectrum + eps;  % 避免log(0)
    geo_mean = exp(mean(log(spectrum_pos)));
    arith_mean = mean(spectrum);

    if arith_mean > eps
        spectral_flatness = geo_mean / arith_mean;
    else
        spectral_flatness = 0;
    end

    % AWGN因子：平坦度越高，噪声因子越高
    features.awgn_factor = spectral_flatness;
end
