% ==========================================================
% convert_stft_to_persistence.m - 从已有STFT .mat 生成持续时间谱
%
% 使用:
%   convert_stft_to_persistence                           % 自动找最新output, 处理所有JNR
%   convert_stft_to_persistence('output/2D_8x9_0520')        % 扫描JNR_*子文件夹, 全部转换
%   convert_stft_to_persistence('output/pspectrum/JNR_+10') % 单个JNR目录
%   convert_stft_to_persistence(..., 'num_power_bins', 224) % 指定功率分箱
%   convert_stft_to_persistence(..., 'method', 'matlab')    % 'custom'|'matlab'
%   convert_stft_to_persistence(..., 'force', true)        % 覆盖已有文件
%   convert_stft_to_persistence('output/2D_8x9_0520','num_power_bins', 224,'force',true) 
% ==========================================================

function convert_stft_to_persistence(varargin)
    p = inputParser;
    p.addOptional('target_dir', '', @ischar);
    p.addParameter('num_power_bins', 224, @isnumeric);
    p.addParameter('method', 'custom', @(s) ischar(s) || isstring(s));
    p.addParameter('power_percentile_lo', 1, @isnumeric);
    p.addParameter('power_margin_db', 3, @isnumeric);
    p.addParameter('force', false, @islogical);
    p.parse(varargin{:});

    target_dir = p.Results.target_dir;
    num_power_bins = p.Results.num_power_bins;
    pers_method = lower(char(p.Results.method));
    pct_lo = p.Results.power_percentile_lo;
    margin = p.Results.power_margin_db;
    force = p.Results.force;

    script_path = fileparts(mfilename('fullpath'));
    root_path = fileparts(script_path);
    addpath(fullfile(root_path, 'utils'));

    % ========================================================
    % 1. 解析目标: 收集所有 (JNR目录, STFT路径) 对
    % ========================================================
    tasks = {};  % {jnr_dir, stft_path, persist_path}

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
        % 父目录模式: 扫描所有JNR_*子文件夹
        for d = 1:length(jnr_subdirs)
            jnr_dir = fullfile(parent_dir, jnr_subdirs(d).name);
            stft_files = dir(fullfile(jnr_dir, '*_echo_stfts.mat'));
            for f = 1:length(stft_files)
                stft_path = fullfile(jnr_dir, stft_files(f).name);
                [~, stft_name] = fileparts(stft_files(f).name);
                persist_name = strrep(stft_name, '_stfts', '_persistences');
                persist_path = fullfile(jnr_dir, [persist_name, '.mat']);
                tasks = [tasks; {jnr_dir, stft_path, persist_path}]; %#ok<AGROW>
            end
        end
    elseif has_direct_stfts
        % 直接STFT文件模式: 单目录
        for f = 1:length(direct_stfts)
            stft_path = fullfile(parent_dir, direct_stfts(f).name);
            [~, stft_name] = fileparts(direct_stfts(f).name);
            persist_name = strrep(stft_name, '_stfts', '_persistences');
            persist_path = fullfile(parent_dir, [persist_name, '.mat']);
            tasks = [tasks; {parent_dir, stft_path, persist_path}]; %#ok<AGROW>
        end
    else
        error('在 %s 中未找到 JNR_* 子目录或 *_echo_stfts.mat 文件', parent_dir);
    end

    fprintf('\n========== 转换任务: %d 个文件 ==========\n', size(tasks, 1));

    % ========================================================
    % 2. 逐任务处理
    % ========================================================
    for t = 1:size(tasks, 1)
        jnr_dir = tasks{t, 1};
        stft_path = tasks{t, 2};
        persist_path = tasks{t, 3};

        fprintf('\n--- [%d/%d] %s ---\n', t, size(tasks, 1), jnr_dir);

        if exist(persist_path, 'file') && ~force
            fprintf('  跳过 (已存在, force=true覆盖): %s\n', persist_path);
            continue;
        end

        % 加载STFT
        stft_data = load(stft_path, 'all_stfts');
        all_stfts = stft_data.all_stfts;
        [SAMPLE_NUM, Nfft, N_cols] = size(all_stfts);
        fprintf('  STFT: %d × %d × %d\n', SAMPLE_NUM, Nfft, N_cols);

        % 重建频率轴
        fs = 80e6;
        F = (-Nfft/2 : Nfft/2-1)' * (fs / Nfft);

        % 计算持续时间谱
        t_start = tic;
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
                    fprintf('    %d/%d (%.0fs)\n', i, SAMPLE_NUM, toc(t_start));
                end
            end
            power_centers = all_power_centers(1, :);
        else
            pow_db1 = 10 * log10(abs(squeeze(all_stfts(1, :, :))).^2 + eps);
            pwr_lo = prctile(pow_db1(:), pct_lo);
            pwr_hi = max(pow_db1(:));
            global_pwr_range = [pwr_lo - margin, pwr_hi + margin];
            fprintf('  模式: custom | 全局功率范围 [%.1f, %.1f] dB\n', ...
                global_pwr_range(1), global_pwr_range(2));
            for i = 1:SAMPLE_NUM
                [all_persistences(i, :, :), ~, power_centers] = compute_duration_spectrum( ...
                    squeeze(all_stfts(i, :, :)), num_power_bins, global_pwr_range, 'custom');
                if mod(i, 500) == 0
                    fprintf('    %d/%d (%.0fs)\n', i, SAMPLE_NUM, toc(t_start));
                end
            end
        end
        fprintf('  耗时: %.1fs (%d样本)\n', toc(t_start), SAMPLE_NUM);

        % 保存
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

    fprintf('\n========== 全部完成: %d 个文件 ==========\n', size(tasks, 1));
end
