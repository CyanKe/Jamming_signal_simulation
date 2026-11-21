function main_generation_unified(mode)
% main_generation_unified - 生成统一数据集的分量文件
%
% 用法:
%   main_generation_unified('smoke')   % 少量单元测试到 unified_20261118_smoke
%   main_generation_unified('full')    % 全量到 unified_20261118
%
% 每个 (split, JNR, class) 写一个 .mat（分量 + E 短序列 + W）和一个 .json（metadata）。
% 主集不重放：每个 cell 用唯一 seed，样本内回波/噪声只属于该样本。
% 配对诊断集单独放在 paired_diagnostic/，按实现共享 E/W，仅用于诊断。

if nargin < 1
    mode = 'full';
end
root_path = 'D:/VSCODE/Jamming_signal_simulation';
addpath(genpath(fullfile(root_path, 'generators')));
addpath(fullfile(root_path, 'utils'));
addpath(fullfile(root_path, 'utils', 'features'));
addpath(fullfile(root_path, 'main'));

if strcmpi(mode, 'smoke')
    out_root = 'E:/GPCN_v2_data/unified_20261118_smoke';
    FORCE = true;
else
    out_root = 'E:/GPCN_v2_data/unified_20261118';
    FORCE = false;
end
if ~exist(out_root, 'dir'), mkdir(out_root); end
diary(fullfile(out_root, 'generation.log'));
diary on;

fprintf('==== unified generation mode=%s out=%s ====\n', mode, out_root);

cfg = config();
cfg.jamming.combo_deceptive = {'none'};
cfg.jamming.combo_types = {'none'};
cfg.generation_plan = {};
p0 = config_to_params(cfg);
[~, p0] = generate_0base_signal(p0);

D = {'DFTJ','SMSPJ','CSJ','ISCJ','ISRJ','MISRJ','ISDJ','C&IJ'};
S = {'AJ','BJ','SJ','NAMJ','NPMJ','NFMJ','PJ','NCJ','NPJ'};
classes = build_classes(D, S);

if strcmpi(mode, 'smoke')
    keep = {'DFTJ', 'CSJ+AJ', 'DFTJ+CSJ', 'DFTJ+DFTJ', 'PJ'};
    keep_idx = find(ismember({classes.name}, keep));
    classes = classes(keep_idx);
    jnr_train = [0 50];
    jnr_test  = [-10 0 50];
    N_train = 5; N_val = 3; N_test = 5; N_key = 7;
else
    jnr_train = 0:5:20;
    jnr_test  = -10:5:50;
    N_train = 100; N_val = 20; N_test = 100; N_key = 200;
end

write_dataset_protocol(out_root, classes, mode, jnr_train, jnr_test, ...
    N_train, N_val, N_test, N_key);

splits = {'train', 'val', 'test'};
t_start = tic;
for si = 1:numel(splits)
    split = splits{si};
    if strcmp(split, 'test')
        jnrs = jnr_test;
        cls_idx = 1:numel(classes);
    else
        jnrs = jnr_train;
        cls_idx = 1:min(17, numel(classes));   % 只有 17 单类进入 train/val
    end
    for ji = 1:numel(jnrs)
        jnr = jnrs(ji);
        jdir = fullfile(out_root, sprintf('JNR_%+d', jnr), split);
        if ~exist(jdir, 'dir'), mkdir(jdir); end
        for ci = cls_idx
            cls = classes(ci);
            if strcmp(split, 'test')
                if cls.key
                    N = N_key;
                else
                    N = N_test;
                end
            elseif strcmp(split, 'val')
                N = N_val;
            else
                N = N_train;
            end
            name = cls.name;
            mat_path = fullfile(jdir, [name '.mat']);
            json_path = fullfile(jdir, [name '.json']);
            if ~FORCE && exist(mat_path, 'file') && exist(json_path, 'file')
                continue;
            end

            % 唯一 seed：split/jnr/class 组合互不重复
            seed = 20261118 + (si - 1) * 100000 + (ji - 1) * 1000 + ci;
            rng(seed, 'twister');
            t_cell = tic;
            [samples, meta, comp] = multi_generation_v2(cls.types, p0, jnr, N, cfg);
            write_cell(mat_path, json_path, split, jnr, ci - 1, cls, seed, N, samples, meta, comp);
            fprintf('[%s JNR %+d] %-16s N=%3d  %.1fs\n', split, jnr, name, N, toc(t_cell));
        end
    end
