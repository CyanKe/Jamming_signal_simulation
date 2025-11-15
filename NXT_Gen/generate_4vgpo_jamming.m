% ==========================================================
% generate_vgpo_jamming.m - 生成速度门拖引(VGPO)假目标干扰样本
% ==========================================================
function [samples, labels] = generate_4vgpo_jamming(tx, params, label, data_num)
% 解包参数
fs = params.fs;             % 采样率
N_total = params.N_total;   % 总采样点数
As = 10^(params.SNR/20);    % 真实目标信号幅度
Aj = 10^(params.JNR/20);    % 干扰信号幅度
PRI_samp = params.PRI_samp; % 每个PRI的采样点数
PRI_s = PRI_samp / fs;      % PRI的持续时间（秒）
Ntau = params.Ntau;         % 脉冲宽度对应的采样点数
Np = params.Np;             % 脉冲个数
real_pos_in_pri = params.pos; % 真实目标在PRI内的起始位置

% --- 新增：速度拖引(VGPO)参数 ---
% 初始多普勒频移(Hz)，0表示开始时与真实目标速度相同
initial_fd_hz = 0;
% 拖引率 (Hz/s)，表示假目标的多普勒频率每秒变化多少Hz
% 这对应于假目标的"加速度"
pull_off_rate_hz_per_s = params.pull; % 例如，每秒增加5kHz的多普勒频移

% 初始化输出
samples = zeros(data_num, N_total);
labels = ones(data_num, 1) * label;

for m = 1:data_num
    % --- 生成噪声 ---
    white_noise = randn([1, N_total]) + 1j*randn([1, N_total]);
    white_noise = white_noise / std(white_noise); % 标准化

    % --- 生成干扰信号 (VGPO) ---
    jam_signal = zeros(1, N_total);
    
    % 获取单个真实目标的LFM脉冲波形，作为干扰模板
    lfm_template = tx(1, real_pos_in_pri : real_pos_in_pri + Ntau - 1);

    % 循环处理每一个脉冲 (PRI)，因为每个PRI的附加相位都不同
    for p = 0:(Np-1)
        % --- 1. 计算当前时刻和瞬时多普勒频率 ---
        current_time_s = p * PRI_s;
        % 瞬时多普勒 = 初始多普勒 + 拖引率 * 时间
        current_fd_hz = initial_fd_hz + pull_off_rate_hz_per_s * current_time_s;
        
        % --- 2. 计算当前脉冲需要施加的总附加相位 ---
        % 相位是频率对时间的积分。
        % phi(t) = 2*pi * integral(f(t) dt)
        % f(t) = f_initial + rate * t
        % integral(f(t) dt) = f_initial*t + 0.5*rate*t^2
        total_phase_shift = 2 * pi * (initial_fd_hz * current_time_s + 0.5 * pull_off_rate_hz_per_s * current_time_s^2);
        
        % 创建相位调制项
        phase_mod = exp(1j * total_phase_shift);
        
        % --- 3. 生成当前脉冲的干扰信号 ---
        % 幅度 * 模板 * 相位调制
        jam_pulse = Aj * lfm_template * phase_mod;
        
        % --- 4. 将带相位的干扰脉冲放入整个信号的对应位置 ---
        % 注意：干扰的位置与真实目标在PRI内的位置完全相同！
        pri_start_idx = p * PRI_samp + 1;
        abs_start_idx = pri_start_idx + real_pos_in_pri - 1;
        abs_end_idx = abs_start_idx + Ntau - 1;
        
        jam_signal(abs_start_idx:abs_end_idx) = jam_pulse;
    end

    % --- 混合信号 ---
    pure_echo = As * tx;
    rx = pure_echo + jam_signal + white_noise;

    % --- 归一化 ---
    rx = rx / max(abs(rx));

    samples(m, :) = rx;
end
end
