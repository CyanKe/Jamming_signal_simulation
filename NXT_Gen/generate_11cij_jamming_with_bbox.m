function [jam_signal, bbox_info] = generate_11cij_jamming_with_bbox(tx, params, flag)
% generate_11cij_jamming_with_bbox - 生成切片交织干扰并计算bounding box
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

% 切片交织干扰参数
a = randi([2 4]);  % 每个段的时隙数 2~4
b = randi([2 4]);  % 采样段数 2~4
total_segments = a * b;  % 总分段数 4~16
T_seg_samp = floor(Ntau / total_segments);  % 每段采样点

% 初始化干扰信号
jam_signal = zeros(1, N_total);

% 存储bounding box信息
bbox_info = [];

% 采样循环（外层）
for i = 0:b-1
    % 计算采样段的起始和结束
    sample_start = i * a * T_seg_samp + 1;
    sample_end = sample_start + T_seg_samp - 1;

    % 确保在有效范围内
    if sample_end > Ntau
        break;
    end

    % 获取当前切片
    current_slice = lfm_pulse(sample_start:sample_end);

    % 重复填充（内层）
    for k = 0:a-1
        delay_samp = (i * a + k) * T_seg_samp;
        start_pos = pos + delay_samp;
        end_pos = start_pos + T_seg_samp - 1;

        % 确保在有效范围内
        if end_pos > N_total
            continue;
        end

        % 填充干扰信号
        jam_signal(start_pos:end_pos) = current_slice;

        % 计算bounding box
        % 时域范围
        x_min = start_pos;
        x_max = end_pos;

        % 频域范围（与LFM相同）
        y_min = fc - B / 2;
        y_max = fc + B / 2;

        % 添加到bounding box列表
        bbox_info = [bbox_info; x_min, y_min, x_max, y_max];
    end
end

% 添加幅度
Aj = 10^(JNR / 20);
jam_signal = Aj * jam_signal;

% 如果没有生成任何切片，返回空bounding box
if isempty(bbox_info)
    bbox_info = [];
end
end
