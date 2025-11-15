function [samples, labels] = generate_1dftj_jamming(tx, params, label, data_num)
% 解包参数
fs = params.fs;
N_total = params.N_total;
As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);
PRI_samp = params.PRI_samp;
Ntau = params.Ntau;
Np = params.Np; 


% 初始化输出
samples = zeros(data_num, N_total);
labels = ones(data_num, 1) * label;
for m = 1:data_num
    % --- 生成噪声 ---
    white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    white_noise = white_noise / std(white_noise); % 标准化

    % --- 1. 设置假目标参数 ---
    k = 3;%+randi([3, 6]);  % 随机产生3-6个假目标

    % --- 2. 创建一个PRI长度的干扰信号模板 ---
    % 我们首先在一个PRI内生成假目标，然后将其复制到所有PRI
    jam_pri = zeros(1, PRI_samp);

    % --- 3. 循环生成每个假目标并放入模板 ---
    for i = 1:k
        % 随机延迟时间 (1-10us)，并转换为采样点数
        delay_time = 10e-6;
        delay_samp = round(delay_time * fs);
        if i == 1
            % 第一个假目标相对于真实目标的位置
            left_range = params.pos + delay_samp*m;
        else
            % 后续假目标相对于前一个假目标的位置
            left_range = last_pos + delay_samp;
        end
        right_range = left_range + Ntau - 1;

        % 记录当前假目标的位置，供下一个假目标参考
        last_pos = left_range;

        % 检查假目标是否超出当前PRI的范围，如果超出则不添加
        if right_range <= PRI_samp
            % 为每个假目标设置一个随机幅度 (0.5到1.5倍的Aj)
            % Aj_rand = Aj * (0.5 + rand());
            lfm = tx(1,params.pos:params.pos+params.Ntau-1);
            jam_pri(left_range:right_range) = jam_pri(left_range:right_range) + Aj * lfm;
        end
    end

    % --- 4. 将单个PRI的干扰模板复制到整个信号长度 ---
    jam_signal = repmat(jam_pri, 1, Np);

    % --- 混合信号 ---
    pure_echo = As * tx;
    rx = pure_echo + jam_signal + white_noise;

    % --- 归一化 (防止梯度爆炸) ---
    rx = rx / max(abs(rx));

    samples(m, :) = rx;
end
end
