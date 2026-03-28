% ==========================================================
% generate_vgpo_jamming.m - 生成速度拖引(VGPO)假目标干扰样本
% ==========================================================
% VGPO三阶段：捕获(capture) -> 拖引(pull-off) -> 停止(cessation)
% ==========================================================
function [pure_jam] = generate_4vgpo_jamming(tx, params, data_num)
% 解包参数
fs = params.fs;             % 采样率
N_total = params.N_total;   % 总采样点数
Aj = 10^(params.JNR/20);    % 干扰信号幅度
PRI_samp = params.PRI_samp; % 每个PRI的采样点数
Ntau = params.Ntau;         % 脉冲宽度对应的采样点数
Np = params.Np;             % 脉冲个数
real_pos_in_pri = params.pos; % 真实目标在PRI内的起始位置

% --- VGPO拖引参数 ---
% 多普勒频率拖引率 (Hz/s)，假目标的多普勒频率每秒变化量
if isfield(params, 'fd_rate')
    fd_rate = params.fd_rate;
else
    fd_rate = 10e3;  % 默认 10kHz/s (0.01MHz/s)
end

% 三阶段时长 (秒)
capture_time = 2e-3;   % 捕获阶段 2ms
pull_off_time = 10e-3; % 拖引阶段 10ms
% cessation阶段不发射干扰，总时长 2ms

% 初始化输出
pure_jam = zeros(data_num, N_total);
t_pulse = (0:Ntau-1) / fs;  % 脉冲内时间轴

for m = 1:data_num
    jam_signal = zeros(1, N_total);

    % 获取LFM脉冲模板
    lfm_template = tx(1, real_pos_in_pri : real_pos_in_pri + Ntau - 1);

    % 处理每个脉冲
    for p = 0:(Np-1)
        pri_start_idx = p * PRI_samp + 1;
        current_time_s = p * (PRI_samp / fs);

        % --- 判断当前处于哪个阶段 ---
        if current_time_s < capture_time
            % 捕获阶段：fd=0，与真实目标重合
            fd = 0;
        elseif current_time_s < capture_time + pull_off_time
            % 拖引阶段：多普勒频率逐渐增加
            time_in_pull_off = current_time_s - capture_time;
            fd = fd_rate * time_in_pull_off;
        else
            % 停止阶段：不发射干扰
            continue;
        end

        % 多普勒调制
        doppler_mod = exp(1j * 2 * pi * fd * t_pulse);
        jam_pulse = Aj * lfm_template .* doppler_mod;

        % 放置到对应位置
        abs_start_idx = pri_start_idx + real_pos_in_pri - 1;
        abs_end_idx = abs_start_idx + Ntau - 1;
        jam_signal(abs_start_idx:abs_end_idx) = jam_pulse;
    end
    pure_jam(m,:) = jam_signal;
end
end
