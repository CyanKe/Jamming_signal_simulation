function [samples,metadata,components] = multi_generation_v2(jam_types,params,current_jnr,data_num,cfg,fixed)
% multi_generation_v2 - 使用配置文件生成多干扰类型样本
% 输入:
%   params - 信号参数结构体
%   current_jnr - 当前干噪比 dB
%   data_num - 生成样本数
%   cfg - 配置结构体
%   fixed - 可选。非空时复用同一条回波/噪声实现（配对诊断集用）：
%           .B .taup .sweep_dir .pos .white_noise .random_phase
% 输出:
%   samples - 生成的信号样本（混合 IQ）
%   metadata - 每个样本的生成参数信息
%   components - 每个样本的分量：.jams（各干扰分量 cell）、.types、.roles、
%                .E（含相位与 SNR 的回波）、.W（单位功率噪声）

if nargin < 6
    fixed = [];
end

% 初始化输出
N_total = params.N_total;
As = 10^(params.SNR/20);
samples = zeros(data_num, N_total);

% 初始化metadata结构数组
metadata = struct('sample_idx', {}, 'jam_types', {}, 'JNR', {}, 'pos', {}, 'B', {}, 'taup', {}, 'mu', {}, 'sweep_dir', {}, 'jam_params', {}, 'component_params', {}, 'roles', {});
components = struct('jams', {}, 'types', {}, 'roles', {}, 'E', {}, 'W', {}, 'component_params', {});