end

if strcmpi(mode, 'full')
    % 配对诊断子集：300 个回波实现 × 17 单类 × 3 JNR
    generate_paired(out_root, cfg, p0, D, S, FORCE);
else
    generate_paired(out_root, cfg, p0, D, S, true, 3, [-10 0 50]);
end

fprintf('==== done in %.1f min ====\n', toc(t_start) / 60);
diary off;
end


% ==========================================================
function write_dataset_protocol(out_root, classes, mode, jnr_train, jnr_test, ...
        N_train, N_val, N_test, N_key)
names = {classes.name};
kinds = {classes.kind};
key = [classes.key];
D = {'DFTJ','SMSPJ','CSJ','ISCJ','ISRJ','MISRJ','ISDJ','C&IJ'};
S = {'AJ','BJ','SJ','NAMJ','NPMJ','NFMJ','PJ','NCJ','NPJ'};
order = struct('version', 'unified-20261118', ...
    'classes', {names}, 'kinds', {kinds}, 'key', key, 'n_classes', numel(names), ...
    'deceptive', {D}, 'suppressive', {S}, ...
    'legacy89', struct('single_indices', 0:16, 'ds_indices', 81:152, ...
                       'legacy_indices', 17:88), ...
    'note', 'class_index is 0-based; legacy 89-class view uses singles 0..16 and DS 81..152 mapped to 17..88');
