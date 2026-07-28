% ==========================================================
% config.m - 全局配置文件
% 用于数据生成的参数设置，与生成函数解耦
% ==========================================================

function cfg = config()
    % ==================== 信号基础参数 ====================
    cfg.signal.fs = 80e6;           % 采样频率 80MHz
    cfg.signal.fc = 40e6;           % 中心频率 40MHz
    cfg.signal.B = 10e6;            % 带宽 10MHz
    cfg.signal.taup = 20e-6;        % LFM脉宽 20us
    cfg.signal.Np = 1;              % 脉冲个数
    cfg.signal.PRI = 100e-6;        % 脉冲重复间隔 100us
    cfg.signal.SNR = -5;            % 信噪比 dB
    cfg.signal.pos = 5000;          % 目标在PRI中的起始位置
    cfg.signal.B_range = [8e6, 15e6];         % LFM带宽随机范围 [min, max] Hz（样本级随机，方案A）
    cfg.signal.taup_range = [15e-6, 30e-6];   % LFM脉宽随机范围 [min, max] s（样本级随机，方案A）
    cfg.signal.sweep_dir_enable = true;        % 是否随机上下扫频（false=固定上扫）
    cfg.signal.BT_min = 50;                    % 最小时间带宽积 B*taup

    % ==================== 干扰参数 ====================
    cfg.jamming.numClasses = 17;    % 基础干扰类型数量 (8 deceptive + 9 suppressive)
    cfg.jamming.JNR_values = 10;   % 干噪比范围 dB (可以是标量或数组如 0:5:20)

    % ==================== 各干扰类型的特定参数 ====================
    % RGPO (距离拖引干扰)
    cfg.jamming.rgpo.v = 20e5;       % 拖引速率
    % VGPO (速度拖引干扰)
    cfg.jamming.vgpo.pull = 500e6;    % 拖引频率 Hz
    cfg.jamming.vgpo.start_time = 10e-3; %拖引阶段

    % AJ (瞄准干扰)
    cfg.jamming.aj.BJ_range = [18.5, 23.5];  % 干扰带宽范围 MHz -> 实际 *1e6
    cfg.jamming.aj.random_Fj = true;          % 随机载波频率

    % BJ (阻塞干扰)
    cfg.jamming.bj.BJ_range = [45, 55];      % 干扰带宽范围 MHz
    cfg.jamming.bj.random_Fj = true;

    % SJ (扫频干扰)
    cfg.jamming.sj.BJ_range = [10, 30];      % 干扰带宽范围 MHz

    % NFMJ (噪声调频干扰)
    % BJ_range: 目标 RF 带宽 (MHz)，经 NFM 射频带宽公式 B_RF ≈ 2*Kf*sig_n 反推调制噪声带宽
    cfg.jamming.nfmj.BJ_range = [15, 25];    % 干扰带宽范围 MHz
    cfg.jamming.nfmj.random_Fj = true;
    cfg.jamming.nfmj.Kf = 2e6;               % 调频灵敏度 (Hz/V)，对 unit-rms 调制噪声
    cfg.jamming.nfmj.Kf_range = [1e6, 4e6];  % 可选：样本级随机 Kf（优先于 Kf）

    % NPMJ (噪声调相干扰)
    % BJ_range: 目标 RF 带宽 (MHz)，经 Carson 反推调制噪声带宽
    %   B_RF ≈ 2*(Kp+1)*N_bw  =>  N_bw = BJ/(2*(Kp+1))
    cfg.jamming.npmj.BJ_range = [15, 15];    % 目标 RF 带宽范围 MHz
    cfg.jamming.npmj.random_Fj = true;
    cfg.jamming.npmj.Kp = 1.5;               % 调相指数 (rad)，对 unit-rms 调制噪声
    % cfg.jamming.npmj.Kp_range = [1.0, 2.5]; % 可选：样本级随机 Kp（优先于 Kp）

    % NAMJ (噪声调幅干扰)
    cfg.jamming.namj.BJ_range = [15, 25];    % 干扰带宽范围 MHz
    cfg.jamming.namj.random_Fj = true;
    cfg.jamming.namj.m_a = 0.8;              % 调幅深度
    cfg.jamming.namj.m_a_range = [0.3, 0.95]; % 可选：样本级随机 m_a（优先于 m_a）

    % ==================== STFT参数 ====================
    cfg.stft.Nwin = 128;           % 窗口长度
    cfg.stft.Noverlap = 65;        % 重叠长度
    cfg.stft.Nfft = 128;           % FFT点数

    % ==================== STFT RGB Colormap 参数 ====================
    % 是否生成多种 colormap 的 RGB 图像数据 (用于数据增强)
    % 复数STFT → abs() → [dB/线性] → 全局百分位归一化 → colormap → uint8 RGB [N, H, W, 3]
    % 输出文件: {split}_echo_stfts_rgb.mat (每种colormap保存为独立变量 rgb_<name>)
    cfg.output.save_stft_rgb = false;
    cfg.stft_rgb.colormaps = {'parula', 'jet', 'turbo', 'hot', 'gray'};
    cfg.stft_rgb.normalization = 'dB';               % 'dB'=20*log10 压缩动态范围 | 'linear'=原始幅度
    cfg.stft_rgb.percentile_range = [1, 99];          % 归一化百分位裁剪范围

    % ==================== CWD参数 (可选) ====================
    cfg.cwd.enabled = false;       % 是否使用CWD
    cfg.cwd.sigma = 0.5;           % CWD缩放因子

    % ==================== 持续时间谱参数 (Persistence Spectrum) ====================
    % method: 'custom' | 'matlab'
    cfg.persistence.method = 'custom';
    cfg.persistence.num_power_bins = 224;              % 单通道功率分箱 (兼容)
    cfg.persistence.channel_power_bins = [224, 112, 32]; % 多通道; [] 或标量 = 单通道
    cfg.persistence.target_size = [224, 224];          % 多通道输出 [freq, power]
    % custom 功率轴: 'fixed' 全库统一 | 'auto' 每目录按样本1估算
    cfg.persistence.power_range_mode = 'fixed';  % 'fixed' | 'auto'
    cfg.persistence.power_range_db = [0, 70];     % fixed: [lo, hi] dB
    cfg.persistence.power_percentile_lo = 1;     % auto: 下界百分位
    cfg.persistence.power_margin_db = 3;         % auto: 余量 (两端均 +margin)

    % ==================== 输出设置 ====================
    cfg.output.dataset_type = 'train';  % 'train', 'val', 'test'
    cfg.output.use_datetime = true;    % 是否使用日期时间作为目录名
    cfg.output.custom_dirname = '';   % 自定义目录名 (优先于日期时间)
    cfg.output.extract_features = false;  % 是否提取多域特征 (耗时较长时可关闭)
    cfg.output.save_stft = false;          % 是否保存STFT数据 (不需要STFT时可关闭以节省时间和磁盘)
    cfg.output.save_persistence = false;  % 是否计算并保存持续时间谱 (依赖STFT, 开启后自动计算STFT但不一定保存)

    % ==================== 样本生成参数 ====================
    cfg.generation.SAMPLE_NUM_S = 100;   % 单一干扰样本数
    cfg.generation.SAMPLE_NUM_M = 100;  % 混合干扰样本数
    cfg.generation.pos_range = [500, 4500]; % 目标位置随机范围

    % ==================== 组合干扰生成配置 ====================
    % 欺骗式干扰类型列表
    cfg.jamming.deceptive_types = {'CSJ', 'DFTJ', 'ISRJ', 'ISCJ', 'MISRJ', 'ISDJ', 'C&IJ', 'SMSPJ'};
    % 压制干扰类型列表
    cfg.jamming.suppressive_types = {'AJ', 'BJ', 'SJ', 'PJ', 'NCJ', 'NPJ', 'NFMJ', 'NPMJ', 'NAMJ'};

    % ===== 组合模式1: 压制+欺骗交叉组合 (笛卡尔积) =====
    % 要组合的欺骗干扰 (设为[]使用全部deceptive_types，设为{'none'}跳过此模式)
    cfg.jamming.combo_deceptive = {'CSJ', 'DFTJ', 'ISRJ', 'ISCJ', 'MISRJ', 'C&IJ', 'SMSPJ'};
    % 要组合的压制干扰 (设为[]使用全部suppressive_types)
    cfg.jamming.combo_suppressive = {'AJ', 'BJ', 'SJ', 'PJ', 'NCJ', 'NPJ', 'NFMJ', 'NPMJ', 'NAMJ'};

    % ===== 组合模式2: 任意两种干扰组合 (C(n,2)无重复) =====
    % 设为[]使用全部deceptive+suppressive，设为{'none'}跳过此模式
    % 自动避免: 自配对(DFTJ+DFTJ) 和 反向重复(DFTJ+CSJ vs CSJ+DFTJ)
    cfg.jamming.combo_types = {'none'};%{'CSJ', 'DFTJ', 'ISRJ', 'ISCJ', 'MISRJ', 'ISDJ', 'C&IJ', 'SMSPJ','AJ', 'BJ', 'SJ', 'PJ', 'NCJ', 'NPJ', 'NFMJ', 'NPMJ', 'NAMJ'};
    % ==================== 生成计划 ====================
    % 格式: {名称, 标签, 样本数}
    % 标签可以是单个数字或数组(混合干扰)
    cfg.generation_plan = {
        % 'RGPOJ',  cfg.generation.SAMPLE_NUM_S;
        % 'VGPOJ',  cfg.generation.SAMPLE_NUM_S;

        % ----- 欺骗干扰 -----
        'CSJ'  ,  cfg.generation.SAMPLE_NUM_S;
        'DFTJ' ,  cfg.generation.SAMPLE_NUM_S;
        'ISRJ' ,  cfg.generation.SAMPLE_NUM_S;
        'ISCJ' ,  cfg.generation.SAMPLE_NUM_S;
        'MISRJ',  cfg.generation.SAMPLE_NUM_S;
        'ISDJ' ,  cfg.generation.SAMPLE_NUM_S;
        'C&IJ' ,  cfg.generation.SAMPLE_NUM_S;
        'SMSPJ',  cfg.generation.SAMPLE_NUM_S;

        % ----- 压制干扰 -----
        'AJ'   ,  cfg.generation.SAMPLE_NUM_S;
        'BJ'   ,  cfg.generation.SAMPLE_NUM_S;
        'SJ'   ,  cfg.generation.SAMPLE_NUM_S;
        'PJ'   ,  cfg.generation.SAMPLE_NUM_S;
        'NCJ'  ,  cfg.generation.SAMPLE_NUM_S;
        'NPJ'  ,  cfg.generation.SAMPLE_NUM_S;
        'NFMJ' ,  cfg.generation.SAMPLE_NUM_S;
        'NPMJ' ,  cfg.generation.SAMPLE_NUM_S;
        'NAMJ' ,  cfg.generation.SAMPLE_NUM_S;


        % ----- 组合干扰 (手动指定) -----
        % {'CSJ','AJ'} ,  cfg.generation.SAMPLE_NUM_M;
    };

    % ----- 模式1: 自动生成压制+欺骗交叉组合 (笛卡尔积) -----
    if ~isempty(cfg.jamming.combo_deceptive) && ~strcmp(cfg.jamming.combo_deceptive{1}, 'none')
        combo_plan = generate_combination_plan_cross(cfg, cfg.jamming.combo_deceptive, cfg.jamming.combo_suppressive);
        cfg.generation_plan = [cfg.generation_plan; combo_plan];
    end

    % ----- 模式2: 自动生成任意两种干扰组合 (C(n,2)无重复) -----
    if ~isempty(cfg.jamming.combo_types) && ~strcmp(cfg.jamming.combo_types{1}, 'none')
        combo_plan = generate_combination_plan(cfg, cfg.jamming.combo_types);
        cfg.generation_plan = [cfg.generation_plan; combo_plan];
    end
