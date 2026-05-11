function features = extract_wavelet_features(signal, wavelet, level)
% extract_wavelet_features - 提取小波域特征
%
% 输入:
%   signal   - 输入信号（时域，可为复数）
%   wavelet  - 小波类型（默认 'db4'）
%   level    - 小波分解层数（默认 5）
%
% 输出:
%   features - 小波域特征结构体
%       .variance           - 小波系数方差
%       .mean               - 小波系数均值
%       .max                - 小波系数最大值
%       .scale_centroid     - 尺度重心
%       .max_singular_value - 最大奇异值
%       .central_moment_2   - 二阶中心矩
%       .central_moment_3   - 三阶中心矩
%       .central_moment_4   - 四阶中心矩

    if nargin < 2 || isempty(wavelet)
        wavelet = 'db4';
    end
    if nargin < 3 || isempty(level)
        level = 5;
    end

    features = struct();

    % 取实部进行处理
    signal = real(signal);

    %% 确保分解层数不超过最大值
    max_level = wmaxlev(length(signal), wavelet);
    level = min(level, max_level);

    if level < 1
        level = 1;
    end

    %% 小波分解
    [c, l] = wavedec(signal, level, wavelet);

    %% 提取各层细节系数
    coefficients = cell(1, level);
    for i = 1:level
        coefficients{i} = detcoef(c, l, i);
    end

    %% 合并所有系数
    all_coeffs = [];
    for i = 1:level
        all_coeffs = [all_coeffs, coefficients{i}];
    end

    %% 1. 方差
    features.variance = var(all_coeffs);

    %% 2. 均值
    features.mean = mean(abs(all_coeffs));

    %% 3. 最大值
    features.max = max(abs(all_coeffs));

    %% 4. 尺度重心 (Scale Centroid)
    energies = zeros(1, level);
    for i = 1:level
        energies(i) = sum(coefficients{i}.^2);
    end
    total_energy = sum(energies);
    if total_energy > eps
        features.scale_centroid = sum((1:level) .* energies) / total_energy;
    else
        features.scale_centroid = 0;
    end

    %% 5. 最大奇异值 (Max Singular Value)
    % 构建小波系数矩阵
    max_len = max(cellfun(@length, coefficients));
    coeff_matrix = zeros(max_len, level);
    for i = 1:level
        coeff_matrix(1:length(coefficients{i}), i) = coefficients{i};
    end
    singular_values = svd(coeff_matrix);
    features.max_singular_value = singular_values(1);

    %% 6-8. 中心矩特征
    mu = mean(all_coeffs);

    % 二阶中心矩
    features.central_moment_2 = mean((all_coeffs - mu).^2);

    % 三阶中心矩
    features.central_moment_3 = mean((all_coeffs - mu).^3);

    % 四阶中心矩
    features.central_moment_4 = mean((all_coeffs - mu).^4);
end