fid = fopen(fullfile(out_root, 'class_order.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(order));
fclose(fid);

protocol = struct('version', 'unified-20261118', 'mode', mode, ...
    'fs', 80e6, 'PRI_us', 100, 'window', 8000, 'snr_pulse_db', -5, ...
    'train_jnrs', jnr_train, 'test_jnrs', jnr_test, ...
    'N_train', N_train, 'N_val', N_val, 'N_test', N_test, 'N_key', N_key, ...
    'E_max', 2400, ...
    'component_format', 'real/imag single; h5py shape (N,T); E padded to E_max', ...
    'mixing', 'rx = sum(jam components) + E + W', ...
    'jnr_semantics', 'per-component JNR; total JNR = component JNR + 10log10(n_components)', ...
    'no_replay', 'main set: unique echo/noise per sample; paired_diagnostic shares E/W by design');
fid = fopen(fullfile(out_root, 'protocol.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(protocol));
fclose(fid);
end


% ==========================================================
function classes = build_classes(D, S)
classes = struct('name', {}, 'types', {}, 'kind', {}, 'key', {});
for i = 1:numel(D)
    classes(end+1) = struct('name', D{i}, 'types', {{D{i}}}, 'kind', 'single', 'key', false);
end
for j = 1:numel(S)
    classes(end+1) = struct('name', S{j}, 'types', {{S{j}}}, 'kind', 'single', 'key', false);
end
for i = 1:numel(D)
    for j = i+1:numel(D)
        classes(end+1) = struct('name', [D{i} '+' D{j}], ...
            'types', {{D{i}, D{j}}}, 'kind', 'DD', 'key', false);
    end
end
for i = 1:numel(S)
    for j = i+1:numel(S)
        classes(end+1) = struct('name', [S{i} '+' S{j}], ...
            'types', {{S{i}, S{j}}}, 'kind', 'SS', 'key', false);
    end
end
for i = 1:numel(D)
    for j = 1:numel(S)
        classes(end+1) = struct('name', [D{i} '+' S{j}], ...
            'types', {{D{i}, S{j}}}, 'kind', 'DS', 'key', false);
    end
end
for i = 1:numel(D)
    classes(end+1) = struct('name', [D{i} '+' D{i}], ...
        'types', {{D{i}, D{i}}}, 'kind', 'sameDD', 'key', false);
end
for j = 1:numel(S)
    classes(end+1) = struct('name', [S{j} '+' S{j}], ...
        'types', {{S{j}, S{j}}}, 'kind', 'sameSS', 'key', false);
end

% 44 个重点格：×PJ、×NCJ 两列 + ISDJ/ISRJ/SMSPJ/C&IJ 四行 × 其余 7 个 S
key_names = {};
for i = 1:numel(D)
    key_names{end+1} = [D{i} '+PJ'];
    key_names{end+1} = [D{i} '+NCJ'];
end
for d = {'ISDJ','ISRJ','SMSPJ','C&IJ'}
    for j = 1:numel(S)
        if ~any(strcmp(S{j}, {'PJ','NCJ'}))
            key_names{end+1} = [d{1} '+' S{j}];
        end
    end
end
assert(numel(key_names) == 44, 'key cells %d', numel(key_names));
for c = 1:numel(classes)
    classes(c).key = any(strcmp(classes(c).name, key_names));
end
assert(sum([classes.key]) == 44, 'key flags %d', sum([classes.key]));
assert(numel(classes) == 170, 'classes %d', numel(classes));
end


% ==========================================================
function write_cell(mat_path, json_path, split, jnr, class_index, cls, seed, N, samples, meta, comp)
N_total = size(samples, 2);
EMAX = 2400;   % taup <= 30 us * 80 MHz
J1r = zeros(N_total, N, 'single'); J1i = zeros(N_total, N, 'single');
n2 = numel(comp(1).jams) >= 2;
if n2
    J2r = zeros(N_total, N, 'single'); J2i = zeros(N_total, N, 'single');
end
Er = zeros(EMAX, N, 'single'); Ei = zeros(EMAX, N, 'single');
Epos = zeros(1, N, 'uint16'); Elen = zeros(1, N, 'uint16');
Wr = zeros(N_total, N, 'single'); Wi = zeros(N_total, N, 'single');

for m = 1:N
    j1 = comp(m).jams{1};
    J1r(:, m) = single(real(j1(:)));
    J1i(:, m) = single(imag(j1(:)));
    if n2
        j2 = comp(m).jams{2};
        J2r(:, m) = single(real(j2(:)));
        J2i(:, m) = single(imag(j2(:)));
    end
    Efull = comp(m).E;
    nz = find(abs(Efull) > 0);
    if isempty(nz)
        pos = 1; len = 0;
    else
        pos = nz(1); len = nz(end) - pos + 1;
    end
    assert(len <= EMAX, 'E segment too long: %d', len);
    if len > 0
        Er(1:len, m) = single(real(Efull(pos:pos+len-1)));
        Ei(1:len, m) = single(imag(Efull(pos:pos+len-1)));
    end
    Epos(m) = uint16(pos);
    Elen(m) = uint16(len);
    Wr(:, m) = single(real(comp(m).W(:)));
    Wi(:, m) = single(imag(comp(m).W(:)));

    recon = j1 + Efull + comp(m).W;
    if n2, recon = recon + comp(m).jams{2}; end
    err = max(abs(recon - samples(m, :)));
    assert(err < 1e-6, 'reconstruction error %.3g at sample %d (%s)', err, m, cls.name);

    pn = mean(abs(comp(m).W).^2);
    pj = cellfun(@(x) mean(abs(x).^2), comp(m).jams);
    meta(m).class_index = class_index;
    meta(m).class_name = cls.name;
    meta(m).split = split;
    meta(m).jnr = jnr;
    meta(m).types = comp(m).types;
    meta(m).roles = comp(m).roles;
    meta(m).n_components = numel(comp(m).jams);
    meta(m).seed = seed;
    meta(m).protocol_version = 'unified-20261118';
    meta(m).measured_component_jnr_db = 10 * log10(pj / pn);
    meta(m).measured_total_jnr_db = 10 * log10(sum(pj) / pn);
    meta(m).measured_snr_db = 10 * log10(mean(abs(comp(m).E).^2) / pn);
    meta(m).E_pos = double(pos);
    meta(m).E_len = double(len);
    meta(m).echo_id = sprintf('E_%08d_%05d', seed, m);
    meta(m).noise_id = sprintf('W_%08d_%05d', seed, m);
end

class_name = cls.name;
protocol_version = 'unified-20261118';
n_components = size(comp(1).jams, 2);
vars = {'J1r','J1i','Er','Ei','Epos','Elen','Wr','Wi', ...
        'class_name','class_index','split','jnr','n_components','seed','protocol_version'};
if n2
    vars = [vars, {'J2r','J2i'}];
end
save(mat_path, vars{:}, '-v7.3', '-nocompression');
fid = fopen(json_path, 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(meta));
fclose(fid);
end


% ==========================================================
function generate_paired(out_root, cfg, p0, D, S, FORCE, num_echoes, jnrs)
if nargin < 7, num_echoes = 300; end
if nargin < 8, jnrs = [0 20 50]; end
types = [D, S];
assert(numel(types) == 17);
root = fullfile(out_root, 'paired_diagnostic');
if ~exist(root, 'dir'), mkdir(root); end
EMAX = 2400;
for ji = 1:numel(jnrs)
    jnr = jnrs(ji);
    jdir = fullfile(root, sprintf('JNR_%+d', jnr));
    if ~exist(jdir, 'dir'), mkdir(jdir); end
    for e = 1:num_echoes
        mat_path = fullfile(jdir, sprintf('echo_%04d.mat', e));
        json_path = fullfile(jdir, sprintf('echo_%04d.json', e));
        if ~FORCE && exist(mat_path, 'file') && exist(json_path, 'file')
            continue;
        end
        seed_e = 700000000 + e;   % 同一 e 在 3 个 JNR 中复用
        rng(seed_e, 'twister');
        if isfield(cfg.signal, 'B_range') && ~isempty(cfg.signal.B_range)
            [p0.B, p0.taup, p0.sweep_dir] = sample_lfm_params(cfg.signal, p0.fs, p0.PRI);
        else
            p0.sweep_dir = 1;
        end
        pr = cfg.generation.pos_range;
        p0.pos = pr(1) + randi([0, pr(2) - pr(1)]);
        [tx, pp] = generate_0base_signal(p0);
        W = randn(1, pp.N_total) + 1j * randn(1, pp.N_total);
        W = W / std(W);
        ph = exp(rand * 2 * pi * 1i);
        fixed = struct('B', pp.B, 'taup', pp.taup, 'sweep_dir', pp.sweep_dir, ...
            'pos', pp.pos, 'white_noise', W, 'random_phase', ph);
        E = 10^(pp.SNR/20) * tx * ph;

        Jr = zeros(8000, numel(types), 'single');
        Ji = zeros(8000, numel(types), 'single');
        pj = zeros(1, numel(types));
        comp_meta = struct('type', {}, 'seed_jam', {}, 'jam_info', {}, 'measured_jnr_db', {});
        for k = 1:numel(types)
            seed_j = mod(seed_e * 100 + k, 2^32 - 1);
            rng(seed_j, 'twister');
            [~, ~, c] = multi_generation_v2(types{k}, pp, jnr, 1, cfg, fixed);
            j = c(1).jams{1};
            Jr(:, k) = single(real(j(:)));
            Ji(:, k) = single(imag(j(:)));
            pj(k) = mean(abs(j).^2);
            comp_meta(k).type = types{k};
            comp_meta(k).seed_jam = seed_j;
            comp_meta(k).jam_info = c(1).component_params{1}.jam_info;
            comp_meta(k).measured_jnr_db = 10 * log10(pj(k) / mean(abs(W).^2));
        end
        nz = find(abs(E) > 0);
        pos = nz(1); len = nz(end) - pos + 1;
        assert(len <= EMAX);
        Er = zeros(EMAX, 1, 'single'); Ei = zeros(EMAX, 1, 'single');
        Er(1:len) = single(real(E(pos:pos+len-1)));
        Ei(1:len) = single(imag(E(pos:pos+len-1)));
        Wr = single(real(W(:))); Wi = single(imag(W(:)));
        echo_id = sprintf('P_%04d', e); noise_id = sprintf('PW_%04d', e);
        B = pp.B; taup = pp.taup; mu = pp.mu; sweep_dir = pp.sweep_dir;
        Epos = uint16(pos); Elen = uint16(len);
        protocol_version = 'unified-20261118';
        save(mat_path, 'Jr','Ji','Er','Ei','Epos','Elen','Wr','Wi', ...
            'echo_id','noise_id','jnr','B','taup','mu','sweep_dir','protocol_version', ...
            '-v7.3', '-nocompression');
        meta = struct('echo_index', e, 'echo_id', echo_id, 'noise_id', noise_id, ...
            'jnr', jnr, 'B', B, 'taup', taup, 'mu', mu, 'pos', pos, ...
            'sweep_dir', sweep_dir, 'seed_echo', seed_e, ...
            'types', {types}, 'component_params', {comp_meta}, ...
            'protocol_version', protocol_version, ...
            'note', 'diagnostic only; E/W shared across 17 types and 3 JNR, not for main tables');
        fid = fopen(json_path, 'w', 'n', 'UTF-8');
        fprintf(fid, '%s', jsonencode(meta));
        fclose(fid);
        if mod(e, 25) == 0
            fprintf('[paired JNR %+d] %d/%d\n', jnr, e, num_echoes);
        end
    end
end
end
