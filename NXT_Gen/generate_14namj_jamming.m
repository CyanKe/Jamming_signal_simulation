% ==========================================================
% generate_namj.m - 生成噪声调幅干扰 (NAMJ)
% ==========================================================
function [pure_jam] = generate_14namj_jamming(tx, params, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
Aj = 10^(params.JNR/20);  % 干扰幅度（载波幅度）
Fj = 0;            % 干扰中心频率 (Hz)，通常为基带0，或特定载波

% 调制深度 (Modulation Index)
% 控制噪声对幅度的调制程度。0 < m_a <= 1 (避免过调导致幅度为负)
% 如果未指定，设置一个默认值，例如 0.8
if isfield(params, 'm_a')
    m_a = params.m_a;
    % 确保调制深度在有效范围内
    m_a = min(max(m_a, 0.01), 1.0);
else
    m_a = 0.8; 
end

% 调制噪声带宽控制
% 主要目的是匹配 params.BJ (干扰带宽)
% 对于调幅，如果载频在 Fj，那么总带宽主要由调制噪声的带宽和调制深度决定。
% 但通常为了形成特定形状的宽带压制干扰，我们让调制噪声的带宽等于或略小于目标干扰带宽。
% 但注意：如果噪声是白噪声（带宽很宽），干扰频谱将在 Fj 附近扩散。
% 这里我们假设 params.BJ 指的是干扰信号的总带宽（3dB带宽或10dB带宽），因此：
if isfield(params, 'BJ')
    Bj = params.BJ;
    % 调制噪声的滤波截止频率设定为 Bj/2 (双边带噪声)
    % 实际中，我们可以按比例设定
    N_bw = Bj;
else
    N_bw = fs * 0.1; % 默认带宽为采样率的10%
end

% 初始化输出
pure_jam = zeros(data_num, N_total);

% 生成时间轴 (用于调制载波，如果 Fj != 0)
t = (0:N_total-1) / fs;

for m = 1:data_num
    % --- 1. 生成基带调制噪声 ---
    % 生成高斯白噪声（实信号即可）
    white_noise_real = randn([1, N_total]);
    white_noise_real = white_noise_real / std(white_noise_real); % 标准化，均值0，方差1
    
    % --- 2. 滤波以控制带宽 ---
    % 这是为了让干扰谱符合特定的带宽要求
    % 使用 chebwin 设计滤波器，在通带外有良好衰减
    % 注：如果噪声是白噪声且不滤波，干扰带宽会非常宽（无限宽，受限于Fs/N）
    if N_bw < fs/2
        [b, a] = fir1(64, N_bw/fs, chebwin(65, 40));
        mod_signal = filter(b, a, white_noise_real);
        % 重新归一化，使其方差为1 (因为滤波可能改变方差)
        mod_signal = mod_signal / std(mod_signal);
    else
        mod_signal = white_noise_real;
    end
    
    % --- 3. 进行幅度调制 ---
    % 标准 AM 调制公式: s(t) = Aj * (1 + m_a * m(t)) * cos(2*pi*Fj*t)
    % 注意：这里我们使用解析信号（复信号）形式，方便后续处理
    % 对于基带复信号，可以直接用：s(t) = Aj * (1 + m_a * m(t)) (实数)
    % 或者生成为带 Fj 载频的复信号：s(t) = Aj * (1 + m_a * m(t)) * exp(j*2*pi*Fj*t)
    
    % 生成带载波的复数形式（更通用，方便叠加到射频信号上）
    % 如果 Fj=0，则 exp(j*0) = 1，变为实数基带信号
    amp_env = 1 + m_a * mod_signal;
    
    % 检查是否过调制（理论上 m_a<=1 保证 |1+m_a*m(t)|>=0，但由于噪声随机性，
    % 极小概率可能为负，建议做裁剪或使用平方律避免负值，这里为了简单做裁剪）
    amp_env(amp_env < 0) = 0;
    
    % 生成载波
    carrier = exp(1j * 2 * pi * Fj * t);
    
    % 合成干扰信号
    % 注意：如果 params.JNR 定义的是总功率，那么这里 Aj 应该是载波幅度，
    % 但调制后总功率会变大。在实际系统中，通常固定 Aj 使得干扰功率可控。
    % 这里简单地将 Aj 作为总幅度的标度因子。
    fm_jam_base = Aj * amp_env .* carrier;
    
    % --- 4. 考虑恒包络（可选） ---
    % 有时为了模拟某些发射机限制，我们希望保持恒包络。
    % 但噪声调幅天然不是恒包络的。这里我们不做归一化，保持真实的调幅波形。
    
    pure_jam(m,:) = fm_jam_base;
    
    % --- 可选：视觉检查生成的频谱 ---
    % if m == 1
    %     figure; pspectrum(fm_jam_base, fs); 
    %     title(['Noise AM Jamming, BW=', num2str(N_bw/1e3), 'kHz']);
    %     xlabel('Frequency (Hz)'); ylabel('Power (dB)');
    %     grid on;
    % end
end
end
