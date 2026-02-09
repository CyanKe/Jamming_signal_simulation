function [jam_signal, bbox_info] = generate_5ab_jamming_with_bbox(tx, params, flag)
% generate_5ab_jamming_with_bbox - 生成瞄准/阻塞干扰并计算bounding box
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

% 设计低通滤波器
% FIR滤波器长度
filter_order = 34;
% 归一化截止频率
normalized_cutoff = BJ / fs;
% 使用chebwin窗设计滤波器
lpFilt = fir1(filter_order, normalized_cutoff, chebwin(filter_order + 1, 30));

% 滤波
sp_j = filter(lpFilt, 1, white_noise);

% 添加幅度
Aj = 10^(JNR / 20);
jam_signal = Aj * sp_j;

% 计算bounding box
% 瞄准/阻塞干扰覆盖整个时域
x_min = 1;
x_max = N_total;

% 频域范围
y_min = fc - BJ / 2;
y_max = fc + BJ / 2;

% 存储bounding box信息
bbox_info = [x_min, y_min, x_max, y_max];
end
