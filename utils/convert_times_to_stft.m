% ==========================================================
% convert_times_to_stft.m - 从已有时域数据生成STFT和持续时间谱
%
% 使用:
%   convert_times_to_stft                                    % 自动找最新output, 处理所有JNR
%   convert_times_to_stft('C:\output\output\fine_more')       % 指定父目录, 扫描JNR_*子文件夹
%   convert_times_to_stft('C:\output\output\fine_more\JNR_+0') % 单个JNR目录
%   convert_times_to_stft('mydir', 'compute_persistence', true) % 同时生成persistence
%   convert_times_to_stft('mydir', 'Nwin', 256, 'Nfft', 512)   % 自定义STFT参数
%   convert_times_to_stft('mydir', 'Noverlap', 200)             % 自定义重叠长度
%   convert_times_to_stft('mydir', 'force', true)               % 覆盖已有文件
%   convert_times_to_stft('mydir', 'compute_persistence', true, 'num_power_bins', 128)
% ==========================================================

function convert_times_to_stft(varargin)
    p = inputParser;
    p.addOptional('target_dir', '', @ischar);
    p.addParameter('Nwin', 128, @isnumeric);
    p.addParameter('Noverlap', 93, @isnumeric);
    p.addParameter('Nfft', 224, @isnumeric);
    p.addParameter('fs', 80e6, @isnumeric);
    p.addParameter('compute_persistence', false, @islogical);
    p.addParameter('num_power_bins', 224, @isnumeric);
    p.addParameter('method', 'custom', @(s) ischar(s) || isstring(s));
    p.addParameter('power_percentile_lo', 1, @isnumeric);
    p.addParameter('power_margin_db', 3, @isnumeric);
    p.addParameter('force', false, @islogical);
    p.parse(varargin{:});

    target_dir = p.Results.target_dir;
    Nwin = p.Results.Nwin;
    Noverlap = p.Results.Noverlap;
    Nfft = p.Results.Nfft;
    fs = p.Results.fs;
    compute_persistence = p.Results.compute_persistence;
    num_power_bins = p.Results.num_power_bins;
    pers_method = lower(char(p.Results.method));
    pct_lo = p.Results.power_percentile_lo;
    margin = p.Results.power_margin_db;
    force = p.Results.force;

    script_path = fileparts(mfilename('fullpath'));
    root_path = fileparts(script_path);
    addpath(fullfile(root_path, 'utils'));

    % ========================================================
    % 1. 解析目标: 收集所有 (目录, times路径, stft路径, persist路径) 元组
    % ========================================================
    tasks = {};  % {dir_path, times_path, stft_path, persist_path}

    if isempty(target_dir)
        % 自动查找最新output → 取所有JNR子目录
        output_base = fullfile(root_path, 'output');
        dirs = dir(output_base);
        dirs = dirs([dirs.isdir] & ~ismember({dirs.name}, {'.', '..'}));
        if isempty(dirs), error('output目录下未找到子目录'); end
        [~, idx] = sort({dirs.date}, 'descend');
        for k = 1:length(idx)
            candidate = fullfile(output_base, dirs(idx(k)).name);
            jnr_dirs = dir(fullfile(candidate, 'JNR_*'));
            if ~isempty(jnr_dirs)
                parent_dir = candidate;
                fprintf('自动选择: %s (%d 个JNR子目录)\n', parent_dir, length(jnr_dirs));
                break;
            end
        end
        if ~exist('parent_dir', 'var'), error('未找到包含JNR_*的输出目录'); end
    else
        parent_dir = target_dir;
    end

    % 检测子目录
    jnr_subdirs = dir(fullfile(parent_dir, 'JNR_*'));
    has_jnr_subdirs = ~isempty(jnr_subdirs);

    % 检测直接times文件
    direct_times = dir(fullfile(parent_dir, '*_echo_times.mat'));
    has_direct_times = ~isempty(direct_times);

    if has_jnr_subdirs
        % 父目录模式: 扫描所有JNR_*子文件夹
        for d = 1:length(jnr_subdirs)
            jnr_dir = fullfile(parent_dir, jnr_subdirs(d).name);
            times_files = dir(fullfile(jnr_dir, '*_echo_times.mat'));
            for f = 1:length(times_files)
                times_path = fullfile(jnr_dir, times_files(f).name);
                [~, times_name] = fileparts(times_files(f).name);
                stft_name = strrep(times_name, '_times', '_stfts');
                stft_path = fullfile(jnr_dir, [stft_name, '.mat']);
                persist_name = strrep(times_name, '_times', '_persistences');
                persist_path = fullfile(jnr_dir, [persist_name, '.mat']);
                tasks = [tasks; {jnr_dir, times_path, stft_path, persist_path}]; %#ok<AGROW>
            end
        end
    elseif has_direct_times
        % 直接times文件模式: 单目录
        for f = 1:length(direct_times)
            times_path = fullfile(parent_dir, direct_times(f).name);
            [~, times_name] = fileparts(direct_times(f).name);
            stft_name = strrep(times_name, '_times', '_stfts');
            stft_path = fullfile(parent_dir, [stft_name, '.mat']);
            persist_name = strrep(times_name, '_times', '_persistences');
            persist_path = fullfile(parent_dir, [persist_name, '.mat']);
            tasks = [tasks; {parent_dir, times_path, stft_path, persist_path}]; %#ok<AGROW>
        end
    else
        error('在 %s 中未找到 JNR_* 子目录或 *_echo_times.mat 文件', parent_dir);
    end

    fprintf('\n========== 转换任务: %d 个文件 ==========\n', size(tasks, 1));
    fprintf('STFT参数: Nwin=%d, Noverlap=%d, Nfft=%d, fs=%.0f MHz\n', ...
        Nwin, Noverlap, Nfft, fs/1e6);
    if compute_persistence
        fprintf('Persistence: 启用 (num_power_bins=%d)\n', num_power_bins);
    end
    fprintf('覆盖模式: %s\n', string(force));

    % ========================================================
    % 2. 逐任务处理
    % ========================================================
    for t = 1:size(tasks, 1)
        dir_path = tasks{t, 1};
        times_path = tasks{t, 2};
        stft_path = tasks{t, 3};
        persist_path = tasks{t, 4};

        fprintf('\n--- [%d/%d] %s ---\n', t, size(tasks, 1), dir_path);

        % ---- 2a. 跳过检查 ----
        stft_exists = exist(stft_path, 'file');
        persist_exists = exist(persist_path, 'file');

        if stft_exists && ~force && (~compute_persistence || persist_exists)
            fprintf('  跳过 (已存在, force=true覆盖): %s\n', stft_path);
            continue;
        end

        % ---- 2b. 加载时域数据 ----
        try
            times_data = load(times_path, 'all_times');
        catch ME
            warning('加载失败 %s: %s. 跳过.', times_path, ME.message);
            continue;
        end

        if ~isfield(times_data, 'all_times')
            warning('文件 %s 不包含 all_times 变量, 跳过.', times_path);
            continue;
        end

        all_times = times_data.all_times;
        [SAMPLE_NUM, N_total] = size(all_times);
        fprintf('  加载: all_times [%d × %d] %s\n', SAMPLE_NUM, N_total, class(all_times));

        % 验证信号长度
        if N_total < Nwin
            error('信号长度 (%d) 小于STFT窗口长度 (%d), 无法计算STFT', N_total, Nwin);
        end

        % ---- 2c. STFT计算 ----
        Step = Nwin - Noverlap;
        N_cols = floor((N_total - Noverlap) / Step);
        est_mem = SAMPLE_NUM * Nfft * N_cols * 8 / 1e6;  % complex single = 8 bytes
        fprintf('  STFT: Nwin=%d, Noverlap=%d, Nfft=%d, Step=%d, N_cols=%d\n', ...
            Nwin, Noverlap, Nfft, Step, N_cols);
        fprintf('  预估STFT内存: %.0f MB\n', est_mem);

        if ~stft_exists || force
            t_start = tic;
            win = hamming(Nwin);
            all_stfts = zeros(SAMPLE_NUM, Nfft, N_cols);
            for i = 1:SAMPLE_NUM
                [S, F, T] = spectrogram(all_times(i, 1:N_total), win, Noverlap, Nfft, fs, 'centered');
                all_stfts(i, :, :) = S;
                if mod(i, 500) == 0 || i == SAMPLE_NUM
                    fprintf('    STFT: %d/%d (%.0fs)\n', i, SAMPLE_NUM, toc(t_start));
                end
            end
            fprintf('  STFT完成: %.1fs (%d样本)\n', toc(t_start), SAMPLE_NUM);

            % 保存STFT (single精度, v7.3格式)
            all_stfts = single(all_stfts);
            save(stft_path, 'all_stfts', 'F', 'T', 'Nwin', 'Noverlap', 'Nfft', 'fs', '-v7.3', '-nocompression');
            info = dir(stft_path);
            fprintf('  已保存: %s (%.1f MB)\n', stft_path, info.bytes / 1e6);
        else
            % STFT已存在, 但可能需要persistence → 加载已有STFT
            fprintf('  STFT已存在, 加载用于persistence计算...\n');
            stft_data = load(stft_path, 'all_stfts');
            all_stfts = stft_data.all_stfts;
            [SAMPLE_NUM, Nfft, N_cols] = size(all_stfts);
            fprintf('  加载: all_stfts [%d × %d × %d]\n', SAMPLE_NUM, Nfft, N_cols);
            % 重建频率轴 (如果文件中没有F)
            if ~exist('F', 'var')
                F = (-Nfft/2 : Nfft/2-1)' * (fs / Nfft);
            end
        end

        % ---- 2d. 可选Persistence计算 ----
        if compute_persistence
            if persist_exists && ~force
                fprintf('  跳过 (persistence已存在): %s\n', persist_path);
                continue;
            end

            t_pers = tic;
            all_persistences = zeros(SAMPLE_NUM, Nfft, num_power_bins, 'single');
            all_power_centers = [];
            persistence_method = pers_method; %#ok<NASGU>

            if strcmp(pers_method, 'matlab')
                fprintf('  模式: matlab (每样本独立功率轴, 时间窗百分比)\n');
                all_power_centers = zeros(SAMPLE_NUM, num_power_bins, 'single');
                for i = 1:SAMPLE_NUM
                    [all_persistences(i, :, :), ~, pc] = compute_duration_spectrum( ...
                        squeeze(all_stfts(i, :, :)), num_power_bins, [], 'matlab');
                    all_power_centers(i, :) = pc;
                    if mod(i, 500) == 0
                        fprintf('    Persistence: %d/%d (%.0fs)\n', i, SAMPLE_NUM, toc(t_pers));
                    end
                end
                power_centers = all_power_centers(1, :);
            else
                pow_db1 = 10 * log10(abs(squeeze(all_stfts(1, :, :))).^2 + eps);
                pwr_lo = prctile(pow_db1(:), pct_lo);
                pwr_hi = max(pow_db1(:));
                global_pwr_range = [pwr_lo - margin, pwr_hi + margin];
                fprintf('  模式: custom | 功率范围 [%.1f, %.1f] dB\n', ...
                    global_pwr_range(1), global_pwr_range(2));
                for i = 1:SAMPLE_NUM
                    [all_persistences(i, :, :), ~, power_centers] = compute_duration_spectrum( ...
                        squeeze(all_stfts(i, :, :)), num_power_bins, global_pwr_range, 'custom');
                    if mod(i, 500) == 0
                        fprintf('    Persistence: %d/%d (%.0fs)\n', i, SAMPLE_NUM, toc(t_pers));
                    end
                end
            end
            fprintf('  Persistence完成: %.1fs (%d样本)\n', toc(t_pers), SAMPLE_NUM);

            % 保存Persistence
            if ~isempty(all_power_centers)
                save(persist_path, 'all_persistences', 'num_power_bins', 'power_centers', ...
                    'all_power_centers', 'persistence_method', 'F', '-v7.3');
            else
                save(persist_path, 'all_persistences', 'num_power_bins', 'power_centers', ...
                    'persistence_method', 'F', '-v7.3');
            end
            info = dir(persist_path);
            fprintf('  已保存: %s (%.1f MB)\n', persist_path, info.bytes / 1e6);
        end
    end

    fprintf('\n========== 全部完成: %d 个文件 ==========\n', size(tasks, 1));
end
