% main_feature_extract.m - 从已有时域数据生成特征（主入口）
% ==========================================================
% 读取已生成的 all_times.mat，提取多域特征并保存为JSON
% 支持并行处理（需Parallel Computing Toolbox）
%
% 用法:
%   main_feature_extract                    - 自动查找最新目录
%   main_feature_extract('output/20us_multi') - 指定目录
%   main_feature_extract force               - 强制重新生成
%   main_feature_extract('output/20us_multi', force)

function main_feature_extract(input_dir, options)
    if nargin == 0 && nargout == 0
        clear; clc; close all;
        input_dir = '';
        options = '';
    elseif nargin == 0
        input_dir = '';
        options = '';
    end

    % 添加路径
    script_path = fileparts(mfilename('fullpath'));
    root_path = fileparts(script_path);
    addpath(root_path);
    addpath(fullfile(root_path, 'utils'));
    addpath(fullfile(root_path, 'utils', 'features'));

    % 解析参数
    use_force = false;
    if nargin >= 2
        if ischar(options) && strcmpi(options, 'force')
            use_force = true;
        end
    end
    if isempty(input_dir)
        input_dir = '';
    end

    % 如果未指定目录，显示可选目录列表
    if isempty(input_dir)
        output_root = fullfile(root_path, 'output');
        dirs = dir(output_root);
        dirs = dirs([dirs.isdir]);
        dirs = dirs(~ismember({dirs.name}, {'.', '..'}));

        if isempty(dirs)
            error('output目录下未找到任何数据目录');
        end

        fprintf('可选的数据目录:\n');
        for i = 1:length(dirs)
            % 统计子目录数
            jnr = dir(fullfile(output_root, dirs(i).name, 'JNR_*'));
            jnr = jnr([jnr.isdir]);
            fprintf('  [%d] %s (%d个JNR子目录)\n', i, dirs(i).name, length(jnr));
        end

        idx = input('请选择目录编号: ');
        if idx < 1 || idx > length(dirs)
            % 默认选最新的
            [~, sort_idx] = sort([dirs.datenum], 'descend');
            idx = sort_idx(1);
            fprintf('使用最新目录: %s\n', dirs(idx).name);
        end

        input_dir = fullfile(output_root, dirs(idx).name);
    end

    % 开始特征提取
    fprintf('\n========================================\n');
    fprintf('特征提取入口\n');
    fprintf('目标目录: %s\n', input_dir);
    if use_force
        fprintf('模式: 强制重新生成\n');
    end
    fprintf('========================================\n\n');

    if use_force
        generate_features_from_times(input_dir, 'force', true);
    else
        generate_features_from_times(input_dir);
    end
end