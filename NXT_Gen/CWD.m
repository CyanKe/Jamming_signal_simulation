% ==========================================================
% CWD.m - Choi-Williams Distribution 时频分析
% ==========================================================
% 根据论文公式 (13) 实现 CWD
%
% 输入:
%   y       - 输入信号 (行向量)
%   fs      - 采样频率 (Hz)
%   sigma   - 缩放因子，用于交叉项抑制 (默认 1)
%   n_points - 输出时间点数 (可选，默认信号长度)
%   f_points - 输出频率点数 (可选，默认 128)
%
% 输出:
%   C       - CWD 结果 (复数矩阵，size: f_points x n_points)
%   F       - 频率轴 (Hz)
%   T       - 时间轴 (s)

function [C, F, T] = CWD(y, fs, sigma, n_points, f_points)
    % 默认参数
    if nargin < 3 || isempty(sigma)
        sigma = 1;  % 论文推荐值
    end
    if nargin < 4 || isempty(n_points)
        n_points = length(y);
    end
    if nargin < 5 || isempty(f_points)
        f_points = 128;
    end

    N = length(y);

    % 时间轴和频率轴
    T = linspace(0, (N-1)/fs, n_points);
    F = linspace(-fs/2, fs/2, f_points);

    % 初始化输出
    C = zeros(f_points, n_points);

    % 对每个时间点计算
    for ni = 1:n_points
        % 映射到原始信号索引
        n = round((ni - 1) * (N - 1) / (n_points - 1)) + 1;
        if n > N, n = N; end
        if n < 1, n = 1; end

        % 对每个频率点计算
        for fi = 1:f_points
            omega = 2 * pi * F(fi);
            cwd_sum = 0;

            k_max = min([floor(N/4), 30]);
            for k = 1:k_max
                % m 的求和范围
                m_start = max([1, n - 20, k + 1]);
                m_end = min([N, n + 20, N - k]);

                if m_start >= m_end
                    continue;
                end

                m_vals = m_start:m_end;

                % 高斯权重
                m_diff = m_vals - n;
                gauss_weight = exp(-sigma * (m_diff.^2) ./ (4 * k^2));

                % y(m+k) * y*(m-k)
                y_product = y(m_vals + k) .* conj(y(m_vals - k));

                % 累加 (公式 13)
                sum_val = sum(gauss_weight .* y_product .* exp(-1j * omega * k));
                cwd_sum = cwd_sum + (sqrt(sigma) / (2 * pi * k^2)) * real(sum_val);
            end

            C(fi, ni) = cwd_sum;
        end
    end
end
