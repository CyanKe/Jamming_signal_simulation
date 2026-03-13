function [wave,K] = gen_square_wave(M, N, L)
% 生成指定方波
% 输入参数：
%   M: 决定每段1之间有(M-1)段0
%   N: 方波中包含N段1
%   L: 输出方波的长度
% 输出：
%   wave: 长度为L的行向量，值为0或1

% 计算基本模式长度
T = 1 + M * (N - 1);

% 生成基本模式：1的位置为1, 1+M, 1+2M, ...
base = zeros(1, T);
base(1:M:T) = 1;

% 计算基本重复次数和剩余长度
K = floor(L / T);
r = L - K * T;

% 处理L小于T的情况（通常不会发生，因为L较大）
if K == 0
    wave = base(1:L);
    return;
end

% 构造重复次数向量：前r个元素重复K+1次，其余重复K次
rep_counts = K * ones(1, T);
if r > 0
    rep_counts(1:r) = rep_counts(1:r) + 1;
end

% 生成波形
wave = repelem(base, rep_counts);
end
