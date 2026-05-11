%% ==========================================================
%% generate_features_from_times.m - 从已有时域数据生成特征
%% ==========================================================
%% 读取已生成的 all_times.mat 文件，提取多域特征并保存为JSON
%% 支持并行处理（需Parallel Computing Toolbox）
%%
%% 用法:
%%   1. 直接运行，自动查找最新输出目录并处理所有JNR子目录
%%      >> generate_features_from_times
%%
%%   2. 指定日期目录，处理其下所有JNR子目录
%%      >> generate_features_from_times('output/20us_multi')
%%
%%   3. 指定JNR目录，只处理该目录
%%      >> generate_features_from_times('output/20us_multi/JNR_+10')
%%
%%   4. 关闭并行模式
%%      >> generate_features_from_times('output/20us_multi', 'parallel', false)
%%
%%   5. 强制重新生成（覆盖已有文件）
%%      >> generate_features_from_times('output/20us_multi', 'force', true)

function generate_features_from_times(input_dir, varargin)
    if nargout == 0
        clearvars -except input_dir varargin; clc;
    end

    %% 解析参数
    p = inputParser;
    addParameter(p, 'parallel', true, @islogical);
    addParameter(p, 'force', false, @islogical);
    parse(p, varargin{:});
    use_parallel = p.Results.parallel;
    force = p.Results.force;

    %% 添加路径
    script_path = fileparts(mfilename('fullpath'));
    root_path = fileparts(script_path);
    addpath(fullfile(root_path, 'utils'));
    addpath(fullfile(root_path, 'utils', 'features'));

    %% 检查并行工具箱
    if use_parallel
        has_parallel = license('test', 'Distrib_Computing_Toolbox') && ...
                       ~isempty(ver('parallel'));
        if ~has_parallel
            warning('未检测到Parallel Computing Toolbox，回退到串行模式');
            use_parallel = false;
        end
    end

    %% 确定要处理的目录列表
    if nargin < 1 || isempty(input_dir)
        output_root = fullfile(root_path, 'output');
        date_dirs = dir(output_root);
        date_dirs = date_dirs([date_dirs.isdir]);
        date_dirs = date_dirs(~ismember({date_dirs.name}, {'.', '..'}));
        if isempty(date_dirs)
            error('未找到输出目录');
        end
        [~, idx] = sort([date_dirs.datenum], 'descend');
        input_dir = fullfile(output_root, date_dirs(idx(1)).name);
    end

    target_dirs = find_target_dirs(input_dir);

    if isempty(target_dirs)
        error('未找到包含时域数据文件的目录: %s', input_dir);
    end

    fprintf('========================================\n');
    fprintf('从已有时域数据生成特征\n');
    fprintf('共找到 %d 个数据目录\n', length(target_dirs));
    if use_parallel
        fprintf('并行模式: 开启\n');
    else
        fprintf('并行模式: 关闭\n');
    end
    fprintf('========================================\n\n');

    %% 获取采样频率
    cfg = config();
    fs = cfg.signal.fs;

    %% 逐个处理每个目录
    for d = 1:length(target_dirs)
        process_directory(target_dirs{d}, fs, use_parallel, root_path);
    end

    fprintf('\n========================================\n');
    fprintf('全部处理完成! 共处理 %d 个目录\n', length(target_dirs));
    fprintf('========================================\n');
end

%% ==========================================================
%% find_target_dirs - 递归查找包含 *echo_times.mat 的目录
%% ==========================================================
function target_dirs = find_target_dirs(root_dir)
    target_dirs = {};

    if has_times_file(root_dir)
        target_dirs{end+1} = root_dir;
        return;
    end

    subdirs = dir(fullfile(root_dir, 'JNR_*'));
    subdirs = subdirs([subdirs.isdir]);

    for i = 1:length(subdirs)
        jnr_dir = fullfile(root_dir, subdirs(i).name);
        if has_times_file(jnr_dir)
            target_dirs{end+1} = jnr_dir;
        end
    end

    if isempty(target_dirs)
        all_sub = dir(root_dir);
        all_sub = all_sub([all_sub.isdir]);
        all_sub = all_sub(~ismember({all_sub.name}, {'.', '..'}));
        for i = 1:length(all_sub)
            sub = fullfile(root_dir, all_sub(i).name);
            found = find_target_dirs(sub);
            for j = 1:length(found)
                target_dirs{end+1} = found{j};
            end
        end
    end
end

%% ==========================================================
%% has_times_file - 检查目录是否包含时域数据
%% ==========================================================
function flag = has_times_file(dir_path)
    f = dir(fullfile(dir_path, '*_echo_times.mat'));
    flag = ~isempty(f);
end

%% ==========================================================
%% process_directory - 处理单个数据目录
%% ==========================================================
function process_directory(dir_path, fs, use_parallel, root_path)
    fprintf('\n--- 处理目录: %s ---\n', dir_path);

    times_files = dir(fullfile(dir_path, '*_echo_times.mat'));
    if isempty(times_files)
        fprintf('  跳过: 未找到时域数据\n');
        return;
    end

    % 逐个处理每个数据集
    for t = 1:length(times_files)
        name_parts = strsplit(times_files(t).name, '_echo_times.mat');
        dataset_type = name_parts{1};
        features_path = fullfile(dir_path, sprintf('%s_echo_features.json', dataset_type));

        % 跳过已存在的特征文件
        if exist(features_path, 'file')
            fprintf('  跳过: %s (特征已存在)\n', dataset_type);
            continue;
        end

        % 加载数据
        times_path = fullfile(dir_path, times_files(t).name);
        fprintf('  数据集: %s\n', dataset_type);
        fprintf('  加载时域数据...');
        load(times_path, 'all_times');
        [SAMPLE_NUM, ~] = size(all_times);
        fprintf(' [%d x %d]\n', SAMPLE_NUM, size(all_times, 2));

        % 提取特征
        fprintf('  提取特征...\n');
        feature_cell = cell(SAMPLE_NUM, 1);
        tic;

        features_dir = fullfile(root_path, 'utils', 'features');
        if use_parallel && SAMPLE_NUM >= 50
            parfor i = 1:SAMPLE_NUM
                addpath(features_dir);
                feature_cell{i} = extract_signal_features(all_times(i, :), fs);
            end
            fprintf('  并行, 用时 %.1f秒\n', toc);
        else
            for i = 1:SAMPLE_NUM
                feature_cell{i} = extract_signal_features(all_times(i, :), fs);
                if mod(i, round(SAMPLE_NUM/10)) == 0
                    fprintf('    %d/%d (%d%%)\n', i, SAMPLE_NUM, round(i/SAMPLE_NUM*100));
                end
            end
            fprintf('  完成, 用时 %.1f秒\n', toc);
        end

        % cell -> struct array
        all_features = feature_cell{1};
        for i = 2:SAMPLE_NUM
            all_features(i) = feature_cell{i};
        end

        % 保存
        fprintf('  保存特征...');
        jsonStr = jsonencode(all_features);
        fid = fopen(features_path, 'w', 'n', 'UTF-8');
        fprintf(fid, '%s', jsonStr);
        fclose(fid);
        fprintf(' 已保存: %s\n', features_path);
    end
end
