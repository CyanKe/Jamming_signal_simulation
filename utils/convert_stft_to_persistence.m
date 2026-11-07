% ==========================================================
% convert_stft_to_persistence.m - 从已有STFT .mat 生成持续时间谱
%
% 使用:
%   convert_stft_to_persistence                           % 自动找最新output, 处理所有JNR
%   convert_stft_to_persistence('output/2D_8x9_0520')        % 扫描JNR_*子文件夹, 全部转换
%   convert_stft_to_persistence('output/pspectrum/JNR_+10') % 单个JNR目录
%   convert_stft_to_persistence(..., 'num_power_bins', 224) % 单通道功率分箱
%   convert_stft_to_persistence(..., 'channel_power_bins', [224 112 32]) % 多通道
%   convert_stft_to_persistence(..., 'target_size', [224 224])           % resize 到 HxW
%   convert_stft_to_persistence(..., 'method', 'matlab')    % 'custom'|'matlab'
%   convert_stft_to_persistence(..., 'power_range_mode', 'fixed', 'power_range_db', [0 70])
%   convert_stft_to_persistence(..., 'force', true)        % 覆盖已有文件
%   convert_stft_to_persistence('output/2D_8x9_0520', ...
%       'channel_power_bins',[224 112 32],'target_size',[224 224], ...
%       'power_range_mode','fixed','power_range_db',[0 70],'force',true)
% ==========================================================

