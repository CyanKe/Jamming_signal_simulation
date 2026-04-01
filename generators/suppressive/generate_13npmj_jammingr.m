% ==========================================================
% generate_npmj_random.m - 生成噪声调相干扰 (NPMJ)增加随机性版本
% ==========================================================
function [pure_jam] = generate_13npmj_jammingr(tx, params, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;

% 幅度控制
Aj = 10^(params.JNR/20);

% --- 随机中心频率 (Fj) ---
if isfield(params, 'random_Fj') && params.random_Fj
    Fj = (rand - 0.5) * 0.1 * fs;
else
    if isfield(params, 'Fj')
        Fj = params.Fj;
    else
        Fj = 0;
    end
end

% --- 调制指数 ---
if isfield(params, 'Kp')
    Kp_base = params.Kp;
else
    Kp_base = pi/2;
end

% 是否启用随机 Kp (0: 固定, 1: 随机跳变, 2: 连续慢变)
Kp_variation_mode = 1;

% --- 噪声分布选择 ---
% 0: 标准高斯, 1: 重尾分布 (混合高斯模拟脉冲)
noise_distribution_mode = 1;

% 初始化输出
pure_jam = zeros(data_num, N_total);
t = (0:N_total-1) / fs;

for m = 1:data_num
    % --- 频带随机化 (带宽抖动) ---
    if isfield(params, 'BJ')
        % 允许带宽在目标值的 70% ~ 130% 之间随机跳变
        Bj = params.BJ * (0.9 + 0.1 * rand());
        N_bw_factor = 0.5;
        N_bw = Bj * N_bw_factor;
        % 限制带宽不超过奈奎斯特频率的一半
        N_bw = min(N_bw, fs/2 * 0.9);
    else
        N_bw = fs * 0.1;
    end

    % --- 复合噪声生成 ---
    % 基础高斯白噪声
    white_noise = randn([1,N_total]);
    white_noise = white_noise / std(white_noise);

    % 增加丰富度：采用混合噪声模型 (Mixing Gaussian with Impulsive noise)
    if noise_distribution_mode == 1
        % 引入低概率的脉冲噪声 (幅度更大，模拟重尾分布)
        if rand() < 0.5 % 15% 的概率出现脉冲
            impulsive_noise = randn([1,N_total])  * 2; % 幅度放大3倍
            % 定向频域混合，使部分频段更脏
            % 这里简单线性叠加
            idx = randperm(N_total, round(N_total*0.8)); % 随机选取部分点替换
            white_noise(idx) = impulsive_noise(idx);
        end
    end

    % --- 滤波处理 ---
    % 注意：滤波器阶数也可以稍微随机化，改变频率响应形状的陡峭度
    filter_order = 64 + round(rand()*10); % 阶数在64-74间随机
    [b, a] = fir1(filter_order, N_bw/fs, chebwin(filter_order+1, 40));
    mod_signal = filter(b, a, white_noise);

    % 提取实部作为相位调制信号
    mod_signal_real = real(mod_signal);

    % --- 动态调制指数计算 ---
    if Kp_variation_mode == 1
        % 模式1: 随机跳变 (在每个样本块内随机选择一个 Kp)
        Kp = Kp_base * (0.8 + 0.4 * rand());
    elseif Kp_variation_mode == 2
        % 模式2: 正弦慢变 (模拟载波漂移)
        Kp = Kp_base + 0.5 * sin(2*pi * 0.5 * t);
    else
        Kp = Kp_base;
    end

    % --- 相位调制 ---
    phase_arg = Kp * mod_signal_real;

    % 载波
    carrier = exp(1j * 2 * pi * Fj * t);

    % 基带信号生成
    jam_base = Aj * exp(1j * phase_arg) .* carrier;

    % 叠加微小幅度随机化 (打破恒包络特性，增加对抗性)
    amplitude_perturbation = 1 + 0.05 * randn([1, N_total]);
    jam_base = jam_base .* abs(amplitude_perturbation);

    % --- 功率归一化 ---
    jam_base = jam_base / std(jam_base) * Aj;

    pure_jam(m,:) = jam_base;
end
end
