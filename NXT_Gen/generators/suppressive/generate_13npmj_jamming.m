% ==========================================================
% generate_npmj.m - 生成噪声调相干扰 (NPMJ)
% ==========================================================
function [pure_jam] = generate_13npmj_jamming(tx, params, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;

% 幅度控制 (保持原模板逻辑)
Aj = 10^(params.JNR/20); 

% 调相指数 (Phase Index / Modulation Index)
% 关键参数：决定相位抖动的剧烈程度
% 如果 params 中有 Kp 就使用，否则设定一个默认值 (例如 pi/2)
if isfield(params, 'Kp')
    Kp = params.Kp;
else
    Kp = pi/2; % 默认调制指数，约为 1.57 rad
end

% 调制噪声带宽控制 (NPM 的带宽主要由调制噪声带宽和 Kp 决定)
% 为了让结果接近要求的 Bj (假设 params.BJ 代表干扰带宽需求)，
% 我们需要反推或设定调制噪声的带宽。
% 经验公式：对于窄带调相，正弦调制时，带宽 ≈ 2*(Kp+1)*N_bw
% 这里我们设定调制噪声的标准差等于 Kp，以保证相位抖动幅度可控
if isfield(params, 'BJ')
    Bj = params.BJ;
    % 假设噪声带宽是目标干扰带宽的一部分，留出余量
    % 对于调相，Kp 越大，频谱展宽越宽
    N_bw_factor = 0.5; 
    N_bw = Bj * N_bw_factor;
else
    N_bw = fs * 0.1; % 默认带宽
end

% 初始化输出
pure_jam = zeros(data_num, N_total);

for m = 1:data_num
    % --- 1. 生成基带调制噪声 ---
    % 生成复高斯白噪声
    white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    white_noise = white_noise / std(white_noise); % 标准化
    
    % --- 2. 滤波以控制噪声带宽 ---
    % 噪声的带宽直接影响最终调相信号的频谱形状
    [b, a] = fir1(64, N_bw/fs, chebwin(65, 40));
    mod_signal = filter(b, a, white_noise);
    
    % 提取实部作为相位调制信号 (通常调相使用实噪声)
    mod_signal_real = real(mod_signal);
    
    % --- 3. 直接相位调制 (无积分) ---
    % 核心区别：这里不对噪声积分，而是直接作为相位偏移
    % 公式: s(t) = Aj * exp(j * (2*pi*fc*t + Kp * m(t)))
    % 注意：mod_signal_real 的幅度是归一化的(标准差~1)，乘以 Kp 得到相位偏移量
    
    % 生成基带噪声调相信号
    % 注意：如果 Tx 本身是基带信号，可以直接加在 tx(m,:) 上
    phase_jam_base = Aj * exp(1j * Kp * mod_signal_real);
    
    pure_jam(m,:) = phase_jam_base;
    
    % --- 可选：视觉检查 ---
    % if m == 1
    %     figure; pspectrum(phase_jam_base, fs); title('Generated Noise PM Spectrum');
    %     xlabel('Frequency (Hz)'); ylabel('Power (dB)');
    %     grid on;
    % end
end
end
