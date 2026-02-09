function [jam_signal, bbox_info] = generate_7sj_jamming_with_bbox(tx, params, flag)
% generate_7sj_jamming_with_bbox - 生成扫频干扰并计算bounding box
%
% 输入：
%   tx: 基础LFM信号
%   params: 参数结构体
%   flag: 标志位（未使用）
%
% 输出：
%   jam_signal: 干扰信号
%   bbox_info: bounding box信息 [N_bbox, 4]
%               格式: [x_min, y_min, x_max, y_max]
%               x: 时域坐标（采样点）
%               y: 频域坐标（Hz）

% 参数
fs = params.fs;
fc = params.fc;
N_total = params.N_total;
JNR = params.JNR;
BJ = params.BJ;  % 干扰带宽

% 生成白噪声
white_noise = randn([1, N_total]) + 1j * randn([1, N_total]);
white_noise = white_noise / std(white_noise);

% 扫频干扰参数
T_sweep = (20 + round(rand() * 20)) * 1e-6;  % 扫频周期 20~40us
B1 = 8 * BJ;  % 扫频带宽
f0 = -B1 / 2;  % 起始频率
K = B1 / T_sweep;  % 调频斜率

% 时间轴
t = (0:N_total-1) / fs;

% 扫频载波（周期性）
t_mod = mod(t, T_sweep);
sweep_carrier = exp(1j * 2 * pi * (f0 * t_mod + 0.5 * K * t_mod.^2));

% 设计低通滤波器（用于噪声包络）
filter_order = 34;
normalized_cutoff = BJ / fs;
lpFilt = fir1(filter_order, normalized_cutoff, chebwin(filter_order + 1, 30));

% 滤波得到噪声包络
sp_env = filter(lpFilt, 1, white_noise);

% 生成干扰信号
jam_signal = sweep_carrier .* sp_env;

% 添加幅度
Aj = 10^(JNR / 20);
jam_signal = Aj * jam_signal;

% 计算bounding box
% 扫频干扰覆盖整个时域
x_min = 1;
x_max = N_total;

% 频域范围（扫频带宽）
y_min = fc - B1 / 2;
y_max = fc + B1 / 2;

% 存储bounding box信息
bbox_info = [x_min, y_min, x_max, y_max];
end
