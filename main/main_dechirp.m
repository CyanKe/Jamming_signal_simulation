% main_dechirp.m - 对已有时域数据进行去斜处理并生成STFT
% ==========================================================
% 读取已生成的 all_times.mat，执行去斜变换，计算STFT并保存
%
% 用法:
%   main_dechirp                         - 自动查找最新目录
%   main_dechirp('output/20us_multi')    - 指定目录
%   main_dechirp force                   - 强制覆盖已有文件
%   main_dechirp('output/20us_few', 'force')
%
% 输出:
%   在原目录下生成 *_echo_dechirp_stfts.mat

function main_dechirp(input_dir, options)
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
            jnr = dir(fullfile(output_root, dirs(i).name, 'JNR_*'));
            jnr = jnr([jnr.isdir]);
            fprintf('  [%d] %s (%d个JNR子目录)\n', i, dirs(i).name, length(jnr));
        end

        idx = input('请选择目录编号: ');
        if idx < 1 || idx > length(dirs)
            [~, sort_idx] = sort([dirs.datenum], 'descend');
            idx = sort_idx(1);
            fprintf('使用最新目录: %s\n', dirs(idx).name);
        end

        input_dir = fullfile(output_root, dirs(idx).name);
    end

    % 开始去斜处理
    fprintf('\n========================================\n');
    fprintf('去斜处理\n');
    fprintf('目标目录: %s\n', input_dir);
    if use_force
        fprintf('模式: 强制覆盖\n');
    end
    fprintf('========================================\n\n');

    % 查找所有JNR子目录
    jnr_dirs = dir(fullfile(input_dir, 'JNR_*'));
    jnr_dirs = jnr_dirs([jnr_dirs.isdir]);

    if isempty(jnr_dirs)
        error('未找到JNR_*子目录，请确认目录结构');
    end

    % 加载配置获取去斜参数
    cfg = config();
    fs = cfg.signal.fs;
    B = cfg.signal.B;
    taup = cfg.signal.taup;
    k = B / taup;

    % STFT参数
    Nwin = cfg.stft.Nwin;
    Noverlap = cfg.stft.Noverlap;
    Nfft = cfg.stft.Nfft;
    Step = Nwin - Noverlap;

    fprintf('去斜参数:\n');
    fprintf('  采样率 fs = %.0f MHz\n', fs/1e6);
    fprintf('  带宽 B = %.0f MHz\n', B/1e6);
    fprintf('  脉宽 taup = %.0f us\n', taup/1e6);
    fprintf('  调频率 k = %.2e Hz/s\n\n', k);

    % 处理每个JNR目录
    for d = 1:length(jnr_dirs)
        jnr_path = fullfile(input_dir, jnr_dirs(d).name);
        times_file = fullfile(jnr_path, '*_echo_times.mat');
        stft_file = fullfile(jnr_path, '*_echo_dechirp_stfts.mat');

        fprintf('处理: %s\n', jnr_dirs(d).name);

        % 检查输出文件是否已存在
        existing_stft = dir(stft_file);
        if ~isempty(existing_stft) && ~use_force
            fprintf('  已存在，跳过 (使用force覆盖)\n');
            continue;
        end

        % 查找时域数据文件
        times_files = dir(times_file);
        if isempty(times_files)
            fprintf('  未找到 *_echo_times.mat，跳过\n');
            continue;
        end

        % 加载时域数据
        data = load(fullfile(jnr_path, times_files(1).name));
        if ~isfield(data, 'all_times')
            fprintf('  文件中无 all_times 变量，跳过\n');
            continue;
        end

        all_times = data.all_times;
        [num_samples, N] = size(all_times);
        fprintf('  样本数: %d, 点数: %d\n', num_samples, N);

        % 生成去斜参考信号
        t = (0:N-1)' / fs;
        dechirp_ref = exp(1j * pi * k * t.^2);

        % 去斜处理
        tic;
        all_times_dechirp = all_times .* dechirp_ref';
        elapsed_dechirp = toc;
        fprintf('  去斜耗时: %.2f s\n', elapsed_dechirp);

        % 计算STFT
        N_cols = floor((N - Noverlap) / Step);
        all_stfts = zeros(num_samples, Nfft, N_cols);

        tic;
        for i = 1:num_samples
            [S, ~, ~] = spectrogram(all_times_dechirp(i, :), Nwin, Noverlap, Nfft, fs, 'centered');
            all_stfts(i, :, :) = S;
        end
        elapsed_stft = toc;
        fprintf('  STFT耗时: %.2f s\n', elapsed_stft);

        % 保存STFT数据
        all_stfts = single(all_stfts);
        output_file = fullfile(jnr_path, [cfg.output.dataset_type '_echo_dechirp_stfts.mat']);
        save(output_file, 'all_stfts', '-v7.3');
        fprintf('  已保存: %s\n\n', output_file);

    fprintf('去斜处理完成!\n');  
    end
end