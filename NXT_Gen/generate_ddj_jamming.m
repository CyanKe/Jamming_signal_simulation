% ==========================================================
% generate_spot_jamming.m - 生成瞄准式干扰样本
% ==========================================================
function [samples, labels] = generate_ab_jamming(tx, params, label, data_num)
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

        % --- 生成瞄准干扰 ---
        lpFilt = fir1(34, Bj/fs, chebwin(35,30));
        sp_j = filter(lpFilt, 1, white_noise); % 使用同一个噪声源滤波
        tj = (0:N_total-1)/fs;
        jam_signal = Aj * (sp_j .* exp(1j*2*pi*fjc*tj));

        % --- 混合信号 ---
        pure_echo = As * tx;
        rx = pure_echo + jam_signal + white_noise;

        % --- 归一化 (防止梯度爆炸) ---
        rx = rx / max(abs(rx));

        samples(m, :) = rx;
    end
end