for m = 1:data_num
    % 初始化当前样本的metadata
    metadata(m).sample_idx = m;
    metadata(m).jam_types = jam_types;
    metadata(m).JNR = current_jnr;
    metadata(m).jam_params = struct();
    metadata(m).component_params = {};
    metadata(m).roles = {};

    if isempty(fixed)
        % --- 样本级 LFM 随机化 (先于 pos 随机化) ---
        if isfield(cfg.signal, 'B_range') && ~isempty(cfg.signal.B_range)
            [params.B, params.taup, params.sweep_dir] = ...
                sample_lfm_params(cfg.signal, params.fs, params.PRI);
        else
            params.sweep_dir = 1;  % 默认上扫
        end

        % --- 目标位置随机化 ---
        pos_range = cfg.generation.pos_range;
        current_pos = pos_range(1) + randi([0, pos_range(2)-pos_range(1)]);
        params.pos = current_pos;
    else
        % --- 配对诊断：复用给定实现 ---
        params.B = fixed.B;
        params.taup = fixed.taup;
        params.sweep_dir = fixed.sweep_dir;
        params.pos = fixed.pos;
        current_pos = fixed.pos;
    end

    % --- 生成基础目标信号 ---
    [tx, params] = generate_0base_signal(params);

    % --- 校验: pos+Ntau 不超出 PRI_samp ---
    if params.pos + params.Ntau > params.PRI_samp
        params.pos = max(1, params.PRI_samp - params.Ntau + 1);
    end

    % --- 记录 metadata ---
    metadata(m).pos = current_pos;
    metadata(m).B = params.B;
    metadata(m).taup = params.taup;
    metadata(m).mu = params.mu;
    metadata(m).sweep_dir = params.sweep_dir;

    % --- 生成噪声 ---
    if isempty(fixed)
        white_noise = randn([1,N_total]) + 1j*randn([1,N_total]);
        white_noise = white_noise / std(white_noise);
    else
        white_noise = fixed.white_noise;
    end
    sum_jam = zeros(1, N_total);
    comp_jams = {};
    comp_types = {};
    comp_roles = {};
    comp_params = {};

    if ischar(jam_types)
        jam_types = string(jam_types);
    elseif iscell(jam_types)
        jam_types = string(jam_types);
    end

    for jam_type = jam_types
        jam_info = struct();
        pure_jam = zeros(1, N_total);
        switch jam_type
            case 'clean'  % 纯LFM信号，不生成干扰
                % sum_jam 保持为零向量，无需任何操作
                % 最终 rx = As * tx * random_phase + white_noise
                pure_jam = zeros(1, N_total);

            case 'DFTJ'  % DFTJ - 密集假目标干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam,jam_info] = generate_dftj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.dftj_k = jam_info(1).k;

            case 'ISRJ'  % ISRJ - 间歇采样转发干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam,jam_info] = generate_isrj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.isrj_M = jam_info(1).M;
                metadata(m).jam_params.isrj_N = jam_info(1).N;

            case 'ISCJ'  % ISCJ - 间歇采样循环转发干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam,jam_info] = generate_iscj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.iscj_M = jam_info(1).M;
                metadata(m).jam_params.iscj_N = jam_info(1).N;
                metadata(m).jam_params.iscj_period = jam_info(1).period;
                metadata(m).jam_params.iscj_duty = jam_info(1).duty;

            case 'ISDJ'  % ISDJ - 间歇采样循环/直接干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam,jam_info] = generate_isdj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.isdj_M = jam_info(1).M;
                metadata(m).jam_params.isdj_N = jam_info(1).N;
            
            case 'MISRJ'  % MISRJ - 调制间歇采样转发干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam,jam_info] = generate_misrj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.misrj_M = jam_info(1).M;
                metadata(m).jam_params.misrj_K = jam_info(1).K;
                metadata(m).jam_params.misrj_slice_ratio = jam_info(1).slice_ratio;
                metadata(m).jam_params.misrj_delay_ratio = jam_info(1).delay_ratio;

            case 'SMSPJ' % SMSPJ - 弥散谱干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, jam_info] = generate_smspj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.smspj_M = jam_info(1).M;
                metadata(m).jam_params.smspj_slope_factor = jam_info(1).slope_factor;

            case 'C&IJ' % CIJ - 切片交织干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, jam_info] = generate_cij_jamming(tx, jam_params, 1);
                metadata(m).jam_params.cij_a = jam_info(1).a;
                metadata(m).jam_params.cij_b = jam_info(1).b;
                metadata(m).jam_params.cij_is_continuous = jam_info(1).is_continuous;


            case 'CSJ' % CSJ - 梳状谱干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam, jam_info] = generate_csj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.csj_M = jam_info(1).M;
                metadata(m).jam_params.csj_comb_teeth_count = jam_info(1).comb_teeth_count;

            case 'AJ'  % AJ - 瞄准干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.aj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
                jam_params.random_Fj = cfg.jamming.aj.random_Fj;
                [pure_jam] = generate_ab_jamming(tx, jam_params, 1);
                metadata(m).jam_params.aj_BJ = jam_params.BJ;

            case 'BJ'  % BJ - 阻塞干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.bj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
                jam_params.random_Fj = cfg.jamming.bj.random_Fj;
                [pure_jam] = generate_ab_jamming(tx, jam_params, 1);
                metadata(m).jam_params.bj_BJ = jam_params.BJ;

            case 'SJ'  % SJ - 扫频干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.sj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
                [pure_jam] = generate_sj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.sj_BJ = jam_params.BJ;

            case 'NCJ'  % NCJ - 噪声卷积干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                if sf_enabled(cfg, 'ncj', params)
                    jam_params = apply_sf(jam_params, cfg.jamming.ncj);
                    [pure_jam, sf_info] = generate_ncj_sf_jamming(tx, jam_params, 1);
                    metadata(m).jam_params.ncj_U        = sf_info(1).U;
                    metadata(m).jam_params.ncj_n_blocks = sf_info(1).n_blocks;
                else
                    [pure_jam] = generate_ncj_jamming(tx, jam_params, 1);
                end

            case 'NPJ'  % NPJ - 噪声乘积干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                if sf_enabled(cfg, 'npj', params)
                    jam_params = apply_sf(jam_params, cfg.jamming.npj);
                    [pure_jam, sf_info] = generate_npj_sf_jamming(tx, jam_params, 1);
                    metadata(m).jam_params.npj_U        = sf_info(1).U;
                    metadata(m).jam_params.npj_n_blocks = sf_info(1).n_blocks;
                else
                    [pure_jam] = generate_npj_jamming(tx, jam_params, 1);
                end

            
            case 'NFMJ' % NFMJ - 噪声调频干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.nfmj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
                jam_params.random_Fj = cfg.jamming.nfmj.random_Fj;
                % 可选 Kf / Kf_range (Hz/V)；缺省由 generate_nfmj 使用 Bj/4
                if isfield(cfg.jamming.nfmj, 'Kf_range') && numel(cfg.jamming.nfmj.Kf_range) >= 2
                    kr = cfg.jamming.nfmj.Kf_range;
                    jam_params.Kf = kr(1) + (kr(2) - kr(1)) * rand;
                elseif isfield(cfg.jamming.nfmj, 'Kf')
                    jam_params.Kf = cfg.jamming.nfmj.Kf;
                end
                [pure_jam] = generate_nfmj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.nfmj_BJ = jam_params.BJ;

            case 'NPMJ' % NPMJ - 噪声调相干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                % BJ = 目标 RF 带宽 (Hz)；不再硬截断到 30 MHz
                BJ_range = cfg.jamming.npmj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2) - BJ_range(1)) * rand) * 1e6;
                jam_params.BJ = min(jam_params.BJ, 0.9 * params.fs);
                jam_params.random_Fj = cfg.jamming.npmj.random_Fj;
                % 可选 Kp / Kp_range (rad)；缺省由 generate_npmj 使用 pi/2
                if isfield(cfg.jamming.npmj, 'Kp_range') && numel(cfg.jamming.npmj.Kp_range) >= 2
                    kr = cfg.jamming.npmj.Kp_range;
                    jam_params.Kp = kr(1) + (kr(2) - kr(1)) * rand;
                elseif isfield(cfg.jamming.npmj, 'Kp')
                    jam_params.Kp = cfg.jamming.npmj.Kp;
                end
                [pure_jam] = generate_npmj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.npmj_BJ = jam_params.BJ;
                if isfield(jam_params, 'Kp')
                    metadata(m).jam_params.npmj_Kp = jam_params.Kp;
                end

            case 'NAMJ' % NAMJ - 噪声调幅干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                BJ_range = cfg.jamming.namj.BJ_range;
                jam_params.BJ = (BJ_range(1) + (BJ_range(2)-BJ_range(1))*rand) * 1e6;
                jam_params.random_Fj = cfg.jamming.namj.random_Fj;
                % 可选 m_a / m_a_range；缺省由 generate_namj 使用 0.8
                if isfield(cfg.jamming.namj, 'm_a_range') && numel(cfg.jamming.namj.m_a_range) >= 2
                    mr = cfg.jamming.namj.m_a_range;
                    jam_params.m_a_range = mr;
                elseif isfield(cfg.jamming.namj, 'm_a')
                    jam_params.m_a = cfg.jamming.namj.m_a;
                end
                [pure_jam] = generate_namj_jamming(tx, jam_params, 1);
                metadata(m).jam_params.namj_BJ = jam_params.BJ;

            case 'PJ' % PJ - 脉冲干扰
                jam_params = params;
                jam_params.JNR = current_jnr;
                [pure_jam] = generate_pulse_jamming(tx, jam_params, 1);

                
            % case 3  % RGPO - 距离假目标干扰
            %     jam_params = params;
            %     jam_params.JNR = current_jnr;
            %     jam_params.v = cfg.jamming.rgpo.v;  % 从配置读取
            %     time_range = cfg.jamming.rgpo.start_time;  % 从配置读取
            %     jam_params.start_time = (time_range(1) + (time_range(2)-time_range(1))*rand);
            %     [pure_jam, jam_info] = generate_3rgpo_jamming(tx, jam_params, 1);
            %     metadata(m).jam_params.rgpo_v = jam_params.v;
            %     metadata(m).jam_params.vgpo_start_time = jam_params.start_time;
            %     metadata(m).jam_params.rgpo_position_relation = jam_info(1).position_relation;
            %     metadata(m).jam_params.rgpo_final_delay_us = jam_info(1).final_delay_us;

            % case 4  % VGPO - 速度假目标干扰
            %     jam_params = params;
            %     jam_params.JNR = current_jnr;
            %     jam_params.pull = cfg.jamming.vgpo.pull;  % 从配置读取
            %     time_range = cfg.jamming.rgpo.start_time;  % 从配置读取
            %     jam_params.start_time = (time_range(1) + (time_range(2)-time_range(1))*rand);
            %     [pure_jam, jam_info] = generate_4vgpo_jamming(tx, jam_params, 1);
            %     metadata(m).jam_params.vgpo_pull = jam_params.pull;
            %     metadata(m).jam_params.vgpo_start_time = jam_params.start_time;
            %     metadata(m).jam_params.vgpo_doppler_direction = jam_info(1).doppler_direction;
            %     metadata(m).jam_params.vgpo_final_fd_kHz = jam_info(1).final_fd_kHz;
        end

        % --- 记录本分量（clean 不计入干扰分量）---
        if ~strcmp(char(jam_type), 'clean')
            comp_jams{end+1} = pure_jam;
            comp_types{end+1} = char(jam_type);
            if is_deceptive_type(char(jam_type))
                comp_roles{end+1} = 'D';
            else
                comp_roles{end+1} = 'S';
            end
            comp_params{end+1} = struct('type', char(jam_type), 'jam_info', jam_info);
        end
        sum_jam = sum_jam + pure_jam;
    end

    % --- 混合信号 ---
    pure_echo = As * tx;
    if isempty(fixed)
        random_phase = exp(rand*2*pi*1i);
    else
        random_phase = fixed.random_phase;
    end
    E = pure_echo * random_phase;
    rx = E + sum_jam + white_noise;

    samples(m, :) = rx;
    metadata(m).component_params = comp_params;
    metadata(m).roles = comp_roles;
    components(m).jams = comp_jams;
    components(m).types = comp_types;
    components(m).roles = comp_roles;
    components(m).E = E;
    components(m).W = white_noise;
    components(m).component_params = comp_params;
end
end

% ==========================================================
% 干扰类型分类
% ==========================================================
function tf = is_deceptive_type(t)
    D = {'DFTJ','SMSPJ','CSJ','ISCJ','ISRJ','MISRJ','ISDJ','C&IJ'};
    tf = any(strcmp(t, D));
end


% ==========================================================
% 存储-转发（store-and-forward）辅助
% ==========================================================
function tf = sf_enabled(cfg, name, params)
% 是否启用某类干扰的存储-转发生成器。
% 条件：配置里显式给了 U，且 Np > 1（单脉冲时存储-转发无意义，走原生成器）。
    tf = false;
    if ~isfield(cfg, 'jamming') || ~isfield(cfg.jamming, name)
        return;
    end
    if ~isfield(cfg.jamming.(name), 'U') || isempty(cfg.jamming.(name).U)
        return;
    end
    tf = params.Np > 1;
end

function p = apply_sf(p, sec)
% 把配置里的 U / drift_per_pulse 写进 params
    p.U = sec.U;
    if isfield(sec, 'drift_per_pulse') && ~isempty(sec.drift_per_pulse)
        p.drift_per_pulse = sec.drift_per_pulse;
    end
end