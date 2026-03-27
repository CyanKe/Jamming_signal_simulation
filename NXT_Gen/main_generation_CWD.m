% ==========================================================
% main_generation_CWD.m - 使用 CWD 的主数据生成脚本
% ==========================================================
clear; clc; close all;
tic
% --- 1. 公共参数设置 ---
params.fs = 80e6;        % 采样频率 100MHz
params.fc = 40e6;        % 中心频率 40MHz
params.B = 20e6;         % 带宽    10MHz
params.taup = 20e-6;     % LFM 脉宽 20us
params.Np = 1;           % 脉冲个数 1  ->只在单个 PRI 内测试
params.PRI = 100e-6;     % 脉冲重复间隔 us
params.SNR = 15;         % 信噪比
JNR_values = 15;    % 干噪比范围 dB
params.numClasses = 16;    % 基础九种干扰
SAMPLE_NUM_S = 2;
SAMPLE_NUM_M = 1;
params.pos = 1000+randi([0 6000]);      %在 PRI 中第 5000 点处

% --- 2. 生成计划 ---
generation_plan = {
    % 欺骗干扰
    % 'DFTJ' , 1,  SAMPLE_NUM_S;
    % 'ISRJ' , 2,  SAMPLE_NUM_S;
    % 'SMSPJ', 10, SAMPLE_NUM_S;
    % 'C&IJ' , 11, SAMPLE_NUM_S;
    % 'CSJ'  , 15, SAMPLE_NUM_S;

    % 压制干扰
    % 'AJ'   , 5, SAMPLE_NUM_S;
    % 'BJ'   , 6, SAMPLE_NUM_S;
    % 'SJ'   , 7, SAMPLE_NUM_S;
    % 'NCJ'  , 8, SAMPLE_NUM_S;
    % 'NPJ'  , 9, SAMPLE_NUM_S;
    % 'NFMJ' , 12, SAMPLE_NUM_S;
    % 'NPMJ' , 13, SAMPLE_NUM_S;
    % 'NAMJ' , 14, SAMPLE_NUM_S;
    % 'PJ'   , 16, SAMPLE_NUM_S;
    % 'DFTJ+AJ',  [1,5] , SAMPLE_NUM_M;
    % 'DFTJ+BJ',  [1,6] , SAMPLE_NUM_M;
    % 'DFTJ+SJ',  [1,7] , SAMPLE_NUM_M;
    'DFTJ+NCJ', [1,8] , SAMPLE_NUM_M;
    'DFTJ+NPJ', [1,9] , SAMPLE_NUM_M;
    'DFTJ+NFMJ',[1,12] , SAMPLE_NUM_M;
    'DFTJ+NPMJ',[1,13] , SAMPLE_NUM_M;
    'DFTJ+NAMJ',[1,14] , SAMPLE_NUM_M;
    'DFTJ+PJ',  [1,16] , SAMPLE_NUM_M;
    };

% --- 3. 执行生成 ---
[tx, params] = generate_0base_signal(params);
toc

%% 循环生成每种干扰
len = size(generation_plan, 1);
SAMPLE_NUM = sum( [generation_plan{:, 3}])
tic
for current_jnr = JNR_values
    % 初始化数据容器
    current_jnr
    all_times = zeros(SAMPLE_NUM,params.PRI_samp);
    all_label = zeros(SAMPLE_NUM,params.numClasses);
    Nwin = 256; Noverlap = 240;
    Step = Nwin - Noverlap;
    N_cols = floor((params.N_total - Noverlap) / Step);
    Nfft = 256;
    all_cwds = zeros(SAMPLE_NUM, Nfft, N_cols);  % CWD 结果 [频率，时间]
    point_l = 1;
    for i = 1:len
        jam_type = generation_plan{i, 1};
        label = generation_plan{i, 2};
        num_to_generate = generation_plan{i, 3};

        Aj = 10^(current_jnr/20);
        % 创建当前 JNR 值的子文件夹 - CWD 输出到新目录
        current_datetime = datetime('now', 'Format', 'yyMMdd');
        time_str = char(current_datetime);
        snr_output_dir = fullfile(time_str, sprintf('JNR_%+d', current_jnr));
        cwd_output_dir = fullfile(time_str, 'CWD_features', sprintf('JNR_%+d', current_jnr));

        if ~exist(snr_output_dir, 'dir')
            mkdir(snr_output_dir);
        end
        if ~exist(cwd_output_dir, 'dir')
            mkdir(cwd_output_dir);
        end

        [new_times, new_label] = multi_generation(label,params,current_jnr,num_to_generate);
        if i ~= 1
            point_l = point_r + 1;
        end
        point_r = point_l + num_to_generate-1;
        all_times(point_l:point_r,:) = new_times;
        all_label(point_l:point_r,:) = new_label;
    end

    % === 使用 CWD 代替 STFT (原代码 147-150 行) ===
    % CWD 参数说明:
    %   - 输入信号：all_times(i, 1:params.PRI_samp)
    %   - fs: 采样频率
    %   - sigma: 缩放因子=1 (论文推荐值，用于交叉项抑制)
    %   - n_points: 输出时间点数=124 (与 STFT 保持一致)
    %   - f_points: 输出频率点数=64 (与 STFT 保持一致)
    for i = 1:SAMPLE_NUM
        [S,~,~] = spectrogram(all_times(i,1:params.PRI_samp),Nwin,Noverlap,Nfft,params.fs, 'centered');
        % [C,F,T] = CWD(all_times(i, 1:params.PRI_samp), params.fs, 1, 124, 64);
        % [W,T,F] = wvd(all_times(i, 1:params.PRI_samp), params.fs,"smoothedPseudo");
        [C,F,T] = choiwilliams(all_times(i,1:params.PRI_samp),Nwin,Noverlap,Nfft,params.fs, 'centered', 'Sigma', 0.5);
        all_cwds(i,:,:) = single(C);
        all_stfts(i,:,:) = single(S);
    end

    % STFT 输出路径 (保留原有)
    path_stfts = fullfile(snr_output_dir, 'val_echo_stfts.mat');
    path_times = fullfile(snr_output_dir, 'val_echo_times.mat');
    path_label = fullfile(snr_output_dir, 'val_echo_label.mat');

    % CWD 输出路径 (新文件夹)
    path_cwds = fullfile(cwd_output_dir, 'val_echo_cwds.mat');
    path_cwd_times = fullfile(cwd_output_dir, 'val_echo_times.mat');
    path_cwd_label = fullfile(cwd_output_dir, 'val_echo_label.mat');

    % 保存 CWD 结果 (新增 - 新文件夹)
    save(path_cwds, 'all_cwds', '-v7.3');
    save(path_cwd_times, 'all_times', '-v7.3');
    save(path_cwd_label, 'all_label', '-v7.3');
end
toc

figure(1)
for i = 1:SAMPLE_NUM
    subplot(2,SAMPLE_NUM,i)
    imagesc(T*1e6, F/1e6, abs((squeeze(all_cwds(i,:,:)))) + eps);
    % colormap(turbo)
    axis xy;
    xlabel('时间 (us)');
    ylabel('频率 (MHz)');
    grid on;

    subplot(2,SAMPLE_NUM,SAMPLE_NUM+i)
    imagesc(T*1e6, F/1e6, abs((squeeze(all_stfts(i,:,:)))) + eps);
    % colormap(turbo)
    axis xy;
    xlabel('时间 (us)');
    ylabel('频率 (MHz)');
    grid on;
end