function convert_stft_to_persistence(varargin)
    p = inputParser;
    p.addOptional('target_dir', '', @ischar);
    p.addParameter('num_power_bins', 224, @isnumeric);
    p.addParameter('channel_power_bins', [], @isnumeric);  % 空=用 num_power_bins
    p.addParameter('target_size', [224, 224], @(v) isnumeric(v) && (isempty(v) || numel(v)==2));
    p.addParameter('method', 'custom', @(s) ischar(s) || isstring(s));
    p.addParameter('power_range_mode', 'fixed', @(s) ischar(s) || isstring(s));
    p.addParameter('power_range_db', [0, 70], @(v) isnumeric(v) && numel(v) == 2);
    p.addParameter('power_percentile_lo', 1, @isnumeric);
    p.addParameter('power_margin_db', 3, @isnumeric);
    p.addParameter('force', false, @islogical);
    p.parse(varargin{:});

    target_dir = p.Results.target_dir;
    if isempty(p.Results.channel_power_bins)
        channel_power_bins = double(p.Results.num_power_bins(:).');
    else
        channel_power_bins = double(p.Results.channel_power_bins(:).');
    end
    num_power_bins = max(channel_power_bins); %#ok<NASGU>
    target_size = p.Results.target_size;
    if ~isempty(target_size)
        target_size = double(target_size(:).');
    end
    pers_method = lower(char(p.Results.method));
    pr_opts = struct( ...
        'power_range_mode', lower(char(p.Results.power_range_mode)), ...
        'power_range_db', double(p.Results.power_range_db(:).'), ...
        'power_percentile_lo', p.Results.power_percentile_lo, ...
        'power_margin_db', p.Results.power_margin_db);
    force = p.Results.force;

    script_path = fileparts(mfilename('fullpath'));
    root_path = fileparts(script_path);
    addpath(fullfile(root_path, 'utils'));

    % ========================================================
    % 1. 解析目标: 收集所有 (JNR目录, STFT路径) 对
    % ========================================================
    tasks = {};  % {jnr_dir, stft_path, persist_path}

    if isempty(target_dir)
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

    jnr_subdirs = dir(fullfile(parent_dir, 'JNR_*'));
    has_jnr_subdirs = ~isempty(jnr_subdirs);
    direct_stfts = dir(fullfile(parent_dir, '*_echo_stfts.mat'));
    has_direct_stfts = ~isempty(direct_stfts);

    if has_jnr_subdirs
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
    fprintf('通道 bins=%s, target_size=%s, method=%s\n', ...
        mat2str(channel_power_bins), mat2str(target_size), pers_method);

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

        stft_data = load(stft_path, 'all_stfts');
        all_stfts = stft_data.all_stfts;
        [SAMPLE_NUM, Nfft, N_cols] = size(all_stfts);
        fprintf('  STFT: %d × %d × %d\n', SAMPLE_NUM, Nfft, N_cols);

        fs = 80e6;
        F = (-Nfft/2 : Nfft/2-1)' * (fs / Nfft);

        ts_use = target_size;
        if isempty(ts_use) && numel(channel_power_bins) > 1
            ts_use = [Nfft, max(channel_power_bins)];
        end

        t_start = tic;
        % 探测输出形状
        [P0, ~, ch_info] = compute_persistence_channels( ...
            squeeze(all_stfts(1, :, :)), channel_power_bins, [0 1], pers_method, ts_use);
        target_size = ch_info.target_size; %#ok<NASGU>
        if ndims(P0) == 3
            [H_out, W_out, C_out] = size(P0);
            all_persistences = zeros(SAMPLE_NUM, H_out, W_out, C_out, 'single');
            is_multi = true;
        else
            [H_out, W_out] = size(P0);
            C_out = 1;
            all_persistences = zeros(SAMPLE_NUM, H_out, W_out, 'single');
            is_multi = false;
        end
        all_power_centers = [];
        persistence_method = pers_method; %#ok<NASGU>

        if strcmp(pers_method, 'matlab')
            fprintf('  模式: matlab | 输出 %d×%d×%d\n', H_out, W_out, C_out);
            all_power_centers = zeros(SAMPLE_NUM, W_out, 'single');
            power_range_db = []; %#ok<NASGU>
            power_range_mode = 'per_sample'; %#ok<NASGU>
            for i = 1:SAMPLE_NUM
                [P, pc, ~] = compute_persistence_channels( ...
                    squeeze(all_stfts(i, :, :)), channel_power_bins, [], 'matlab', ts_use);
                if is_multi
                    all_persistences(i, :, :, :) = single(P);
                else
                    all_persistences(i, :, :) = single(P);
                end
                all_power_centers(i, :) = single(pc);
                if mod(i, 500) == 0
                    fprintf('    %d/%d (%.0fs)\n', i, SAMPLE_NUM, toc(t_start));
                end
            end
            power_centers = all_power_centers(1, :);
        else
            stft_ref = squeeze(all_stfts(1, :, :));
            [global_pwr_range, pr_info] = resolve_custom_power_range(stft_ref, pr_opts);
            power_range_db = global_pwr_range; %#ok<NASGU>
            power_range_mode = pr_info.mode; %#ok<NASGU>
            fprintf('  模式: custom/%s | 功率 [%.1f, %.1f] dB | 输出 %d×%d×%d\n', ...
                pr_info.mode, global_pwr_range(1), global_pwr_range(2), H_out, W_out, C_out);
            for i = 1:SAMPLE_NUM
                [P, power_centers, ~] = compute_persistence_channels( ...
                    squeeze(all_stfts(i, :, :)), channel_power_bins, global_pwr_range, 'custom', ts_use);
                if is_multi
                    all_persistences(i, :, :, :) = single(P);
                else
                    all_persistences(i, :, :) = single(P);
                end
                if mod(i, 500) == 0
                    fprintf('    %d/%d (%.0fs)\n', i, SAMPLE_NUM, toc(t_start));
                end
            end
        end
        fprintf('  耗时: %.1fs (%d样本)\n', toc(t_start), SAMPLE_NUM);

        save_vars = {'all_persistences', 'num_power_bins', 'channel_power_bins', ...
            'target_size', 'power_centers', 'persistence_method', ...
            'power_range_mode', 'power_range_db', 'F'};
        if ~isempty(all_power_centers)
            save_vars{end+1} = 'all_power_centers';
        end
        save(persist_path, save_vars{:}, '-v7.3');
        info = dir(persist_path);
        fprintf('  已保存: %s (%.1f MB) shape=%s\n', ...
            persist_path, info.bytes / 1e6, mat2str(size(all_persistences)));
    end

    fprintf('\n========== 全部完成: %d 个文件 ==========\n', size(tasks, 1));
end
