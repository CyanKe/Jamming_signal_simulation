function [jam_signal, bbox_info] = generate_15csj_jamming_with_bbox(tx, params, flag)
% generate_15csj_jamming_with_bbox - 生成梳状谱干扰并计算bounding box
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
B = params.B;
taup = params.taup;
pos = params.pos;
N_total = params.N_total;
JNR = params.JNR;

% LFM参数
Ntau = round(taup * fs);  % LFM脉宽对应的采样点数
T = taup;                 % LFM脉宽
mu = B / T;               % 调频斜率

% 生成基础LFM信号
t = (0:Ntau-1) / fs;
lfm_pulse = exp(1j * 2 * pi * (fc * t + 0.5 * mu * t.^2));

% 梳状谱干扰参数
M = randi([3, 10]);  % 梳齿数 3~10
Q = 0.05 + 0.05 * rand();  % 频率间隔系数 0.05~0.10
P = 0.5 + 0.5 * rand();    % 幅度系数 0.5~1.0

% 生成梳状谱
delta_f = Q * B;  % 频率间隔
comb_pulse = zeros(1, Ntau);

for k = 1:M
    fk = (k - (M + 1) / 2) * delta_f;  % 频率 ±k×delta_f
    comb_pulse = comb_pulse + P * exp(1j * 2 * pi * fk * t);
end

% 调制
jammed_lfm = lfm_pulse .* comb_pulse;

% 初始化干扰信号
jam_signal = zeros(1, N_total);

% 计算位置
start_pos = pos;
end_pos = start_pos + Ntau - 1;

% 确保在有效范围内
if end_pos <= N_total
    jam_signal(start_pos:end_pos) = jammed_lfm;
end

% 添加幅度
Aj = 10^(JNR / 20);
jam_signal = Aj * jam_signal;

% 计算bounding box
% 时域范围
x_min = start_pos;
x_max = end_pos;

% 频域范围（梳状谱带宽）
% 总带宽 = (M-1) × delta_f
total_bandwidth = (M - 1) * delta_f;
y_min = fc - total_bandwidth / 2;
y_max = fc + total_bandwidth / 2;

% 存储bounding box信息
bbox_info = [x_min, y_min, x_max, y_max];
end
