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
addpath(fullfile(root_path, 'utils', 'features'));

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
SAMPLE_NUM = sum([generation_plan{:, 2}]);

tic
for current_jnr = JNR_values
    % 初始化数据容器
    fprintf('当前 JNR = %d dB\n', current_jnr);
    all_times = zeros(SAMPLE_NUM, params.PRI_samp);
    need_stft = cfg.output.save_stft || cfg.output.save_persistence;
    if need_stft
        N_cols = floor((params.N_total - Noverlap) / Step);
        all_stfts = zeros(SAMPLE_NUM, Nfft, N_cols);
    end

    % 初始化metadata数组
    all_metadata = struct('sample_idx', {}, 'jam_types', {}, 'JNR', {}, 'pos', {}, 'B', {}, 'taup', {}, 'mu', {}, 'sweep_dir', {}, 'jam_params', {});

    point_l = 1;
    for i = 1:len
        jam_types = generation_plan{i, 1};
        num_to_generate = generation_plan{i, 2};

        Aj = 10^(current_jnr/20);

        % 创建输出目录 (custom_dirname优先)
        if ~isempty(cfg.output.custom_dirname)
            time_str = cfg.output.custom_dirname;
        elseif cfg.output.use_datetime
            current_datetime = datetime('now', 'Format', 'yyMMdd');
            time_str = char(current_datetime);
        else
            time_str = 'default';
        end
        output_dir = fullfile(root_path, 'output', time_str);
        jnr_output_dir = fullfile(output_dir, sprintf('JNR_%+d', current_jnr));

        if ~exist(jnr_output_dir, 'dir')
            mkdir(jnr_output_dir);
        end

        % 生成样本 (使用配置中的参数)
        [new_times, new_metadata] = multi_generation_v2(jam_types, params, current_jnr, num_to_generate, cfg);

        if i ~= 1
            point_l = point_r + 1;
        end
        point_r = point_l + num_to_generate - 1;
        all_times(point_l:point_r, :) = new_times;
        all_metadata(point_l:point_r) = new_metadata;
    end

    % 计算STFT (持续时间谱也需要STFT)
    if need_stft
        fprintf('正在计算STFT (%d 样本)...\n', SAMPLE_NUM);
        t_stft = tic;
        win = hamming(Nwin);  % Hamming窗抑制频谱泄漏
        for i = 1:SAMPLE_NUM
            [S, F, T] = spectrogram(all_times(i, 1:params.PRI_samp), win, Noverlap, Nfft, params.fs, 'centered');
            all_stfts(i, :, :) = S;
        end
        fprintf('  STFT耗时: %.2f s\n', toc(t_stft));
    end

    % 计算持续时间谱 (Persistence Spectrum)
    if cfg.output.save_persistence
        fprintf('正在计算持续时间谱 (%d 样本)...\n', SAMPLE_NUM);
        t_pers = tic;
        num_power_bins = cfg.persistence.num_power_bins;
        if isfield(cfg.persistence, 'method') && ~isempty(cfg.persistence.method)
            pers_method = lower(char(cfg.persistence.method));
        else
            pers_method = 'custom';
        end
        all_persistences = zeros(SAMPLE_NUM, Nfft, num_power_bins);
        all_power_centers = [];  % matlab 模式下每样本功率轴可能不同

        if strcmp(pers_method, 'matlab')
            % 对齐 pspectrum("persistence"): 每样本独立 min/max + 5% cushion, 时间窗百分比
            fprintf('  模式: matlab (每样本功率轴独立, 值=时间窗百分比)\n');
            all_power_centers = zeros(SAMPLE_NUM, num_power_bins);
            for i = 1:SAMPLE_NUM
                [all_persistences(i, :, :), ~, pc] = compute_duration_spectrum( ...
                    squeeze(all_stfts(i, :, :)), num_power_bins, [], 'matlab');
                all_power_centers(i, :) = pc;
            end
            power_centers = all_power_centers(1, :);  % 兼容旧字段: 以样本1为参考
        else
            % custom: 第1样本百分位全局范围 + 行概率归一化
            pct_lo = 1;
            if isfield(cfg.persistence, 'power_percentile_lo')
                pct_lo = cfg.persistence.power_percentile_lo;
            end
            margin = 3;
            if isfield(cfg.persistence, 'power_margin_db')
                margin = cfg.persistence.power_margin_db;
            end
            pow_db1 = 10 * log10(abs(squeeze(all_stfts(1, :, :))).^2 + eps);
            pwr_lo = prctile(pow_db1(:), pct_lo);
            pwr_hi = max(pow_db1(:));
            global_pwr_range = [pwr_lo - margin, pwr_hi + margin];
            fprintf('  模式: custom | 全局功率范围 [%.1f, %.1f] dB (pct_lo=%.1f, margin=%.1f)\n', ...
                global_pwr_range(1), global_pwr_range(2), pct_lo, margin);
            for i = 1:SAMPLE_NUM
                [all_persistences(i, :, :), ~, power_centers] = compute_duration_spectrum( ...
                    squeeze(all_stfts(i, :, :)), num_power_bins, global_pwr_range, 'custom');
            end
        end
        fprintf('  持续时间谱耗时: %.2f s\n', toc(t_pers));
    end

    % 生成 RGB Colormap 数据 (用于数据增强)
    if cfg.output.save_stft_rgb
        fprintf('正在生成 RGB colormap 数据 (%d 样本)...\n', SAMPLE_NUM);
        t_rgb = tic;
        cmaps = cfg.stft_rgb.colormaps;
        num_cmaps = length(cmaps);

        % 计算全局归一化参数 (基于子集以加速)
        norm_mode = cfg.stft_rgb.normalization;  % 'dB' 或 'linear'
        sample_size = min(50, SAMPLE_NUM);
        sample_indices = randperm(SAMPLE_NUM, sample_size);
        sample_abs = abs(all_stfts(sample_indices, :, :));
        switch norm_mode
            case 'db'
                sample_mag = 20 * log10(sample_abs + eps);
            case 'linear'
                sample_mag = sample_abs;
        end
        norm_params.lo = prctile(sample_mag(:), cfg.stft_rgb.percentile_range(1));
        norm_params.hi = prctile(sample_mag(:), cfg.stft_rgb.percentile_range(2));
        fprintf('  %s归一化范围: [%.1f, %.1f] (百分位 [%d, %d])\n', ...
                upper(norm_mode), norm_params.lo, norm_params.hi, ...
                cfg.stft_rgb.percentile_range(1), cfg.stft_rgb.percentile_range(2));

        % 逐 colormap 生成, 保存为独立变量 (rgb_parula, rgb_jet, ...)
        for c = 1:num_cmaps
            cmap_name = cmaps{c};
            t_cmap = tic;
            rgb_data = zeros(SAMPLE_NUM, Nfft, N_cols, 3, 'uint8');
            for i = 1:SAMPLE_NUM
                rgb_data(i, :, :, :) = apply_colormap_to_stft(...
                    squeeze(all_stfts(i, :, :)), cmap_name, norm_params, norm_mode);
            end
            varname = ['rgb_', cmap_name];
            eval([varname ' = rgb_data;']);
            fprintf('  [%d/%d] %s: %dx%dx%d, 耗时 %.1fs\n', ...
                    c, num_cmaps, cmap_name, Nfft, N_cols, 3, toc(t_cmap));
        end
        colormap_names = cmaps; %#ok<NASGU>
        fprintf('  RGB生成总耗时: %.2f s\n', toc(t_rgb));
    end

    % 提取多域特征（并行加速）
    if cfg.output.extract_features
        fprintf('正在提取特征...\n');
        use_parallel = license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel')) && SAMPLE_NUM >= 50;
        feature_cell = cell(SAMPLE_NUM, 1);
        features_dir = fullfile(root_path, 'utils', 'features');
        if use_parallel
            parfor i = 1:SAMPLE_NUM
                addpath(features_dir);
                feature_cell{i} = extract_signal_features(all_times(i, 1:params.PRI_samp), params.fs);
            end
            fprintf('  并行完成, 处理 %d 个样本\n', SAMPLE_NUM);
        else
            for i = 1:SAMPLE_NUM
                feature_cell{i} = extract_signal_features(all_times(i, 1:params.PRI_samp), params.fs);
                if mod(i, 100) == 0
                    fprintf('  已处理 %d/%d 样本\n', i, SAMPLE_NUM);
                end
            end
        end
        all_features = feature_cell{1};
        for i = 2:SAMPLE_NUM
            all_features(i) = feature_cell{i};
        end
    else
        fprintf('特征提取已跳过 (cfg.output.extract_features = false)\n');
    end

    % 根据配置设置输出路径
    dataset_type = cfg.output.dataset_type;
    path_stfts = fullfile(jnr_output_dir, sprintf('%s_echo_stfts.mat', dataset_type));
    path_persistences = fullfile(jnr_output_dir, sprintf('%s_echo_persistences.mat', dataset_type));
    path_stfts_rgb = fullfile(jnr_output_dir, sprintf('%s_echo_stfts_rgb.mat', dataset_type));
    path_times = fullfile(jnr_output_dir, sprintf('%s_echo_times.mat', dataset_type));
    path_metadata = fullfile(jnr_output_dir, sprintf('%s_echo_metadata.json', dataset_type));
    path_features = fullfile(jnr_output_dir, sprintf('%s_echo_features.json', dataset_type));
    path_plan_mat = fullfile(jnr_output_dir, 'generation_plan.mat');
    path_plan_json = fullfile(jnr_output_dir, 'generation_plan.json');

    % 保存数据
    if cfg.output.save_stft
        all_stfts = single(all_stfts);
        save(path_stfts, 'all_stfts', '-v7.3', '-nocompression');
    end
    if cfg.output.save_persistence
        all_persistences = single(all_persistences);
        persistence_method = pers_method; %#ok<NASGU>
        if ~isempty(all_power_centers)
            all_power_centers = single(all_power_centers); %#ok<NASGU>
            save(path_persistences, 'all_persistences', 'num_power_bins', 'power_centers', ...
                'all_power_centers', 'persistence_method', 'F', '-v7.3');
        else
            save(path_persistences, 'all_persistences', 'num_power_bins', 'power_centers', ...
                'persistence_method', 'F', '-v7.3');
        end
    end
    if cfg.output.save_stft_rgb
        % 动态构建保存变量列表, 将每种 colormap 作为独立变量保存
        cmaps = cfg.stft_rgb.colormaps;
        save_vars = {};
        for c = 1:length(cmaps)
            save_vars{end+1} = ['rgb_', cmaps{c}]; %#ok<AGROW>
        end
        save_vars{end+1} = 'colormap_names';
        save_vars{end+1} = 'F';
        save_vars{end+1} = 'T';
        save_vars{end+1} = 'norm_params';
        save(path_stfts_rgb, save_vars{:}, '-v7.3');
        info = dir(path_stfts_rgb);
        fprintf('  RGB已保存: %s (%.1f MB)\n', path_stfts_rgb, info.bytes / 1e6);
    end
    all_times = single(all_times);
    save(path_times, 'all_times', '-v7.3', '-nocompression');
    save(path_plan_mat, 'generation_plan', '-v7.3', '-nocompression');

    % 保存generation_plan为JSON格式 (便于查看)
    plan_struct = struct('jam_types', {}, 'sample_num', {});
    for p = 1:size(generation_plan, 1)
        jt = generation_plan{p, 1};
        if iscell(jt)
            plan_struct(p).jam_types = jt;
        else
            plan_struct(p).jam_types = {jt};
        end
        plan_struct(p).sample_num = generation_plan{p, 2};
    end
    fid = fopen(path_plan_json, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(plan_struct));
    fclose(fid);

    % 保存metadata为JSON格式
    % jsonencode可以直接处理struct数组
    jsonStr = jsonencode(all_metadata);
    fid = fopen(path_metadata, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonStr);
    fclose(fid);

    % 保存特征为JSON格式
    if cfg.output.extract_features
        jsonStr = jsonencode(all_features);
        fid = fopen(path_features, 'w', 'n', 'UTF-8');
        fprintf(fid, '%s', jsonStr);
        fclose(fid);
    end

    fprintf('已保存到: %s\n', jnr_output_dir);
