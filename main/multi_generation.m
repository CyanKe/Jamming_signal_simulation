function [samples,labels,metadata] = multi_generation(label,params,current_jnr,data_num)
% multi_generation - 生成多干扰类型样本，并记录metadata
% 输入:
%   label - 干扰类型标签数组 (如 [1] 或 [1,5])
%   params - 信号参数结构体
%   current_jnr - 当前干噪比 dB
%   data_num - 生成样本数
% 输出:
%   samples - 生成的信号样本
%   labels - one-hot编码的标签
%   metadata - 每个样本的生成参数信息

% 初始化输出
numClasses = params.numClasses;
N_total = params.N_total;
As = 10^(params.SNR/20);
samples = zeros(data_num, N_total);
oneHotEncoded = convertLabelsToOneHot(label, numClasses);
labels = ones(data_num, numClasses) .* oneHotEncoded;

% 初始化metadata结构数组
metadata = struct('sample_idx', {}, 'jam_types', {}, 'JNR', {}, 'pos', {}, 'jam_params', {});

for m = 1:data_num
    % 初始化当前样本的metadata
    metadata(m).sample_idx = m;
    metadata(m).jam_types = label;
    metadata(m).JNR = current_jnr;
    metadata(m).jam_params = struct();

    % 生成基础目标信号 (所有干扰类型共用)
    current_pos = 500+randi([0 4000]);      % 随机位置
    params.pos = current_pos;
    metadata(m).pos = current_pos;

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
                [pure_jam,~,jam_info] = generate_1dftj_jamming(tx, jam_params, 1);
                % 记录DFTJ参数
                metadata(m).jam_params.dftj_k = jam_info(1).k;

            case 2
                jam_params = params;
                jam_params.JNR = current_jnr; % 间歇采样转发干扰
                [pure_jam,~,jam_info] = generate_2isrj_jamming(tx, jam_params, 1);
                % 记录ISRJ参数
                metadata(m).jam_params.isrj_M = jam_info(1).M;
                metadata(m).jam_params.isrj_N = jam_info(1).N;

            case 3
                jam_params = params;
                jam_params.JNR = current_jnr; % 距离假目标干扰
                jam_params.v = 5e5;           % 拖引速率
                [pure_jam, jam_info] = generate_3rgpo_jamming(tx, jam_params, 1);
                % 记录RGPO参数
                metadata(m).jam_params.rgpo_v = jam_params.v;
                metadata(m).jam_params.rgpo_position_relation = jam_info(1).position_relation;
                metadata(m).jam_params.rgpo_final_delay_us = jam_info(1).final_delay_us;

            case 4
                jam_params = params;
                jam_params.JNR = current_jnr; % 速度假目标干扰
                jam_params.pull = 5e5;        % 拖引频率 Hz
                [pure_jam, jam_info] = generate_4vgpo_jamming(tx, jam_params, 1);
                % 记录VGPO参数
                metadata(m).jam_params.vgpo_pull = jam_params.pull;
                metadata(m).jam_params.vgpo_doppler_direction = jam_info(1).doppler_direction;
                metadata(m).jam_params.vgpo_final_fd_kHz = jam_info(1).final_fd_kHz;

            case 5
                jam_params = params;
                jam_params.JNR = current_jnr; % 瞄准干扰
                jam_params.BJ = (18.5+5*rand)*1e6;         % 干扰带宽
                jam_params.random_Fj = true;  % 随机载波频率
                [pure_jam] = generate_5ab_jamming(tx, jam_params, 1);
                metadata(m).jam_params.aj_BJ = jam_params.BJ;

            case 6
                jam_params = params;
                jam_params.JNR = current_jnr; % 阻塞干扰
                jam_params.BJ = (45+10*rand)*1e6;         % 干扰带宽
                jam_params.random_Fj = true;  % 随机载波频率
                [pure_jam] = generate_5ab_jamming(tx, jam_params, 1);
                metadata(m).jam_params.bj_BJ = jam_params.BJ;

            case 7
                jam_params = params;
                jam_params.JNR = current_jnr;  % 扫频干扰
                jam_params.BJ = (10+20*rand)*1e6;          % 干扰带宽
                [pure_jam] = generate_7sj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.sj_BJ = jam_params.BJ;

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
                jam_params.JNR = current_jnr; % 弥散谱干扰
                [pure_jam, jam_info] = generate_10smspj_jamming(tx, jam_params, 1);
                % 记录SMSPJ参数：扫频分段数M，STFT图表现为M个陡峭斜线
                metadata(m).jam_params.smspj_M = jam_info(1).M;
                metadata(m).jam_params.smspj_slope_factor = jam_info(1).slope_factor;

            case 11
                jam_params = params;
                jam_params.JNR = current_jnr; % 切片交织干扰
                [pure_jam, jam_info] = generate_11cij_jamming(tx, jam_params, 1);
                % 记录CIJ参数：转发无间隔，STFT连续（与ISRJ区别）
                metadata(m).jam_params.cij_a = jam_info(1).a;
                metadata(m).jam_params.cij_b = jam_info(1).b;
                metadata(m).jam_params.cij_is_continuous = jam_info(1).is_continuous;

            case 12
                jam_params = params;
                jam_params.JNR = current_jnr; % 噪声调频干扰
                jam_params.BJ = max(20e6, (15+0*rand)*1e6);  % 干扰带宽
                jam_params.random_Fj = true;  % 随机载波频率
                [pure_jam] = generate_12nfmj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.nfmj_BJ = jam_params.BJ;

            case 13
                jam_params = params;
                jam_params.JNR = current_jnr; % 噪声调相干扰
                jam_params.BJ = max(20e6, (15+0*rand)*1e6);  % 干扰带宽
                jam_params.random_Fj = true;  % 随机载波频率
                [pure_jam] = generate_13npmj_jammingr(tx, jam_params, 1);
                metadata(m).jam_params.npmj_BJ = jam_params.BJ;

            case 14
                jam_params = params;
                jam_params.JNR = current_jnr; % 噪声调幅干扰
                jam_params.BJ = max(20e6, (15+0*rand)*1e6);  % 干扰带宽
                jam_params.random_Fj = true;  % 随机载波频率
                [pure_jam] = generate_14namj_jammingr(tx, jam_params, 1);
                metadata(m).jam_params.namj_BJ = jam_params.BJ;

            case 15
                jam_params = params;
                jam_params.JNR = current_jnr; % 梳状谱干扰
                [pure_jam, jam_info] = generate_15csj_jamming(tx, jam_params, 1);
                % 记录CSJ参数：梳齿数，STFT图表现为密集梳齿状斜线
                metadata(m).jam_params.csj_M = jam_info(1).M;
                metadata(m).jam_params.csj_comb_teeth_count = jam_info(1).comb_teeth_count;

            case 16
                jam_params = params;
                jam_params.JNR = current_jnr; % 脉冲干扰
                [pure_jam] = generate_16pulse_jamming(tx, jam_params, 1);
        end
        sum_jam = sum_jam+pure_jam;
    end
    % --- 混合信号 ---
    pure_echo = As * tx;
    random_phase = exp(rand*2*pi*1i);
    rx = pure_echo * random_phase + sum_jam + white_noise;

    % --- 归一化 (防止梯度爆炸) ---
    % rx = rx / max(abs(rx));
    samples(m, :) = rx;
end
end