end

% ==========================================================
% generate_combination_plan_cross - 模式1: 压制+欺骗交叉组合 (笛卡尔积)
% ==========================================================
function plan = generate_combination_plan_cross(cfg, deceptive_list, suppressive_list, sample_num)
    if nargin < 4
        sample_num = cfg.generation.SAMPLE_NUM_M;
    end
    if isempty(deceptive_list)
        deceptive_list = cfg.jamming.deceptive_types;
    end
    if isempty(suppressive_list)
        suppressive_list = cfg.jamming.suppressive_types;
    end

    plan = {};
    for i = 1:length(deceptive_list)
        for j = 1:length(suppressive_list)
            combination = {deceptive_list{i}, suppressive_list{j}};
            plan = [plan; {combination, sample_num}]; %#ok<AGROW>
        end
    end

    fprintf('生成交叉组合干扰计划 (%d 种组合 = %d×%d):\n', ...
        length(plan), length(deceptive_list), length(suppressive_list));
    for k = 1:length(plan)
        combo = plan{k,1};
        fprintf('  {''%s'', ''%s''} -> %d 样本\n', combo{1}, combo{2}, plan{k,2});
    end
end

% ==========================================================
% generate_combination_plan - 模式2: 任意两种干扰组合 (C(n,2)无重复)
% ==========================================================
function plan = generate_combination_plan(cfg, type_list, sample_num)
    if nargin < 3
        sample_num = cfg.generation.SAMPLE_NUM_M;
    end
    if isempty(type_list)
        type_list = [cfg.jamming.deceptive_types, cfg.jamming.suppressive_types];
    end

    n = length(type_list);
    plan = {};

    % 生成 C(n,2) 无重复组合: 仅 i < j，避免自配对和反向重复
    for i = 1:n
        for j = i+1:n
            combination = {type_list{i}, type_list{j}};
            plan = [plan; {combination, sample_num}]; %#ok<AGROW>
        end
    end

    fprintf('生成任意组合干扰计划 (%d 种组合 = C(%d,2)):\n', length(plan), n);
    for k = 1:length(plan)
        combo = plan{k,1};
        fprintf('  {''%s'', ''%s''} -> %d 样本\n', combo{1}, combo{2}, plan{k,2});
    end
end

