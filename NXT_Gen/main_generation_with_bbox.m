% ==========================================================
% main_generation_with_bbox.m - 带bounding box的主数据生成脚本
% ==========================================================
% 功能：
% 1. 生成干扰信号数据
% 2. 在生成过程中直接计算bounding box（避免事后检测误差）
% 3. 保存STFT数据、标签和bounding box信息
% ==========================================================

clear; clc; close all;
tic

% --- 1. 公共参数设置 ---
params.fs = 80e6;        % 采样频率 80MHz
params.fc = 40e6;        % 中心频率 40MHz
params.B = 10e6;         % 带宽    10MHz
params.taup = 20e-6;     % LFM脉宽 20us
params.Np = 1;           % 脉冲个数 1
params.PRI = 100e-6;     % 脉冲重复间隔 100us
params.SNR = 15;         % 信噪比
params.numClasses = 16;  % 基础九种干扰
SAMPLE_NUM_S = 2;
SAMPLE_NUM_M = 5;
% JNR_values = 5:5:50;    %干噪比范围 dB
JNR_values = 15;    %干噪比范围 dB
params.pos = 1000+randi([0 6000]);  % 在PRI中第5000点处

% STFT参数（与Python脚本保持一致）
params.stft_window = 128;
params.stft_overlap = 64;
params.stft_nfft = 64;

% --- 2. 生成计划 ---
% 定义要生成的干扰类型和对应的标签
generation_plan = {
    % 欺骗干扰
    % 'DFTJ' , 1,  SAMPLE_NUM_S;
    'ISRJ' , 2,  SAMPLE_NUM_S;
    % 'SMSPJ', 10, SAMPLE_NUM_S;
    % 'C&IJ' , 11, SAMPLE_NUM_S;
    % 'CSJ'  , 15, SAMPLE_NUM_S;
    %
    % % 压制干扰
    % 'AJ'   , 5, SAMPLE_NUM_S;
    % 'BJ'   , 6, SAMPLE_NUM_S;
    % 'SJ'   , 7, SAMPLE_NUM_S;
    % 'NCJ'  , 8, SAMPLE_NUM_S;
    % 'NPJ'  , 9, SAMPLE_NUM_S;
    % 'NFMJ' , 12, SAMPLE_NUM_S;
    % 'NPMJ' , 13, SAMPLE_NUM_S;
    % 'NAMJ' , 14, SAMPLE_NUM_S;
    % 'PJ'   , 16, SAMPLE_NUM_S;
};

% --- 3. 执行生成 ---
[tx, params] = generate_0base_signal(params);
toc

%% 循环生成每种干扰
len = size(generation_plan, 1);
SAMPLE_NUM = sum([generation_plan{:, 3}]);

% STFT尺寸计算
params.PRI_samp = round(params.PRI * params.fs);
[S, ~, ~] = spectrogram(tx(1:params.PRI_samp), ...
    params.stft_window, params.stft_overlap, ...
    params.stft_nfft, params.fs, 'centered');
stft_size = size(S);  % [freq_bins, time_bins]
fprintf('STFT尺寸: %d x %d\n', stft_size(1), stft_size(2));

