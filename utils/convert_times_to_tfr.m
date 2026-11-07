% ==========================================================
% convert_times_to_tfr.m - 从时域数据生成 WVD / PWVD / SPWVD / CWD
%
% 默认: 每 jam type 取 1 样本; lag 窗 256; 原生 256x256 → resize 224x224
%
% 使用:
%   convert_times_to_tfr
%   convert_times_to_tfr('output/psp_test/JNR_+10')
%   convert_times_to_tfr('output/psp_test', 'per_class', 1, 'force', true)
%   convert_times_to_tfr(dir, 'modes', {'wvd','pwvd','spwvd','cwd'})
%   convert_times_to_tfr(dir, 'lag_len', 256, 'native_size', 256, 'target_size', [224 224])
% ==========================================================

function convert_times_to_tfr(varargin)
    p = inputParser;
    p.addOptional('target_dir', '', @(s) ischar(s) || isstring(s));
    p.addParameter('modes', {'wvd', 'pwvd', 'spwvd', 'cwd'}, @(c) iscell(c) || isstring(c) || ischar(c));
    p.addParameter('lag_len', 256, @isnumeric);
    p.addParameter('time_win_len', 256, @isnumeric);
    p.addParameter('native_size', 256, @isnumeric);
    p.addParameter('target_size', [224, 224], @(v) isnumeric(v) && numel(v) == 2);
    p.addParameter('per_class', 1, @isnumeric);
    p.addParameter('fs', 80e6, @isnumeric);
    p.addParameter('cwd_sigma', 0.5, @isnumeric);
    p.addParameter('cwd_nwin', 256, @isnumeric);
    p.addParameter('cwd_noverlap', 200, @isnumeric);
    p.addParameter('force', false, @islogical);
    p.addParameter('max_classes', inf, @isnumeric);  % 调试用: 限制类数
    p.parse(varargin{:});

    target_dir = char(p.Results.target_dir);
    modes = lower(cellstr(p.Results.modes));
    lag_len = double(p.Results.lag_len);
    time_win_len = double(p.Results.time_win_len);
    native_size = double(p.Results.native_size);
    target_size = double(p.Results.target_size(:).');
    per_class = max(1, round(p.Results.per_class));
    fs = p.Results.fs;
    cwd_sigma = p.Results.cwd_sigma;
    cwd_nwin = double(p.Results.cwd_nwin);
    cwd_noverlap = double(p.Results.cwd_noverlap);
    force = p.Results.force;
    max_classes = p.Results.max_classes;

    script_path = fileparts(mfilename('fullpath'));
    root_path = fileparts(script_path);
    addpath(script_path);
    addpath(fullfile(root_path, 'utils'));

    valid_modes = {'wvd', 'pwvd', 'spwvd', 'cwd'};
    for i = 1:numel(modes)
        if ~ismember(modes{i}, valid_modes)
            error('未知 mode ''%s'', 可选: %s', modes{i}, strjoin(valid_modes, ', '));
        end
    end

    if isempty(target_dir)
        target_dir = auto_pick_output_dir(root_path);
    end
    if ~isfolder(target_dir)
        error('目录不存在: %s', target_dir);
    end

    tasks = collect_times_tasks(target_dir);
    if isempty(tasks)
        error('在 %s 中未找到 *_echo_times.mat', target_dir);
    end

    fprintf('\n========== TFR 转换: %d 个 times 文件 ==========\n', size(tasks, 1));
    fprintf('modes=%s | lag=%d | time_win=%d | native=%d | target=%s | per_class=%d\n', ...
        strjoin(modes, ','), lag_len, time_win_len, native_size, mat2str(target_size), per_class);

    % MATLAB wvd 要求平滑窗为奇数长度; 偶数配置自动 -1
    lag_len_odd = make_odd_len(lag_len);
    time_win_len_odd = make_odd_len(time_win_len);
    if lag_len_odd ~= lag_len
        fprintf('注意: lag 窗长度 %d → %d (wvd 要求奇数)\n', lag_len, lag_len_odd);
    end
    if time_win_len_odd ~= time_win_len
        fprintf('注意: 时间窗长度 %d → %d (wvd 要求奇数)\n', time_win_len, time_win_len_odd);
    end
    lag_win = hamming(lag_len_odd);
    time_win = hamming(time_win_len_odd);
    lag_len = lag_len_odd;           % 后续元数据记录实际使用值
    time_win_len = time_win_len_odd;

    for t = 1:size(tasks, 1)
        times_path = tasks{t, 1};
        dir_path = tasks{t, 2};
        split_prefix = tasks{t, 3};  % e.g. 'test'
        meta_path = tasks{t, 4};

        fprintf('\n--- [%d/%d] %s ---\n', t, size(tasks, 1), times_path);

        % 跳过: 若全部 mode 已存在且不 force
        out_paths = containers.Map();
        all_exist = true;
        for mi = 1:numel(modes)
            [op, vn] = mode_paths(dir_path, split_prefix, modes{mi});
            out_paths(modes{mi}) = struct('path', op, 'var', vn);
            if ~exist(op, 'file')
                all_exist = false;
            end
        end
        if all_exist && ~force
            fprintf('  跳过 (全部 TFR 已存在, force=true 可覆盖)\n');
            continue;
        end

        % 加载 times
        try
            td = load(times_path, 'all_times');
        catch ME
            warning('加载失败 %s: %s', times_path, ME.message);
            continue;
        end
        if ~isfield(td, 'all_times')
            warning('无 all_times: %s', times_path);
            continue;
        end
        all_times = td.all_times;
        [SAMPLE_NUM, N_total] = size(all_times);
        fprintf('  all_times: [%d x %d] %s\n', SAMPLE_NUM, N_total, class(all_times));

        % 选样本
        [sel, labels, meta_sel] = select_per_class_indices( ...
            meta_path, SAMPLE_NUM, per_class, max_classes);
        n_sel = numel(sel);
        fprintf('  选中样本: %d (每类最多 %d)\n', n_sel, per_class);
        for k = 1:min(n_sel, 20)
            fprintf('    [%3d] idx=%d  %s\n', k, sel(k), labels{k});
        end
        if n_sel > 20
            fprintf('    ... 共 %d 条\n', n_sel);
        end

        % 写子集 metadata (与 TFR 样本顺序对齐, 0-based 浏览器索引对应此数组)
        tfr_meta_path = fullfile(dir_path, sprintf('%s_echo_tfr_metadata.json', split_prefix));
        write_tfr_metadata(tfr_meta_path, meta_sel, sel, labels);

        % 计时与结果
        cost = struct();
        for mi = 1:numel(modes)
            mode = modes{mi};
            info = out_paths(mode);
            if exist(info.path, 'file') && ~force
                fprintf('  跳过 %s (已存在)\n', mode);
                continue;
            end

            fprintf('  计算 %s ...\n', upper(mode));
            arr = zeros(n_sel, target_size(1), target_size(2), 'single');
            F = [];
            T = [];
            t_mode = tic;
            times_each = zeros(n_sel, 1);

            for i = 1:n_sel
                x = double(all_times(sel(i), :));
                t1 = tic;
                [d, Fi, Ti] = compute_one_tfr(x, fs, mode, lag_win, time_win, ...
                    native_size, cwd_nwin, cwd_noverlap, cwd_sigma);
                times_each(i) = toc(t1);

                % 统一 256 → 224
                d = ensure_size(d, [native_size, native_size]);
                d = ensure_size(d, target_size);
                arr(i, :, :) = single(real(d));

                if isempty(F)
                    F = Fi;
                    T = Ti;
                end

                if mod(i, 5) == 0 || i == n_sel
                    fprintf('    %s %d/%d  last=%.2fs  mean=%.2fs\n', ...
                        upper(mode), i, n_sel, times_each(i), mean(times_each(1:i)));
                end
            end
            elapsed = toc(t_mode);
            cost.(mode) = struct( ...
                'elapsed_sec', elapsed, ...
                'per_sample_sec', times_each, ...
                'mean_sec', mean(times_each), ...
                'sum_sec', sum(times_each));

            % 轴插值到 target (近似)
            F_out = linspace_axis(F, target_size(1));
            T_out = linspace_axis(T, target_size(2));

            S = struct();
            S.(info.var) = arr;
            S.F = F_out;
            S.T = T_out;
            S.sel_indices = sel(:);
            S.lag_len = lag_len;
            S.time_win_len = time_win_len;
            S.native_size = native_size;
            S.target_size = target_size;
            S.tfr_mode = mode;
            S.fs = fs;
            S.cwd_sigma = cwd_sigma;
            S.elapsed_sec = elapsed;
            S.mean_sec = mean(times_each);

            save(info.path, '-struct', 'S', '-v7.3', '-nocompression');
            fi = dir(info.path);
            fprintf('  已保存 %s: %s (%.2f MB, %.1fs, mean %.2fs/sample)\n', ...
                upper(mode), info.path, fi.bytes/1e6, elapsed, mean(times_each));
        end

        write_cost_report(dir_path, split_prefix, modes, cost, n_sel, target_size, labels);
    end

    fprintf('\n========== TFR 转换完成 ==========\n');
end


%% ---- helpers ----

function target_dir = auto_pick_output_dir(root_path)
    output_base = fullfile(root_path, 'output');
    dirs = dir(output_base);
    dirs = dirs([dirs.isdir] & ~ismember({dirs.name}, {'.', '..'}));
    if isempty(dirs)
        error('output 下无子目录');
    end
    [~, idx] = sort({dirs.date}, 'descend');
    for k = 1:numel(idx)
        candidate = fullfile(output_base, dirs(idx(k)).name);
        jnr = dir(fullfile(candidate, 'JNR_*'));
        if ~isempty(jnr)
            target_dir = candidate;
            fprintf('自动选择: %s\n', target_dir);
            return;
        end
    end
    error('未找到含 JNR_* 的输出目录');
end


function tasks = collect_times_tasks(parent_dir)
    tasks = {};  % {times_path, dir_path, split_prefix, meta_path}
    jnr_sub = dir(fullfile(parent_dir, 'JNR_*'));
    if isempty(jnr_sub)
        jnr_sub = dir(fullfile(parent_dir, 'SNR_*'));
    end

    if ~isempty(jnr_sub)
        for d = 1:numel(jnr_sub)
            jdir = fullfile(parent_dir, jnr_sub(d).name);
            tasks = [tasks; list_times_in_dir(jdir)]; %#ok<AGROW>
        end
    else
        tasks = list_times_in_dir(parent_dir);
    end
end


function tasks = list_times_in_dir(jdir)
    tasks = {};
    files = dir(fullfile(jdir, '*_echo_times.mat'));
    for f = 1:numel(files)
        times_path = fullfile(jdir, files(f).name);
        [~, name] = fileparts(files(f).name);
        % test_echo_times -> test
        split_prefix = regexprep(name, '_echo_times$', '');
        meta_path = fullfile(jdir, sprintf('%s_echo_metadata.json', split_prefix));
        if ~exist(meta_path, 'file')
            meta_path = '';
        end
        tasks = [tasks; {times_path, jdir, split_prefix, meta_path}]; %#ok<AGROW>
    end
end


function [out_path, var_name] = mode_paths(dir_path, split_prefix, mode)
    switch mode
        case 'wvd'
            out_path = fullfile(dir_path, sprintf('%s_echo_wvds.mat', split_prefix));
            var_name = 'all_wvds';
        case 'pwvd'
            out_path = fullfile(dir_path, sprintf('%s_echo_pwvds.mat', split_prefix));
            var_name = 'all_pwvds';
        case 'spwvd'
            out_path = fullfile(dir_path, sprintf('%s_echo_spwvds.mat', split_prefix));
            var_name = 'all_spwvds';
        case 'cwd'
            out_path = fullfile(dir_path, sprintf('%s_echo_cwds.mat', split_prefix));
            var_name = 'all_cwds';
        otherwise
            error('mode %s', mode);
    end
end


function [sel, labels, meta_sel] = select_per_class_indices(meta_path, sample_num, per_class, max_classes)
    sel = [];
    labels = {};
    meta_sel = {};

    if ~isempty(meta_path) && exist(meta_path, 'file')
        raw = fileread(meta_path);
        meta = jsondecode(raw);
        if ~iscell(meta)
            meta = num2cell(meta);
        end
        counts = containers.Map('KeyType', 'char', 'ValueType', 'double');
        n_classes = 0;
        for i = 1:min(numel(meta), sample_num)
            item = meta{i};
            if isstruct(item) && isfield(item, 'jam_types')
                key = jam_type_key(item.jam_types);
            else
                key = sprintf('idx_%d', i);
            end
            is_new = ~isKey(counts, key);
            if is_new
                if isfinite(max_classes) && n_classes >= max_classes
                    continue;  % 不再接受新类
                end
                counts(key) = 0;
                n_classes = n_classes + 1;
            end
            if counts(key) < per_class
                counts(key) = counts(key) + 1;
                sel(end+1) = i; %#ok<AGROW>
                labels{end+1} = key; %#ok<AGROW>
                meta_sel{end+1} = item; %#ok<AGROW>
            end
        end
    else
        warning('无 metadata, 使用前 %d 个样本', min(per_class, sample_num));
        n = min(per_class, sample_num);
        sel = 1:n;
        for i = 1:n
            labels{i} = sprintf('sample_%d', i);
            meta_sel{i} = struct('sample_idx', i, 'jam_types', labels{i});
        end
    end
    sel = sel(:);
end


function key = jam_type_key(jt)
    if iscell(jt)
        parts = cellfun(@char, jt, 'UniformOutput', false);
        key = strjoin(parts, '+');
    elseif isstring(jt)
        if isscalar(jt)
            key = char(jt);
        else
            key = strjoin(cellstr(jt), '+');
        end
    elseif ischar(jt)
        key = jt;
    elseif isnumeric(jt)
        key = mat2str(jt);
    else
        key = 'unknown';
    end
    key = strtrim(key);
end


function write_tfr_metadata(path, meta_sel, sel, labels)
    out = cell(numel(meta_sel), 1);
    for i = 1:numel(meta_sel)
        item = meta_sel{i};
        if ~isstruct(item)
            item = struct('jam_types', labels{i});
        end
        item.tfr_index = i;           % 1-based in TFR file
        item.source_index = sel(i);   % 1-based in all_times
        item.jam_type_key = labels{i};
        out{i} = item;
    end
    % jsonencode cell of structs → JSON array
    try
        js = jsonencode(out);
    catch
        % older MATLAB: convert to struct array
        js = jsonencode([out{:}]);
    end
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        warning('无法写 metadata: %s', path);
        return;
    end
    fwrite(fid, js, 'char');
    fclose(fid);
    fprintf('  TFR metadata: %s (%d)\n', path, numel(out));
end


function [d, F, T] = compute_one_tfr(x, fs, mode, lag_win, time_win, native_size, cwd_nwin, cwd_noverlap, cwd_sigma)
    % R2025b Signal Processing Toolbox:
    %   wvd / wvd(...,"smoothedPseudo",twin,fwin)  — 无独立 "pseudo" 关键字
    %   PWVD ≈ SPWVD 用极短时间窗 (长度 3) + lag/频率窗 fwin
    %   NumFrequencyPoints/NumTimePoints 仅对 smoothedPseudo 有效
    x = x(:);
    nfreq = native_size;
    ntime = native_size;

    switch mode
        case 'wvd'
            % 经典 WVD: 全网格后 resize 到 native
            [d, F, T] = wvd(x, fs);
        case 'pwvd'
            % 伪 WVD (频率/lag 平滑): 最短时间窗 + lag 窗
            twin_pw = ones(3, 1);
            try
                [d, F, T] = wvd(x, fs, 'smoothedPseudo', twin_pw, lag_win, ...
                    'NumFrequencyPoints', nfreq, 'NumTimePoints', ntime);
            catch
                [d, F, T] = wvd(x, fs, 'smoothedPseudo', twin_pw, lag_win);
            end
        case 'spwvd'
            try
                [d, F, T] = wvd(x, fs, 'smoothedPseudo', time_win, lag_win, ...
                    'NumFrequencyPoints', nfreq, 'NumTimePoints', ntime);
            catch
                [d, F, T] = wvd(x, fs, 'smoothedPseudo', time_win, lag_win);
            end
        case 'cwd'
            nfft = nfreq;
            [C, F, T] = choiwilliams(x, cwd_nwin, cwd_noverlap, nfft, fs, ...
                'centered', 'Sigma', cwd_sigma);
            d = real(C);
            d = ensure_size(d, [nfreq, ntime]);
            F = linspace_axis(F, nfreq);
            T = linspace_axis(T, ntime);
            return;
        otherwise
            error('mode %s', mode);
    end
    d = real(d);
    d = ensure_size(d, [nfreq, ntime]);
    F = linspace_axis(F, nfreq);
    T = linspace_axis(T, ntime);
end


function n = make_odd_len(n)
    n = max(3, round(n));
    if mod(n, 2) == 0
        n = n - 1;
    end
end


function d = ensure_size(d, sz)
    d = double(d);
    if isequal(size(d), sz)
        return;
    end
    % 优先 Image Processing Toolbox
    if exist('imresize', 'file') == 2
        d = imresize(d, sz, 'bilinear');
    else
        d = resize_persistence_map(d, sz);
    end
end


function ax = linspace_axis(ax, n)
    if isempty(ax)
        ax = (0:n-1).';
        return;
    end
    ax = ax(:);
    if numel(ax) == n
        return;
    end
    ax = linspace(ax(1), ax(end), n).';
end


function write_cost_report(dir_path, split_prefix, modes, cost, n_sel, target_size, labels)
    report_path = fullfile(dir_path, sprintf('%s_wvd_cost_report.txt', split_prefix));
    bytes_per = prod(target_size) * 4;  % single
    fid = fopen(report_path, 'w');
    if fid < 0
        warning('无法写开销报告');
        return;
    end
    fprintf(fid, 'WVD-family / CWD cost report\n');
    fprintf(fid, 'split=%s  n_sel=%d  target=%s  bytes/sample=%.0f\n', ...
        split_prefix, n_sel, mat2str(target_size), bytes_per);
    fprintf(fid, 'labels (%d): %s\n\n', numel(labels), strjoin(labels, ', '));
    fprintf(fid, '%-8s  %10s  %12s  %12s  %10s\n', ...
        'mode', 'mean_s', 'sum_s', 'elapsed_s', 'disk_MB');
    fprintf(fid, '%s\n', repmat('-', 1, 60));
    total_disk = 0;
    total_time = 0;
    for i = 1:numel(modes)
        m = modes{i};
        if ~isfield(cost, m)
            fprintf(fid, '%-8s  (skipped)\n', m);
            continue;
        end
        c = cost.(m);
        disk_mb = n_sel * bytes_per / 1e6;
        total_disk = total_disk + disk_mb;
        total_time = total_time + c.elapsed_sec;
        fprintf(fid, '%-8s  %10.3f  %12.3f  %12.3f  %10.3f\n', ...
            upper(m), c.mean_sec, c.sum_sec, c.elapsed_sec, disk_mb);
    end
    fprintf(fid, '%s\n', repmat('-', 1, 60));
    fprintf(fid, 'TOTAL wall (sum modes): %.2f s | disk all modes: %.2f MB\n', ...
        total_time, total_disk);
    fclose(fid);
    fprintf('  开销报告: %s\n', report_path);

    % 控制台摘要
    fprintf('\n  ---- 开销摘要 ----\n');
    for i = 1:numel(modes)
        m = modes{i};
        if isfield(cost, m)
            fprintf('  %-6s  mean %.3fs/sample  total %.2fs  disk ~%.2f MB\n', ...
                upper(m), cost.(m).mean_sec, cost.(m).elapsed_sec, n_sel * bytes_per / 1e6);
        end
    end
end
