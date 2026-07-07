% ==========================================================
% convert_stft_to_rgb.m - 从已有STFT .mat 生成多colormap RGB数据
%
% 参照 convert_stft_to_persistence.m 的扫描-处理模式。
% 对已生成的 *_echo_stfts.mat 文件批量生成 RGB colormap 变体,
% 无需重新运行完整生成管道。
%
% 使用:
%   convert_stft_to_rgb                                    % 自动找最新output, 默认5种colormap
%   convert_stft_to_rgb('output/20us_multi')                % 指定目录, 扫描JNR_*子文件夹
%   convert_stft_to_rgb('output/20us_multi/JNR_+10')        % 单个JNR目录
%   convert_stft_to_rgb(..., 'colormaps', {'jet','hot'})    % 自定义colormap列表
%   convert_stft_to_rgb(..., 'force', true)                 % 强制覆盖已有文件
%   convert_stft_to_rgb(..., 'percentile_range', [2, 98])   % 自定义百分位裁剪
%   convert_stft_to_rgb(..., 'normalization', 'linear')      % 线性幅度归一化 (默认'dB')
% ==========================================================

function convert_stft_to_rgb(varargin)
    p = inputParser;
    p.addOptional('target_dir', '', @ischar);
    p.addParameter('colormaps', {'parula', 'jet', 'turbo', 'hot', 'gray'}, @iscell);
    p.addParameter('percentile_range', [0, 100], @(x) isnumeric(x) && numel(x) == 2);
    p.addParameter('normalization', 'dB', @(c) ischar(c) && ismember(lower(c), {'db', 'linear'}));
    p.addParameter('force', false, @islogical);
    p.parse(varargin{:});

    target_dir = p.Results.target_dir;
    cmaps = p.Results.colormaps;
    percentile_range = p.Results.percentile_range;
    normalization = lower(p.Results.normalization);
    force = p.Results.force;

    script_path = fileparts(mfilename('fullpath'));
    root_path = fileparts(script_path);
    addpath(fullfile(root_path, 'utils'));

    % ========================================================
    % 1. 解析目标: 收集所有 (JNR目录, STFT路径) 对
    % ========================================================
    tasks = {};  % {jnr_dir, stft_path, rgb_path}

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

    % 检测直接STFT文件
    direct_stfts = dir(fullfile(parent_dir, '*_echo_stfts.mat'));
    has_direct_stfts = ~isempty(direct_stfts);

    if has_jnr_subdirs
        for d = 1:length(jnr_subdirs)
            jnr_dir = fullfile(parent_dir, jnr_subdirs(d).name);
            stft_files = dir(fullfile(jnr_dir, '*_echo_stfts.mat'));
            for f = 1:length(stft_files)
                stft_path = fullfile(jnr_dir, stft_files(f).name);
                [~, stft_name] = fileparts(stft_files(f).name);
                rgb_name = strrep(stft_name, '_stfts', '_stfts_rgb');
                rgb_path = fullfile(jnr_dir, [rgb_name, '.mat']);
                tasks = [tasks; {jnr_dir, stft_path, rgb_path}]; %#ok<AGROW>
            end
        end
    elseif has_direct_stfts
        for f = 1:length(direct_stfts)
            stft_path = fullfile(parent_dir, direct_stfts(f).name);
            [~, stft_name] = fileparts(direct_stfts(f).name);
            rgb_name = strrep(stft_name, '_stfts', '_stfts_rgb');
            rgb_path = fullfile(parent_dir, [rgb_name, '.mat']);
            tasks = [tasks; {parent_dir, stft_path, rgb_path}]; %#ok<AGROW>
        end
    else
        error('在 %s 中未找到 JNR_* 子目录或 *_echo_stfts.mat 文件', parent_dir);
    end

    % 空任务诊断: 目录存在但没有STFT文件
    if isempty(tasks)
        fprintf('\n========== 错误: 未找到任何 *_echo_stfts.mat 文件 ==========\n');
        fprintf('搜索目录: %s\n', parent_dir);

        % 检测是否有 *_echo_times.mat (时域数据), 给出针对性建议
        has_times = false;
        if has_jnr_subdirs
            for d = 1:min(3, length(jnr_subdirs))
                jnr_dir = fullfile(parent_dir, jnr_subdirs(d).name);
                if ~isempty(dir(fullfile(jnr_dir, '*_echo_times.mat')))
                    has_times = true;
                    fprintf('  发现时域数据: %s\n', jnr_dir);
                end
            end
        else
            has_times = ~isempty(dir(fullfile(parent_dir, '*_echo_times.mat')));
        end

        if has_times
            fprintf('\n原因: 数据生成时 cfg.output.save_stft = false, 未保存STFT。\n');
            fprintf('请先运行 convert_times_to_stft 从时域数据生成STFT:\n');
            fprintf('  convert_times_to_stft(''%s'')\n', parent_dir);
        else
            fprintf('\n原因: 未找到 *_echo_stfts.mat 文件。\n');
            fprintf('请确保:\n');
            fprintf('  1. 数据生成时 cfg.output.save_stft = true\n');
            fprintf('  2. 或先运行 convert_times_to_stft 从时域数据生成STFT\n');
        end
        error('无法继续: 需要 *_echo_stfts.mat 文件作为输入。');
    end

    fprintf('\n========== RGB转换任务: %d 个文件, %d 种colormap ==========\n', ...
            size(tasks, 1), length(cmaps));
    fprintf('Colormaps: %s\n', strjoin(cmaps, ', '));

    % ========================================================
    % 2. 逐任务处理
    % ========================================================
    for t = 1:size(tasks, 1)
        jnr_dir = tasks{t, 1};
        stft_path = tasks{t, 2};
        rgb_path = tasks{t, 3};

        fprintf('\n--- [%d/%d] %s ---\n', t, size(tasks, 1), jnr_dir);

        if exist(rgb_path, 'file') && ~force
            fprintf('  跳过 (已存在, force=true覆盖): %s\n', rgb_path);
            continue;
        end

        % 加载STFT
        stft_data = load(stft_path, 'all_stfts');
        all_stfts = stft_data.all_stfts;
        [SAMPLE_NUM, Nfft, N_cols] = size(all_stfts);
        fprintf('  STFT: %d x %d x %d\n', SAMPLE_NUM, Nfft, N_cols);

        % 计算全局归一化参数 (基于子集以加速)
        sample_size = min(50, SAMPLE_NUM);
        sample_indices = randperm(SAMPLE_NUM, sample_size);
        sample_abs = abs(all_stfts(sample_indices, :, :));
        switch normalization
            case 'db'
                sample_mag = 20 * log10(sample_abs + eps);
            case 'linear'
                sample_mag = sample_abs;
        end
        lo = prctile(sample_mag(:), percentile_range(1));
        hi = prctile(sample_mag(:), percentile_range(2));
        fprintf('  %s归一化范围: [%.1f, %.1f] (百分位 [%d, %d])\n', ...
                upper(normalization), lo, hi, percentile_range(1), percentile_range(2));

        norm_params.lo = lo;
        norm_params.hi = hi;

        % 逐 colormap 生成
        t_start = tic;
        num_cmaps = length(cmaps);
        for c = 1:num_cmaps
            cmap_name = cmaps{c};
            t_cmap = tic;
            rgb_data = zeros(SAMPLE_NUM, Nfft, N_cols, 3, 'uint8');
            for i = 1:SAMPLE_NUM
                rgb_data(i, :, :, :) = apply_colormap_to_stft( ...
                    squeeze(all_stfts(i, :, :)), cmap_name, norm_params, normalization);
                if mod(i, 500) == 0
                    fprintf('    [%s] %d/%d (%.0fs)\n', cmap_name, i, SAMPLE_NUM, toc(t_start));
                end
            end
            varname = ['rgb_', cmap_name];
            eval([varname ' = rgb_data;']);
            fprintf('  [%d/%d] %s: %dx%dx%d, 耗时 %.1fs\n', ...
                    c, num_cmaps, cmap_name, Nfft, N_cols, 3, toc(t_cmap));
        end
        fprintf('  总耗时: %.1fs (%d样本 x %d colormaps)\n', toc(t_start), SAMPLE_NUM, num_cmaps);

        % 重建频率/时间轴 (使用默认配置参数)
        fs = 80e6;
        Nwin = 128;
        Noverlap = 65;
        PRI = 100e-6;
        N_total = round(PRI * fs);
        Step = Nwin - Noverlap;
        F = (-Nfft/2 : Nfft/2-1)' * (fs / Nfft);
        dt = 1/fs;
        T = ((Nwin/2 : Step : Nwin/2 + (N_cols-1)*Step) - N_total/2) * dt;

        % 保存
        save_vars = {};
        for c = 1:num_cmaps
            save_vars{end+1} = ['rgb_', cmaps{c}]; %#ok<AGROW>
        end
        save_vars{end+1} = 'colormap_names';
        save_vars{end+1} = 'F';
        save_vars{end+1} = 'T';
        save_vars{end+1} = 'norm_params';
        colormap_names = cmaps; %#ok<NASGU>
        save(rgb_path, save_vars{:}, '-v7.3');
        info = dir(rgb_path);
        fprintf('  已保存: %s (%.1f MB)\n', rgb_path, info.bytes / 1e6);
    end

    fprintf('\n========== 全部完成: %d 个文件 ==========\n', size(tasks, 1));
end
