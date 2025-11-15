% ==========================================================
% generate_spot_jamming.m - 生成瞄准式干扰样本
% ==========================================================
function [samples, labels] = generate_npj_jamming(tx, params, label, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);
PRI_samp = params.PRI_samp;
taup = params.taup;
ttau = params.ttau;
Ntau = params.Ntau;
Np = params.Np; 

% 初始化输出
samples = zeros(data_num, N_total);
labels = ones(data_num, 1) * label;
for m = 1:data_num
    % --- 生成噪声 ---
    white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    white_noise = white_noise / std(white_noise); % 标准化

    % --- 1. 生成用于乘积的噪声源 ---
    % 这个噪声是干扰机内部产生的，用于调制干扰信号
    product_noise = randn([1, PRI_samp]) + 1j*randn([1, PRI_samp]);
    product_noise = product_noise / std(product_noise);

    % --- 2. 创建门控LFM信号 (与ISRJ/NCJ类似) ---
    % 设置间歇采样的随机参数
    sampling_period = taup / (5 + randi(10)); % 采样周期
    sampling_duty = 20 + randi(30);           % 占空比

    % 生成单极性方波门控信号
    jam_gate = (square((1/sampling_period)*2*pi*ttau, sampling_duty) + 1) / 2;
    % 将LFM信号与门控相乘，得到被切片的LFM
    lfm = tx(1,params.pos:params.pos+params.Ntau-1);
    gated_lfm = lfm .* jam_gate;

    % --- 3. 在一个PRI内生成转发干扰串 ---
    % 我们首先在一个PRI内生成干扰，然后将其复制到所有PRI
    jam_pri = zeros(1, PRI_samp);
    repetition_times = 5 + randi(5); % 转发5-10次

    for i = 1:repetition_times
        % 设置每次转发的随机延迟
        delay_time = (1 + rand() * 4) * 1e-7;
        delay_samp = round(delay_time * fs);

        % 干扰切片的起始位置
        if i == 1
            left_range = params.pos + delay_samp;
        else
            left_range = last_pos + delay_samp;
        end
        right_range = left_range + Ntau - 1;

        last_pos = left_range; % 记录位置供下次使用

        % 检查是否超出当前PRI的范围
        if right_range <= PRI_samp
            % --- NPJ核心操作 ---
            % 从噪声源中取出一个片段
            noise_segment = product_noise(left_range : right_range);
            % 将门控LFM与噪声片段进行逐元素相乘
            npj_segment = gated_lfm .* noise_segment;

            % 为每次转发设置一个随机幅度
            Aj_rand = Aj * (0.5 + rand());
            jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj_rand * npj_segment;
        end
    end

    % --- 4. 将单个PRI的干扰模板复制到整个信号长度 ---
    jam_signal = repmat(jam_pri, 1, Np);
end

% --- 混合信号 ---
pure_echo = As * tx;
rx = pure_echo + jam_signal + white_noise;

% --- 归一化 (防止梯度爆炸) ---
rx = rx / max(abs(rx));

samples(m, :) = rx;
end
