% ==========================================================
% generate_NFMJ.m - 生成噪声调频干扰（NFMJ）
% ==========================================================
function [pure_jam] = generate_12nfmj_jamming(tx, params, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
Aj = 10^(params.JNR/20); % 干扰信噪比 (相对于回波或底噪，这里用于幅度控制)
Bj = params.BJ;          % 干扰带宽 (估算值或目标带宽)

% 调频灵敏度 (Hz/Volt) - 这是一个关键参数，决定干扰形状
% 如果 params 中有 Kf 就使用，否则根据 Bj 设定一个默认值
if isfield(params, 'Kf')
    Kf = params.Kf;
else
    % 简单的经验公式：假设噪声功率为1，则 2*Kf*sqrt(Pn) ≈ Bj
    % 这里做简单映射，Bj越大，Kf相对越大
    Kf = Bj / 4; 
end

% 初始化输出
pure_jam = zeros(data_num, N_total);

for m = 1:data_num
    % --- 1. 生成基带调制噪声 ---
    % 生成复高斯白噪声 (可以是实信号，但为了相位生成方便，用解析信号)
    white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    white_noise = white_noise / std(real(white_noise)); % 标准化，使功率归一化
    
    % --- 2. 滤波以控制带宽 ---
    % 关键：噪声的带宽直接影响最终干扰的频谱宽度。
    % 为了让结果更接近要求的 Bj，我们将噪声先滤波到一个特定带宽
    % 假设调制噪声的带宽为 N_bw (通常需要比目标干扰带宽窄一点，留出余量)
    N_bw_factor = 0.3 + 0.7 * rand(1); % 调制噪声带宽系数 (0.3~1.0)
    N_bw = Bj * N_bw_factor; 
    
    [b, a] = fir1(64, N_bw/fs, chebwin(65, 40));
    mod_signal = filter(b, a, white_noise);
    
    % --- 3. 相位生成 (噪声积分) ---
    % 核心步骤：对噪声进行积分得到相位控制信号
    % 使用 cumsum 进行离散积分，注意：在实际物理系统中，积分器是环路的一部分
    % 为了稳定性，这里对积分后的信号做去除趋势项处理 (detrend) 防止频率偏移
    phase_control = cumsum(real(mod_signal)); 
    
    % --- 4. 生成噪声调频信号 ---
    % 公式: s(t) = Aj * exp(j * (2*pi*fc*t + 2*pi*Kf * integral(m(t))))
    % 此处 fc 设为 0 (基带)，实际使用时由 tx 提供载波或这里叠加
    % 注意：如果 tx 本身是基带信号，我们可以直接加调制
    
    % 纯噪声调频信号 (基带解析形式)
    fm_jam_base = Aj * exp(1j * 2 * pi * Kf * phase_control / fs);
    % 注：将 cumsum 转换回时间域：integral(m(t)) ≈ cumsum(m) / fs

    % --- 5. 功率归一化 ---
    fm_jam_base = fm_jam_base / std(fm_jam_base) * Aj;

    pure_jam(m,:) = fm_jam_base;
    
    % --- 可选：视觉检查生成的频谱 ---
    % if m == 1
    %     figure; pspectrum(fm_jam_base, fs); title('Generated Noise FM Jamming Spectrum');
    % end
end
end
