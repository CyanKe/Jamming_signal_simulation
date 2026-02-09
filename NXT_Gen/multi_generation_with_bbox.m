function [samples, labels, bboxes] = multi_generation_with_bbox(label, params, current_jnr, data_num)
% multi_generation_with_bbox - 生成干扰信号并计算bounding box
%
% 输出：
%   samples: 时域信号 [data_num, N_total]
%   labels:  one-hot编码标签 [data_num, numClasses]
%   bboxes:  bounding box信息，cell数组，每个元素是[N_bbox, 4]矩阵
%           格式: [x_min, y_min, x_max, y_max] (像素坐标)

% 初始化输出
numClasses = params.numClasses;
N_total = params.N_total;
As = 10^(params.SNR/20);
samples = zeros(data_num, N_total);
oneHotEncoded = convertLabelsToOneHot(label, numClasses);
labels = ones(data_num, numClasses) .* oneHotEncoded;

% STFT参数
fs = params.fs;
stft_window = params.stft_window;
stft_overlap = params.stft_overlap;
stft_nfft = params.stft_nfft;

% 频率轴（用于计算频域bounding box）
freq_axis = linspace(-fs/2, fs/2, stft_nfft);

for m = 1:data_num
    % 生成基础目标信号 (所有干扰类型共用)
    params.pos = 500 + randi([0 5000]);  % 在PRI中随机位置
    [tx, params] = generate_0base_signal(params);

    % --- 生成噪声 ---
    white_noise = randn([1, N_total]) + 1j * randn([1, N_total]);
    white_noise = white_noise / std(white_noise);  % 标准化
    sum_jam = zeros(1, N_total);

    % 存储当前样本的所有bounding box
    current_bboxes = [];

    for jam_type = label
        switch jam_type
            case 1  % DFTJ - 密集假目标干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, bbox_info] = generate_1dftj_jamming(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 2  % ISRJ - 间歇采样转发干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, bbox_info] = generate_2isrj_jamming(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 3  % RGPO - 距离假目标干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.v = 5e5;
                [pure_jam, bbox_info] = generate_3rgpo_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 4  % VGPO - 速度假目标干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.pull = 5e5;
                [pure_jam, bbox_info] = generate_4vgpo_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 5  % AJ - 瞄准干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.BJ = 20e6;  % 干扰带宽 20MHz
                [pure_jam, bbox_info] = generate_5ab_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 6  % BJ - 阻塞干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.BJ = 45e6;  % 干扰带宽 45MHz
                [pure_jam, bbox_info] = generate_5ab_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 7  % SJ - 扫频干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.BJ = 10e6;
                [pure_jam, bbox_info] = generate_7sj_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 8  % NCJ - 噪声卷积干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, bbox_info] = generate_8ncj_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 9  % NPJ - 噪声乘积干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, bbox_info] = generate_9npj_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 10 % SMSPJ - 弥散谱干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, bbox_info] = generate_10smspj_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 11 % C&IJ - 切片交织干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, bbox_info] = generate_11cij_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 12 % NFMJ - 噪声调频干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.BJ = 40e6;
                [pure_jam, bbox_info] = generate_12nfmj_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 13 % NPMJ - 噪声调相干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.BJ = (35 + 5 * randn) * 1e6;
                [pure_jam, bbox_info] = generate_13npmj_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 14 % NAMJ - 噪声调幅干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                jam_params.BJ = 20e6;
                [pure_jam, bbox_info] = generate_14namj_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 15 % CSJ - 梳状谱干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, bbox_info] = generate_15csj_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];

            case 16 % PJ - 脉冲干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, bbox_info] = generate_16pulse_jamming_with_bbox(tx, jam_params, 1);
                current_bboxes = [current_bboxes; bbox_info];
        end
        sum_jam = sum_jam + pure_jam;
    end

    % --- 混合信号 ---
    pure_echo = As * tx;
    rx = pure_echo + sum_jam + white_noise;

    % --- 归一化 (防止梯度爆炸) ---
    rx = rx / max(abs(rx));
    samples(m, :) = rx;

    % --- 计算STFT并转换bounding box到YOLO格式 ---
    % 计算STFT
    [S, F, T] = spectrogram(rx(1:params.PRI_samp), ...
        stft_window, stft_overlap, stft_nfft, fs, 'centered');

    % STFT尺寸
    stft_freq_bins = size(S, 1);  % 频率维度（图像高度）
    stft_time_bins = size(S, 2);  % 时间维度（图像宽度）

    % 转换bounding box到YOLO格式
    % YOLO格式: [class_id, x_center, y_center, width, height]
    % 所有值归一化到0-1之间
    % x_center, width 相对于图像宽度（时间维度）
    % y_center, height 相对于图像高度（频率维度）
    yolo_bboxes = [];

    if ~isempty(current_bboxes)
        for bbox_idx = 1:size(current_bboxes, 1)
            x_min = current_bboxes(bbox_idx, 1);  % 时域起始（采样点）
            y_min = current_bboxes(bbox_idx, 2);  % 频域起始（Hz）
            x_max = current_bboxes(bbox_idx, 3);  % 时域结束（采样点）
            y_max = current_bboxes(bbox_idx, 4);  % 频域结束（Hz）

            % 转换时域坐标到STFT时间轴
            % STFT时间轴: T = linspace(0, PRI, stft_time_bins)
            PRI = params.PRI;
            time_axis = linspace(0, PRI, stft_time_bins);

            % 找到最接近的时间bin
            [~, time_idx_min] = min(abs(time_axis - x_min / fs));
            [~, time_idx_max] = min(abs(time_axis - x_max / fs));

            % 转换频域坐标到STFT频率轴
            % STFT频率轴: F (Hz)
            [~, freq_idx_min] = min(abs(F - y_min));
            [~, freq_idx_max] = min(abs(F - y_max));

            % 确保坐标在有效范围内
            time_idx_min = max(1, min(time_idx_min, stft_time_bins));
            time_idx_max = max(1, min(time_idx_max, stft_time_bins));
            freq_idx_min = max(1, min(freq_idx_min, stft_freq_bins));
            freq_idx_max = max(1, min(freq_idx_max, stft_freq_bins));

            % 确保min < max
            if time_idx_min > time_idx_max
                [time_idx_min, time_idx_max] = deal(time_idx_max, time_idx_min);
            end
            if freq_idx_min > freq_idx_max
                [freq_idx_min, freq_idx_max] = deal(freq_idx_max, freq_idx_min);
            end

            % 计算YOLO格式的归一化坐标
            % x_center = (time_idx_min + time_idx_max) / 2 / stft_time_bins
            % y_center = (freq_idx_min + freq_idx_max) / 2 / stft_freq_bins
            % width = (time_idx_max - time_idx_min) / stft_time_bins
            % height = (freq_idx_max - freq_idx_min) / stft_freq_bins
            x_center = (time_idx_min + time_idx_max) / 2 / stft_time_bins;
            y_center = (freq_idx_min + freq_idx_max) / 2 / stft_freq_bins;
            width = (time_idx_max - time_idx_min) / stft_time_bins;
            height = (freq_idx_max - freq_idx_min) / stft_freq_bins;

            % 添加到YOLO bounding box列表
            % class_id = label (从1开始，但YOLO通常从0开始，这里保持原样)
            yolo_bboxes = [yolo_bboxes; ...
                label, x_center, y_center, width, height];
        end
    end

    % 存储YOLO格式的bounding box
    bboxes{m} = yolo_bboxes;
end
end
