function [samples,labels,metadata] = multi_generation_v2(label,params,current_jnr,data_num,cfg)
% multi_generation_v2 - 使用配置文件生成多干扰类型样本
% 输入:
%   label - 干扰类型标签数组 (如 [1] 或 [1,5])
%   params - 信号参数结构体
%   current_jnr - 当前干噪比 dB
%   data_num - 生成样本数
%   cfg - 配置结构体
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
    metadata(m).jam_types = label(:)';  % 强制转为行向量，确保JSON输出为数组
    metadata(m).JNR = current_jnr;
    metadata(m).jam_params = struct();

    % 生成基础目标信号 (所有干扰类型共用)
    pos_range = cfg.generation.pos_range;
    current_pos = pos_range(1) + randi([0, pos_range(2)-pos_range(1)]);
    params.pos = current_pos;
    metadata(m).pos = current_pos;

    [tx, params] = generate_0base_signal(params);

    % --- 生成噪声 ---
    white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
    white_noise = white_noise / std(white_noise);
    sum_jam = zeros(1, N_total);

    for jam_type = label
        switch jam_type
            case 1  % DFTJ - 密集假目标干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam,~,jam_info] = generate_1dftj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.dftj_k = jam_info(1).k;

            case 2  % ISRJ - 间歇采样转发干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam,~,jam_info] = generate_2isrj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.isrj_M = jam_info(1).M;
                metadata(m).jam_params.isrj_N = jam_info(1).N;

            case 3  % RGPO - 距离假目标干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.v = cfg.jamming.rgpo.v;  % 从配置读取
                [pure_jam, jam_info] = generate_3rgpo_jamming(tx, jam_params, 1);
                metadata(m).jam_params.rgpo_v = jam_params.v;
                metadata(m).jam_params.rgpo_position_relation = jam_info(1).position_relation;
                metadata(m).jam_params.rgpo_final_delay_us = jam_info(1).final_delay_us;

            case 4  % VGPO - 速度假目标干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.pull = cfg.jamming.vgpo.pull;  % 从配置读取
                jam_params.start_time = cfg.jamming.vgpo.start_time;  % 从配置读取
                [pure_jam, jam_info] = generate_4vgpo_jamming(tx, jam_params, 1);
                metadata(m).jam_params.vgpo_pull = jam_params.pull;
                metadata(m).jam_params.vgpo_start_time = jam_params.start_time;
                metadata(m).jam_params.vgpo_doppler_direction = jam_info(1).doppler_direction;
                metadata(m).jam_params.vgpo_final_fd_kHz = jam_info(1).final_fd_kHz;

            case 5  % AJ - 瞄准干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.aj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
                jam_params.random_Fj = cfg.jamming.aj.random_Fj;
                [pure_jam] = generate_5ab_jamming(tx, jam_params, 1);
                metadata(m).jam_params.aj_BJ = jam_params.BJ;

            case 6  % BJ - 阻塞干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.bj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
                jam_params.random_Fj = cfg.jamming.bj.random_Fj;
                [pure_jam] = generate_5ab_jamming(tx, jam_params, 1);
                metadata(m).jam_params.bj_BJ = jam_params.BJ;

            case 7  % SJ - 扫频干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.sj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
                [pure_jam] = generate_7sj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.sj_BJ = jam_params.BJ;

            case 8  % NCJ - 噪声卷积干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam] = generate_8ncj_jamming(tx, jam_params, 1);

            case 9  % NPJ - 噪声乘积干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam] = generate_9npj_jamming(tx, jam_params, 1);

            case 10 % SMSPJ - 弥散谱干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, jam_info] = generate_10smspj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.smspj_M = jam_info(1).M;
                metadata(m).jam_params.smspj_slope_factor = jam_info(1).slope_factor;

            case 11 % CIJ - 切片交织干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, jam_info] = generate_11cij_jamming(tx, jam_params, 1);
                metadata(m).jam_params.cij_a = jam_info(1).a;
                metadata(m).jam_params.cij_b = jam_info(1).b;
                metadata(m).jam_params.cij_is_continuous = jam_info(1).is_continuous;

            case 12 % NFMJ - 噪声调频干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.nfmj.BJ_range;
                jam_params.BJ = max(20e6, (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6);
                jam_params.random_Fj = cfg.jamming.nfmj.random_Fj;
                [pure_jam] = generate_12nfmj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.nfmj_BJ = jam_params.BJ;

            case 13 % NPMJ - 噪声调相干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.npmj.BJ_range;
                jam_params.BJ = max(20e6, (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6);
                jam_params.random_Fj = cfg.jamming.npmj.random_Fj;
                [pure_jam] = generate_13npmj_jammingr(tx, jam_params, 1);
                metadata(m).jam_params.npmj_BJ = jam_params.BJ;

            case 14 % NAMJ - 噪声调幅干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.namj.BJ_range;
                jam_params.BJ = max(20e6, (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6);
                jam_params.random_Fj = cfg.jamming.namj.random_Fj;
                [pure_jam] = generate_14namj_jammingr(tx, jam_params, 1);
                metadata(m).jam_params.namj_BJ = jam_params.BJ;

            case 15 % CSJ - 梳状谱干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, jam_info] = generate_15csj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.csj_M = jam_info(1).M;
                metadata(m).jam_params.csj_comb_teeth_count = jam_info(1).comb_teeth_count;

            case 16 % PJ - 脉冲干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam] = generate_16pulse_jamming(tx, jam_params, 1);
        end
        sum_jam = sum_jam + pure_jam;
    end

    % --- 混合信号 ---
    pure_echo = As * tx;
    random_phase = exp(rand*2*pi*1i);
    rx = pure_echo * random_phase + sum_jam + white_noise;

    samples(m, :) = rx;
end
end