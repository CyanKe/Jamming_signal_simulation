% ==========================================================
% generate_rgpo_jamming.m - 生成距离拖引(RGPO)假目标干扰样本
% ==========================================================
function [samples, labels] = generate_3rgpo_jamming(tx, params, data_num)
% 解包参数
fs = params.fs;             % 采样率
N_total = params.N_total;   % 总采样点数
As = 10^(params.SNR/20);    % 真实目标信号幅度
Aj = 10^(params.JNR/20);    % 干扰信号幅度
PRI_samp = params.PRI_samp; % 每个脉冲重复周期(PRI)的采样点数
Ntau = params.Ntau;         % 脉冲宽度对应的采样点数
Np = params.Np;             % 脉冲个数
real_pos_in_pri = params.pos; % 真实目标在第一个PRI内的起始位置
% --- 新增：距离拖引(RGPO)参数 ---
% 初始延迟时间(秒)，0表示一开始与真实目标重合
initial_delay_s = 0; 
% 拖引速率(秒/秒)，表示延迟时间每秒增加多少。可以设为正值。
% 例如：2000 m/s 的拖引速度 -> 时间变化率 = 2*2000/c ≈ 1.33e-5 s/s
v = params.v;
pull_off_rate_sps = v*2/3e8;% 1.5e-5; 
% 初始化输出
% samples = zeros(data_num, N_total);
% labels = ones(data_num, 1) * label;
pure_jam = zeros(data_num, N_total);
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
        % 当前时间 = p * (PRI时长)
        current_time_s = p * (PRI_samp / fs);
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
        if jam_end_in_pri <= PRI_samp
            % 计算假目标在整个jam_signal向量中的绝对位置
            abs_start_idx = pri_start_idx + jam_start_in_pri - 1;
            abs_end_idx = pri_start_idx + jam_end_in_pri - 1;
            
            % 放置假目标信号
            jam_signal(abs_start_idx:abs_end_idx) = Aj * lfm_template;
        end
    end
    pure_jam(m,:) = jam_signal;
    % % --- 混合信号 ---
    % pure_echo = As * tx;
    % rx = pure_echo + jam_signal + white_noise;
    % % --- 归一化 (防止梯度爆炸) ---
    % rx = rx / max(abs(rx));
    % samples(m, :) = rx;
end
end