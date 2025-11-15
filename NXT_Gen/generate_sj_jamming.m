% ==========================================================
% generate_spot_jamming.m - 生成瞄准式干扰样本
% ==========================================================
function [samples, labels] = generate_sj_jamming(tx, params, label, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);
Bj = params.BJ; % 瞄准带宽
fjc = 0;   % 干扰中心频率

% 初始化输出
samples = zeros(data_num, N_total);
labels = ones(data_num, 1) * label;
for m = 1:data_num
    % --- 生成噪声 ---
    white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    white_noise = white_noise / std(white_noise); % 标准化

    % --- 生成扫频干扰 ---
    T_sweep=20*1e-6+round((rand(1,1)*20))*1e-6;%扫频周期20-40us
    B1 = 8*Bj;
    f0 = -B1/2;                % 起始频率（相对基带）
    K = B1 / T_sweep;          % 调频斜率
    tj = (0:N_total-1)/fs;     % 时间轴

    % 将时间折返到每个扫频周期内
    t_mod = mod(tj, T_sweep);

    % 生成扫频载波（周期性线性调频）
    sweep_carrier = exp(1j*2*pi*(f0*t_mod + 0.5*K*t_mod.^2));

    % 叠加宽带噪声包络（可选）
    sp = randn([1,N_total]) + 1j*randn([1,N_total]);
    sp = sp / std(sp);
    lpFilt = fir1(34, Bj/fs, chebwin(35,30));
    sp_env = filter(lpFilt, 1, sp);

    % 扫频干扰信号
    sp_j = sweep_carrier .* sp_env;
    jam_signal = Aj * (sp_j .* exp(1j*2*pi*fjc*tj));

    % --- 混合信号 ---
    pure_echo = As * tx;
    rx = pure_echo + jam_signal + white_noise;

    % --- 归一化 (防止梯度爆炸) ---
    rx = rx / max(abs(rx));

    samples(m, :) = rx;
end
end
