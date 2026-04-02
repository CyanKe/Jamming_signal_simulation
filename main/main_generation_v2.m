% ==========================================================
% main_generation_v2.m - 使用配置文件的主数据生成脚本
% ==========================================================
clear; clc; close all;

% 添加路径
script_path = fileparts(mfilename('fullpath'));
root_path = fileparts(script_path);
addpath(root_path);  % 添加config.m路径
addpath(fullfile(root_path, 'generators', 'base'));
addpath(fullfile(root_path, 'generators', 'deceptive'));
addpath(fullfile(root_path, 'generators', 'suppressive'));
addpath(fullfile(root_path, 'utils'));

tic

% --- 1. 加载配置 ---
cfg = config(); % 需要根据具体使用配置修改
params = config_to_params(cfg);

% --- 2. 执行生成 ---
[tx, params] = generate_0base_signal(params);
toc

% 从配置获取生成计划
generation_plan = cfg.generation_plan;
JNR_values = cfg.jamming.JNR_values;

% STFT参数
Nwin = cfg.stft.Nwin;
Noverlap = cfg.stft.Noverlap;
Nfft = cfg.stft.Nfft;
Step = Nwin - Noverlap;

%% 循环生成每种干扰
len = size(generation_plan, 1);
SAMPLE_NUM = sum([generation_plan{:, 3}]);

tic
for current_jnr = JNR_values
    % 初始化数据容器
    fprintf('当前 JNR = %d dB\n', current_jnr);
    all_times = zeros(SAMPLE_NUM, params.PRI_samp);
    all_label = zeros(SAMPLE_NUM, params.numClasses);
    N_cols = floor((params.N_total - Noverlap) / Step);
    all_stfts = zeros(SAMPLE_NUM, Nfft, N_cols);

    % 初始化metadata数组
    all_metadata = struct('sample_idx', {}, 'jam_types', {}, 'JNR', {}, 'pos', {}, 'jam_params', {});

    point_l = 1;
    for i = 1:len
        jam_type = generation_plan{i, 1};
        label = generation_plan{i, 2};
        num_to_generate = generation_plan{i, 3};

        Aj = 10^(current_jnr/20);

        % 创建输出目录
        if cfg.output.use_datetime
            current_datetime = datetime('now', 'Format', 'yyMMdd');
            time_str = char(current_datetime);
        else
            time_str = cfg.output.custom_dirname;
        end
        output_dir = fullfile(root_path, 'output', time_str);
        snr_output_dir = fullfile(output_dir, sprintf('JNR_%+d', current_jnr));

        if ~exist(snr_output_dir, 'dir')
            mkdir(snr_output_dir);
        end

        % 生成样本 (使用配置中的参数)
        [new_times, new_label, new_metadata] = multi_generation_v2(label, params, current_jnr, num_to_generate, cfg);

        if i ~= 1
            point_l = point_r + 1;
        end
        point_r = point_l + num_to_generate - 1;
        all_times(point_l:point_r, :) = new_times;
        all_label(point_l:point_r, :) = new_label;
        all_metadata(point_l:point_r) = new_metadata;
    end

    % 计算STFT
    for i = 1:SAMPLE_NUM
        [S, F, T] = spectrogram(all_times(i, 1:params.PRI_samp), Nwin, Noverlap, Nfft, params.fs, 'centered');
        all_stfts(i, :, :) = S;
    end

    % 根据配置设置输出路径
    dataset_type = cfg.output.dataset_type;
    path_stfts = fullfile(snr_output_dir, sprintf('%s_echo_stfts.mat', dataset_type));
    path_times = fullfile(snr_output_dir, sprintf('%s_echo_times.mat', dataset_type));
    path_label = fullfile(snr_output_dir, sprintf('%s_echo_label.mat', dataset_type));
    path_metadata = fullfile(snr_output_dir, sprintf('%s_echo_metadata.json', dataset_type));

    % 保存数据
    all_stfts = single(all_stfts);
    all_times = single(all_times);
    save(path_stfts, 'all_stfts', '-v7.3');
    save(path_times, 'all_times', '-v7.3');
    save(path_label, 'all_label', '-v7.3');

    % 保存metadata为JSON格式
    % jsonencode可以直接处理struct数组
    jsonStr = jsonencode(all_metadata);
    fid = fopen(path_metadata, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonStr);
    fclose(fid);

    fprintf('已保存到: %s\n', snr_output_dir);
end
toc

fprintf('数据生成完成!\n');

split_num = round(SAMPLE_NUM/4);
for j = 0:split_num-1
figure(j+1)
for i = 1:4
    subplot(2,4,i)
    t_axis = params.t_total;% 时间轴 us
    plot(t_axis, real(all_times(4*j+i,:)));
    xlabel('时间 (us)');
    ylabel('幅度');
    grid on;

    subplot(2,4,4+i)
    imagesc(T*1e6, F/1e6, abs((squeeze(all_stfts(4*j+i,:,:)))) + eps);
    % colormap(Londres)
    axis xy;
    xlabel('时间 (us)');
    ylabel('频率 (MHz)');
    grid on;

end
end