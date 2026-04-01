% ==========================================================
% config_example.m - 全局配置文件
% 用于数据生成的参数设置，与生成函数解耦
% ==========================================================

function cfg = config_example()
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
    cfg.jamming.numClasses = 16;    % 基础干扰类型数量
    cfg.jamming.JNR_values = 10;   % 干噪比范围 dB (可以是标量或数组如 0:5:20)

    % ==================== 各干扰类型的特定参数 ====================
    % RGPO (距离拖引干扰)
    cfg.jamming.rgpo.v = 5e5;       % 拖引速率

    % VGPO (速度拖引干扰)
    cfg.jamming.vgpo.pull = 5e5;    % 拖引频率 Hz

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

    % ==================== 样本生成参数 ====================
    cfg.generation.SAMPLE_NUM_S = 20;   % 单一干扰样本数
    cfg.generation.SAMPLE_NUM_M = 20;  % 混合干扰样本数
    cfg.generation.pos_range = [500, 4500]; % 目标位置随机范围

    % ==================== STFT参数 ====================
    cfg.stft.Nwin = 128;           % 窗口长度
    cfg.stft.Noverlap = 93;        % 重叠长度
    cfg.stft.Nfft = 224;           % FFT点数

    % ==================== CWD参数 (可选) ====================
    cfg.cwd.enabled = false;       % 是否使用CWD
    cfg.cwd.sigma = 0.5;           % CWD缩放因子

    % ==================== 输出设置 ====================
    cfg.output.dataset_type = 'val';  % 'train', 'val', 'test'
    cfg.output.use_datetime = true;    % 是否使用日期时间作为目录名
    cfg.output.custom_dirname = '';   % 自定义目录名 (优先于日期时间)

    % ==================== 生成计划 ====================
    % 格式: {名称, 标签, 样本数}
    % 标签可以是单个数字或数组(混合干扰)
    cfg.generation_plan = {
        % ----- 欺骗干扰 -----
        'DFTJ' ,  1, cfg.generation.SAMPLE_NUM_S;
        'ISRJ' ,  2, cfg.generation.SAMPLE_NUM_S;
        'RGPOJ',  3, cfg.generation.SAMPLE_NUM_S;
        'VGPOJ',  4, cfg.generation.SAMPLE_NUM_S;
        'SMSPJ', 10, cfg.generation.SAMPLE_NUM_S;
        'C&IJ' , 11, cfg.generation.SAMPLE_NUM_S;
        'CSJ'  , 15, cfg.generation.SAMPLE_NUM_S;

        % ----- 压制干扰 -----
        'AJ'   ,  5, cfg.generation.SAMPLE_NUM_S;
        'BJ'   ,  6, cfg.generation.SAMPLE_NUM_S;
        'SJ'   ,  7, cfg.generation.SAMPLE_NUM_S;
        'NCJ'  ,  8, cfg.generation.SAMPLE_NUM_S;
        'NPJ'  ,  9, cfg.generation.SAMPLE_NUM_S;
        'NFMJ' , 12, cfg.generation.SAMPLE_NUM_S;
        'NPMJ' , 13, cfg.generation.SAMPLE_NUM_S;
        'NAMJ' , 14, cfg.generation.SAMPLE_NUM_S;
        'PJ'   , 16, cfg.generation.SAMPLE_NUM_S;

        % ----- 混合干扰 -----
        'RGPO+AJ', [3,5] , cfg.generation.SAMPLE_NUM_M;
        'VGPO+AJ', [4,5] , cfg.generation.SAMPLE_NUM_M;
        'DFTJ+AJ', [1,5] , cfg.generation.SAMPLE_NUM_M;
        'ISRJ+AJ', [2,5] , cfg.generation.SAMPLE_NUM_M;
        'SMSPJ+AJ', [10,5], cfg.generation.SAMPLE_NUM_M;
        'C&IJ+AJ', [11,5] , cfg.generation.SAMPLE_NUM_M;
        'CSJ+AJ'  , [15,5] , cfg.generation.SAMPLE_NUM_M;
    };
end

