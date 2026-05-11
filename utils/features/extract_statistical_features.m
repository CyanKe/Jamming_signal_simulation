function features = extract_statistical_features(signal)
% extract_statistical_features - 提取统计域特征
%
% 输入:
%   signal - 输入信号（时域，可为复数）
%
% 输出:
%   features - 统计域特征结构体
%       .shannon_entropy    - 信息熵
%       .exponential_entropy - 指数熵
%       .norm_entropy       - 范数熵

    features = struct();

    % 取实部进行处理
    signal_real = real(signal(:)');

    %% 1. 信息熵 (Shannon Entropy)
    % 使用直方图估计概率分布
    num_bins = min(100, length(signal_real)/10);
    if num_bins < 2
        num_bins = 2;
    end

    p = histcounts(signal_real, num_bins, 'Normalization', 'probability');
    p = p(p > 0);  % 去除零概率

    if ~isempty(p)
        features.shannon_entropy = -sum(p .* log2(p));
    else
        features.shannon_entropy = 0;
    end

    %% 2. 指数熵 (Exponential Entropy)
    if ~isempty(p)
        features.exponential_entropy = -sum(p .* exp(p - 1));
    else
        features.exponential_entropy = 0;
    end

    %% 3. 范数熵 (Norm Entropy)
    % 使用L2范数
    features.norm_entropy = norm(signal_real, 2) / sqrt(length(signal_real));
end
