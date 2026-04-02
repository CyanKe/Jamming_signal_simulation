% ==========================================================
% generate_rgpo_jamming.m - 生成距离拖引(RGPO)假目标干扰样本
% ==========================================================
function [pure_jam, jam_info] = generate_3rgpo_jamming(tx, params, data_num)
% generate_3rgpo_jamming - 生成距离拖引干扰
% 输出:
%   pure_jam - 干扰信号
%   jam_info - 干扰参数信息 (用于metadata记录)

% 解包参数
fs = params.fs;             % 采样率
N_total = params.N_total;   % 总采样点数
As = 10^(params.SNR/20);    % 真实目标信号幅度
Aj = 10^(params.JNR/20);    % 干扰信号幅度
PRI_samp = params.PRI_samp; % 每个脉冲重复周期(PRI)的采样点数
Ntau = params.Ntau;         % 脉冲宽度对应的采样点数
Np = params.Np;             % 脉冲个数
lambda = 3e8/10e9;          % 雷达波长，假设载频为10G
real_pos_in_pri = params.pos; % 真实目标在第一个PRI内的起始位置
% --- 新增：距离拖引(RGPO)参数 ---
% 初始延迟时间(秒)，0表示一开始与真实目标重合
initial_delay_s = 0;
% 拖引速率(秒/秒)，表示延迟时间每秒增加多少。可以设为正值。
% 例如：2000 m/s 的拖引速度 -> 时间变化率 = 2*2000/c ≈ 1.33e-5 s/s
v = params.v;
pull_off_rate_sps = v*2/3e8;% 1.5e-5;
% 起始时间 (秒)，与 Np 解耦，直接指定干扰信号的起始时间点
if isfield(params, 'start_time')
    start_time = params.start_time;
else
    start_time = 0;  % 默认从 0 开始
end
% 初始化输出
% samples = zeros(data_num, N_total);
% labels = ones(data_num, 1) * label;
pure_jam = zeros(data_num, N_total);
jam_info = struct('v', {}, 'position_relation', {}, 'final_delay_us', {});

for m = 1:data_num
    % % --- 生成噪声 ---
    % white_noise = randn([1, N_total]) + 1j*randn([1, N_total]);
    % white_noise = white_noise / std(white_noise); % 标准化
    % --- 生成干扰信号 (RGPO) ---
    % 初始化整个干扰信号为空
    jam_signal = zeros(1, N_total);

    % 获取单个真实目标的LFM脉冲波形，作为干扰模板
    lfm_template = tx(1, real_pos_in_pri : real_pos_in_pri + Ntau - 1);
    % 循环处理每一个脉冲 (PRI)，因为每个PRI中的假目标位置都不同
    for p = 0:(Np-1)
        % --- 1. 计算当前PRI的起始和结束位置 ---
        pri_start_idx = p * PRI_samp + 1;
        pri_end_idx = (p + 1) * PRI_samp;

        % --- 2. 计算当前时刻的总延迟 ---
        % 当前时间 = start_time + p * (PRI 时长)，与 PRI_samp 解耦
        current_time_s = start_time + p * (PRI_samp / fs);
        % 当前总延迟 = 初始延迟 + 拖引速率 * 当前时间
        current_delay_s = initial_delay_s + pull_off_rate_sps * current_time_s;
        % 将延迟时间转换为采样点数
        delay_samp = round(current_delay_s * fs);

        % --- 3. 计算假目标在当前PRI内的位置 ---
        % 假目标位置 = 真实目标位置 + 延迟
        jam_start_in_pri = real_pos_in_pri + delay_samp;
        jam_end_in_pri = jam_start_in_pri + Ntau - 1;

        % --- 4. 将假目标放入整个信号的对应位置 ---
        % 检查假目标是否超出了当前PRI的范围
        % if jam_end_in_pri <= PRI_samp
        %     % 计算假目标在整个jam_signal向量中的绝对位置
        %     abs_start_idx = pri_start_idx + jam_start_in_pri - 1;
        %     abs_end_idx = pri_start_idx + jam_end_in_pri - 1;
        %
        %     % 在 p 循环内部
        %     jam_signal(abs_start_idx:abs_end_idx) = Aj * lfm_template(1:valid_len);
        % end

        % 替换 if jam_end_in_pri <= PRI_samp
        if jam_start_in_pri <= PRI_samp
            % 计算实际能放入当前PRI的脉冲长度
            valid_len = min(Ntau, PRI_samp - jam_start_in_pri + 1);

            % 计算绝对位置
            abs_start_idx = pri_start_idx + jam_start_in_pri - 1;
            abs_end_idx = abs_start_idx + valid_len - 1;

            % 放置脉冲片段
            jam_signal(abs_start_idx:abs_end_idx) = Aj * lfm_template(1:valid_len);
        end
    end

    % 计算最终延迟和位置关系
    final_delay_s = initial_delay_s + pull_off_rate_sps * (start_time + (Np-1) * PRI_samp / fs);
    final_delay_us = final_delay_s * 1e6;  % 转换为微秒

    % 判断假目标相对于真实目标的位置关系
    if final_delay_s > 0
        position_relation = 'after';  % 假目标在真实目标之后（右侧/后向）
    elseif final_delay_s < 0
        position_relation = 'before'; % 假目标在真实目标之前（左侧/前向）
    else
        position_relation = 'overlap'; % 重合
    end

    % 记录当前样本的参数信息
    jam_info(m).v = v;                    % 拖引速率 m/s
    jam_info(m).position_relation = position_relation;  % 位置关系
    jam_info(m).final_delay_us = final_delay_us;        % 最终延迟时间(微秒)
    jam_info(m).start_time = start_time;                % 起始时间 (s)

    pure_jam(m,:) = jam_signal;
    % % --- 混合信号 ---
    % pure_echo = As * tx;
    % rx = pure_echo + jam_signal + white_noise;
    % % --- 归一化 (防止梯度爆炸) ---
    % rx = rx / max(abs(rx));
    % samples(m, :) = rx;
end
end