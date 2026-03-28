% ==========================================================
% generate_5ab_jamming.m - 生成瞄准式/阻塞干扰样本
% ==========================================================
function [pure_jam] = generate_5ab_jamming(tx, params, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);
Bj = params.BJ; % 瞄准/阻塞带宽

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

% 初始化输出
pure_jam = zeros(data_num, N_total);
t = (0:N_total-1) / fs;

for m = 1:data_num
    % --- 生成噪声 ---
    white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    white_noise = white_noise / std(white_noise); % 标准化

    % --- 生成瞄准/阻塞干扰 ---
    lpFilt = fir1(34, Bj/fs, chebwin(35,30));
    sp_j = filter(lpFilt, 1, white_noise); % 使用同一个噪声源滤波

    % 载波
    carrier = exp(1j * 2 * pi * Fj * t);

    jam_signal = Aj * sp_j .* carrier;

    pure_jam(m,:) = jam_signal;
end
end
