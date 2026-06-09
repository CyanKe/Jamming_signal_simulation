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
    cfg.jamming.nfmj.BJ_range = [15, 15];    % 干扰带宽范围 MHz
    cfg.jamming.nfmj.random_Fj = true;

    % NPMJ (噪声调相干扰)
    cfg.jamming.npmj.BJ_range = [15, 15];    % 干扰带宽范围 MHz
    cfg.jamming.npmj.random_Fj = true;

    % NAMJ (噪声调幅干扰)
    cfg.jamming.namj.BJ_range = [15, 15];    % 干扰带宽范围 MHz
    cfg.jamming.namj.random_Fj = true;

    % ==================== STFT参数 ====================
    cfg.stft.Nwin = 128;           % 窗口长度
    cfg.stft.Noverlap = 65;        % 重叠长度
    cfg.stft.Nfft = 128;           % FFT点数

    % ==================== CWD参数 (可选) ====================
    cfg.cwd.enabled = false;       % 是否使用CWD
    cfg.cwd.sigma = 0.5;           % CWD缩放因子

    % ==================== 输出设置 ====================
    cfg.output.dataset_type = 'test';  % 'train', 'val', 'test'
    cfg.output.use_datetime = true;    % 是否使用日期时间作为目录名
    cfg.output.custom_dirname = '';   % 自定义目录名 (优先于日期时间)
    cfg.output.extract_features = false;  % 是否提取多域特征 (耗时较长时可关闭)
    
    % ==================== 样本生成参数 ====================
    cfg.generation.SAMPLE_NUM_S = 100;   % 单一干扰样本数
    cfg.generation.SAMPLE_NUM_M = 100;  % 混合干扰样本数
    cfg.generation.pos_range = [500, 4500]; % 目标位置随机范围

    % ==================== 组合干扰生成配置 ====================
    % 欺骗式干扰类型列表
    cfg.jamming.deceptive_types = {'CSJ', 'DFTJ', 'ISRJ', 'ISCJ', 'MISRJ', 'ISDJ', 'C&IJ', 'SMSPJ'};
    % 压制干扰类型列表
    cfg.jamming.suppressive_types = {'AJ', 'BJ', 'SJ', 'PJ', 'NCJ', 'NPJ', 'NFMJ', 'NPMJ', 'NAMJ'};

    % 要组合的欺骗干扰 (设为[]使用全部，设为{'none'}跳过自动组合)
    cfg.jamming.combo_deceptive = {'CSJ', 'DFTJ', 'ISRJ', 'ISCJ', 'MISRJ', 'C&IJ', 'SMSPJ'};
    % 要组合的压制干扰 (设为[]使用全部)
    cfg.jamming.combo_suppressive = {'AJ', 'BJ', 'SJ', 'PJ', 'NCJ', 'NPJ', 'NFMJ', 'NPMJ', 'NAMJ'};

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

    % ----- 自动生成组合干扰 (基于combo_deceptive和combo_suppressive) -----
    if ~isempty(cfg.jamming.combo_deceptive) && ~strcmp(cfg.jamming.combo_deceptive{1}, 'none')
        combo_plan = generate_combination_plan(cfg, cfg.jamming.combo_deceptive, cfg.jamming.combo_suppressive);
        cfg.generation_plan = [cfg.generation_plan; combo_plan];
    end
end

% ==========================================================
% generate_combination_plan - 自动生成欺骗+压制组合干扰计划
% ==========================================================
% 用法:
%   plan = generate_combination_plan(cfg, {'CSJ', 'DFTJ'}, {'AJ'})
%   plan = generate_combination_plan(cfg, {'CSJ', 'DFTJ'}, {'AJ'}, 100)  % 指定样本数
%   plan = generate_combination_plan(cfg, [], {'AJ'})  % 使用所有欺骗干扰
%   plan = generate_combination_plan(cfg, {'CSJ'}, [])  % 使用所有压制干扰
%
% 返回格式: cell array，可直接合并到generation_plan中
% 例如: cfg.generation_plan = [cfg.generation_plan; plan];
% ==========================================================
function plan = generate_combination_plan(cfg, deceptive_list, suppressive_list, sample_num)
    % 如果未指定样本数，使用默认混合干扰样本数
    if nargin < 4
        sample_num = cfg.generation.SAMPLE_NUM_M;
    end

    % 如果deceptive_list为空，使用所有欺骗干扰
    if isempty(deceptive_list)
        deceptive_list = cfg.jamming.deceptive_types;
    end

    % 如果suppressive_list为空，使用所有压制干扰
    if isempty(suppressive_list)
        suppressive_list = cfg.jamming.suppressive_types;
    end

    % 生成所有两两组合
    plan = {};
    for i = 1:length(deceptive_list)
        for j = 1:length(suppressive_list)
            % 组合格式: {cell数组, 样本数}
            combination = {deceptive_list{i}, suppressive_list{j}};
            plan = [plan; {combination, sample_num}]; %#ok<AGROW>
        end
    end

    % 打印生成的计划
    fprintf('生成组合干扰计划 (%d 种组合):\n', length(plan));
    for k = 1:length(plan)
        combo = plan{k,1};
        fprintf('  {''%s'', ''%s''} -> %d 样本\n', combo{1}, combo{2}, plan{k,2});
    end
end