end
toc

fprintf('数据生成完成!\n');

if SAMPLE_NUM < 100
    % 根据启用的可视化类型确定行数
    has_stft  = cfg.output.save_stft && exist('all_stfts','var');
    has_pers  = cfg.output.save_persistence && exist('all_persistences','var');
    num_rows  = 1 + has_stft + has_pers;  % 时域始终显示

    split_num = ceil(SAMPLE_NUM/4);
    for j = 0:split_num-1
        figure(j+1)
        for i = 1:4
            sample_idx = 4*j + i;
            if sample_idx > SAMPLE_NUM, break; end

            % --- 行1: 时域 ---
            subplot(num_rows, 4, i)
            t_axis = params.t_total;
            plot(t_axis, real(all_times(sample_idx,:)));
            xlabel('时间 (us)'); ylabel('幅度'); grid on;

            % --- 行2: STFT (优先) 或 持续时间谱 ---
            if has_stft
                subplot(num_rows, 4, 4 + i)
                imagesc(T*1e6, F/1e6, abs((squeeze(all_stfts(sample_idx,:,:)))) + eps);
                axis xy;
                set(gca, 'YDir', 'normal');
                xlabel('时间 (us)'); ylabel('频率 (MHz)');
                title('短时傅里叶变换'); grid on;colorbar;
            elseif has_pers
                subplot(num_rows, 4, 4 + i)
                imagesc(F/1e6, power_centers, squeeze(all_persistences(sample_idx,:,:))');
                set(gca, 'YDir', 'normal');
                xlabel('频率 (MHz)'); ylabel('功率 (dB)');
                title('持续时间谱'); colorbar;
            end

            % --- 行3: 持续时间谱 (仅在STFT也存在时) ---
            if has_stft && has_pers
                subplot(num_rows, 4, 8 + i)
                imagesc(F/1e6, power_centers, squeeze(all_persistences(sample_idx,:,:))');
                set(gca, 'YDir', 'normal');
                xlabel('频率 (MHz)'); ylabel('功率 (dB)');
                title('持续时间谱'); colorbar;
            end
        end
    end
end