function features = extract_bispectrum_features(signal, fs, nfft)
% extract_bispectrum_features - 提取双谱域特征
%
% 输入:
%   signal - 输入信号（时域，可为复数）
%   fs     - 采样频率
%   nfft   - FFT点数（可选，默认128）
%
% 输出:
%   features - 双谱域特征结构体
%       .bispectrum_variance - 双谱方差
%       .bispectrum_mean     - 双谱均值

    if nargin < 3
        nfft = 128;
    end

    features = struct();

    %% 计算双谱（使用间接法）
    % 1. 计算三阶累积量
    signal = real(signal(:)');  % 取实部
    N = length(signal);

    % 去均值
    signal = signal - mean(signal);

    % 计算三阶累积量矩阵
    lag_max = min(nfft - 1, floor(N/4));
    c3 = zeros(lag_max + 1, lag_max + 1);

    for lag1 = 0:lag_max
        for lag2 = 0:lag_max
            if (lag1 + lag2) < N
                c3(lag1 + 1, lag2 + 1) = mean(signal(1:N-lag1-lag2) .* ...
                                              signal(lag1+1:N-lag2) .* ...
                                              signal(lag1+lag2+1:N));
            end
        end
    end

    % 2. 对称化处理
    c3_full = zeros(nfft, nfft);
    c3_full(1:size(c3,1), 1:size(c3,2)) = c3;

    % 3. 2D FFT得到双谱
    bispectrum = abs(fft2(c3_full));

    %% 4. 双谱方差
    features.bispectrum_variance = var(bispectrum(:));

    %% 5. 双谱均值
    features.bispectrum_mean = mean(bispectrum(:));
end
