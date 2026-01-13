function [samples,labels] = multi_generation(label,params,current_jnr,data_num)
%UNTITLED2 此处显示有关此函数的摘要
%   此处显示详细说明
% 初始化输出
numClasses = params.numClasses;
N_total = params.N_total;
As = 10^(params.SNR/20);
samples = zeros(data_num, N_total);
oneHotEncoded = convertLabelsToOneHot(label, numClasses);
labels = ones(data_num, numClasses) .* oneHotEncoded;

for m = 1:data_num
    % 生成基础目标信号 (所有干扰类型共用)
    params.pos = 5000+randi([-2000 2000]);
    [tx, params] = generate_0base_signal(params);
    % --- 生成噪声 ---
    white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    white_noise = white_noise / std(white_noise); % 标准化
    sum_jam = zeros(1, N_total);

    for jam_type = label
        switch jam_type
            case 1
                jam_params = params;
                jam_params.JNR = current_jnr; % 密集假目标干扰
                [pure_jam] = generate_1dftj_jamming(tx, jam_params, 1);

            case 2
                jam_params = params;
                jam_params.JNR = current_jnr; % 间歇采样转发干扰
                [pure_jam] = generate_2isrj_jamming(tx, jam_params, 1);

            case 3
                jam_params = params;
                jam_params.JNR = current_jnr; % 距离假目标干扰
                jam_params.v = 5e5;           % 拖引速率
                [pure_jam] = generate_3rgpo_jamming(tx, jam_params, 1);

            case 4
                jam_params = params;
                jam_params.JNR = current_jnr; % 速度假目标干扰
                jam_params.pull = 5e5;        % 拖引频率 Hz
                [pure_jam] = generate_4vgpo_jamming(tx, jam_params, 1);

            case 5
                jam_params = params;
                jam_params.JNR = current_jnr; % 瞄准干扰通常功率更集中
                jam_params.BJ = 20e6;         % 干扰带宽 20MHz
                [pure_jam] = generate_5ab_jamming(tx, jam_params, 1);

            case 6
                jam_params = params;
                jam_params.JNR = current_jnr; % 阻塞干扰
                jam_params.BJ = 45e6;         % 干扰带宽 45MHz
                [pure_jam] = generate_5ab_jamming(tx, jam_params, 1);

            case 7
                jam_params = params;
                jam_params.JNR = current_jnr;  % 扫频干扰
                jam_params.BJ = 10e6;          % 干扰带宽 5MHz
                [pure_jam] = generate_7sj_jamming(tx, jam_params, 1);

            case 8
                jam_params = params;
                jam_params.JNR = current_jnr; % 噪声卷积干扰
                [pure_jam] = generate_8ncj_jamming(tx, jam_params, 1);

            case 9
                jam_params = params;
                jam_params.JNR = current_jnr; % 噪声乘积干扰
                [pure_jam] = generate_9npj_jamming(tx, jam_params, 1);
            
            case 10
                jam_params = params;
                jam_params.JNR = current_jnr; % 噪声乘积干扰
                [pure_jam] = generate_10smspj_jamming(tx, jam_params, 1);
        end
        sum_jam = sum_jam+pure_jam;
    end
    % --- 混合信号 ---
    pure_echo = As * tx;
    rx = pure_echo + sum_jam + white_noise;

    % --- 归一化 (防止梯度爆炸) ---
    rx = rx / max(abs(rx));
    samples(m, :) = rx;
end
end