tic
for current_jnr = JNR_values
    % 初始化数据容器
    current_jnr
    all_times = zeros(SAMPLE_NUM, params.PRI_samp);
    all_label = zeros(SAMPLE_NUM, params.numClasses);
    all_stfts = zeros(SAMPLE_NUM, stft_size(1), stft_size(2));

    % 新增：bounding box容器
    % 每个样本可能有多个bounding box，使用cell数组存储
    all_bboxes = cell(SAMPLE_NUM, 1);

    point_l = 1;

    for i = 1:len
        jam_type = generation_plan{i, 1};
        label = generation_plan{i, 2};
        num_to_generate = generation_plan{i, 3};

        Aj = 10^(current_jnr/20);

        % 创建当前JNR值的子文件夹
        current_datetime = datetime('now', 'Format', 'yyMMdd');
        time_str = char(current_datetime);
        snr_output_dir = fullfile(time_str, sprintf('JNR_%+d', current_jnr));

        if ~exist(snr_output_dir, 'dir')
            mkdir(snr_output_dir);
        end

        % 调用带bounding box计算的生成函数
        [new_times, new_label, new_bboxes] = ...
            multi_generation_with_bbox(label, params, current_jnr, num_to_generate);

        if i ~= 1
            point_l = point_r + 1;
        end
        point_r = point_l + num_to_generate - 1;

        all_times(point_l:point_r, :) = new_times;
        all_label(point_l:point_r, :) = new_label;
        all_bboxes(point_l:point_r) = new_bboxes;

        fprintf('  %s: 生成 %d 个样本，每个样本平均 %.1f 个bounding box\n', ...
            jam_type, num_to_generate, mean(cellfun(@length, new_bboxes)));
    end

    % 计算STFT
    for i = 1:SAMPLE_NUM
        [S, F, T] = spectrogram(all_times(i, 1:params.PRI_samp), ...
            params.stft_window, params.stft_overlap, ...
            params.stft_nfft, params.fs, 'centered');
        all_stfts(i, :, :) = S;
    end

    % 保存数据
    path_stfts = fullfile(snr_output_dir, 'val_echo_stfts.mat');
    path_times = fullfile(snr_output_dir, 'val_echo_times.mat');
    path_label = fullfile(snr_output_dir, 'val_echo_label.mat');
    path_bboxes = fullfile(snr_output_dir, 'val_echo_bboxes.mat');

    save(path_stfts, 'all_stfts', '-v7.3');
    save(path_times, 'all_times', '-v7.3');
    save(path_label, 'all_label', '-v7.3');
    save(path_bboxes, 'all_bboxes', '-v7.3');

    % 保存bounding box为YOLO格式的.txt文件
    bbox_txt_dir = fullfile(snr_output_dir, 'bbox_labels');
    if ~exist(bbox_txt_dir, 'dir')
        mkdir(bbox_txt_dir);
    end

    for i = 1:SAMPLE_NUM
        bbox_file = fullfile(bbox_txt_dir, sprintf('sample_%06d.txt', i));
        yolo_bboxes = all_bboxes{i};

        % 如果有bounding box，保存为txt文件
        if ~isempty(yolo_bboxes)
            % YOLO格式: class_id x_center y_center width height
            % 每行一个bounding box
            writematrix(yolo_bboxes, bbox_file, 'Delimiter', ' ');
        else
            % 如果没有bounding box，创建空文件
            fid = fopen(bbox_file, 'w');
            fclose(fid);
        end
    end

    fprintf('  保存完成: %s\n', snr_output_dir);
end
toc

fprintf('\n=== 生成完成 ===\n');
fprintf('数据已保存到: %s\n', time_str);
fprintf('每个JNR级别包含:\n');
fprintf('  - train_echo_stfts.mat: STFT数据\n');
fprintf('  - train_echo_times.mat: 时域信号\n');
fprintf('  - train_echo_label.mat: 标签\n');
fprintf('  - train_echo_bboxes.mat: bounding box信息\n');
fprintf('  - bbox_labels/*.txt: YOLO格式bounding box\n');

len = generation_plan{1, 3};
disp(generation_plan{1, 1})
for i =1:len
    rx = all_times(i,:);
    figure(i);
    subplot(1,2,1);
    plot(params.t_total*1e3, real(rx));
    % axis([0 3.2 -1.1 1.1])
    axis tight;
    xlabel('Time / ms'); ylabel('Amplitude');

    subplot(1,2,2);

    [S,F,T] = spectrogram(rx(1:params.PRI_samp),128,64,256,params.fs, 'centered');
    % S = all_S(50*i-49,:,:);
    S = squeeze(S);
    imagesc(T*1e6,F/1e6,abs(S));
    xlabel('Time/μs'); ylabel('Frequency/MHz');

    % 在STFT图上绘制bounding box
    yolo_bboxes = all_bboxes{i};
    if ~isempty(yolo_bboxes)
        hold on;
        for bbox_idx = 1:size(yolo_bboxes, 1)
            % YOLO格式: [class_id, x_center, y_center, width, height]
            class_id = yolo_bboxes(bbox_idx, 1);
            x_center = yolo_bboxes(bbox_idx, 2);
            y_center = yolo_bboxes(bbox_idx, 3);
            width = yolo_bboxes(bbox_idx, 4);
            height = yolo_bboxes(bbox_idx, 5);

            % 转换回像素坐标
            stft_time_bins = size(S, 2);
            stft_freq_bins = size(S, 1);

            x_min = (x_center - width/2) * stft_time_bins;
            x_max = (x_center + width/2) * stft_time_bins;
            y_min = (y_center - height/2) * stft_freq_bins;
            y_max = (y_center + height/2) * stft_freq_bins;

            % 转换为实际的物理坐标（时间、频率）
            time_min = T(int8(x_min)) * 1e6;  % 转换为μs
            time_max = T(int8(x_max)) * 1e6;
            freq_min = F((y_min)) / 1e6;  % 转换为MHz
            freq_max = F((y_max)) / 1e6;

            % 绘制矩形
            rectangle('Position', [time_min, freq_min, time_max-time_min, freq_max-freq_min], ...
                'EdgeColor', 'r', 'LineWidth', 2);

            % 添加类别标签
            text(time_min, freq_max + 0.5, sprintf('Class:%d', class_id), ...
                'Color', 'r', 'FontSize', 8, 'FontWeight', 'bold');
        end
        hold off;
    end
end
