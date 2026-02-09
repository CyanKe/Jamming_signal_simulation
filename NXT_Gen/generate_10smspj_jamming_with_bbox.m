function [jam_signal, bbox_info] = generate_10smspj_jamming_with_bbox(tx, params, flag)
% generate_10smspj_jamming_with_bbox - 生成弥散谱干扰并计算bounding box
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

% 弥散谱干扰参数
M = randi([4 8]);  % 扫频分段数 4~8
mu_prime = M * mu;  % 压缩后斜率（M倍）

% 子波形长度
Tj_samples = floor(Ntau / M);
t_sub = (0:Tj_samples-1) / fs;

% 生成子波形
sub_wave = exp(1j * pi * mu_prime * t_sub.^2) .* exp(-1j * pi * B * t_sub);

% 拼接子波形
smsp_pulse = repmat(sub_wave, 1, M);

% 确保长度匹配
if length(smsp_pulse) > Ntau
    smsp_pulse = smsp_pulse(1:Ntau);
elseif length(smsp_pulse) < Ntau
    smsp_pulse = [smsp_pulse, zeros(1, Ntau - length(smsp_pulse))];
end

% 初始化干扰信号
jam_signal = zeros(1, N_total);

% 计算位置
delay_samp = round(5e-6 * fs);  % 延迟5us
start_pos = pos + delay_samp;
end_pos = start_pos + Ntau - 1;

% 确保在有效范围内
if end_pos <= N_total
    jam_signal(start_pos:end_pos) = smsp_pulse;
end

% 添加幅度
Aj = 10^(JNR / 20);
jam_signal = Aj * jam_signal;

% 计算bounding box
% 时域范围
x_min = start_pos;
x_max = end_pos;

% 频域范围（弥散谱带宽）
% 带宽扩展: B × M
bandwidth_extended = B * M;
y_min = fc - bandwidth_extended / 2;
y_max = fc + bandwidth_extended / 2;

% 存储bounding box信息
bbox_info = [x_min, y_min, x_max, y_max];
end
