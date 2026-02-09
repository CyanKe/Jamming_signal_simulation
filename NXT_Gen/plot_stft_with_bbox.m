 % plot_stft_with_bbox.m - 绘制带有bounding box的STFT图
 %
 % 功能：
 % 1. 加载已生成的STFT数据和bounding box信息
 % 2. 绘制STFT频谱图
 % 3. 在图上叠加bounding box

 clear; clc; close all;

 % --- 1. 参数设置 ---
 params.fs = 80e6;        % 采样频率 80MHz
 params.fc = 40e6;        % 中心频率 40MHz
 params.B = 10e6;         % 带宽 10MHz
 params.taup = 20e-6;     % LFM脉宽 20us
 params.PRI = 100e-6;     % 脉冲重复间隔 100us

 % STFT参数
 params.stft_window = 128;
 params.stft_overlap = 64;
 params.stft_nfft = 64;

 % --- 2. 加载数据 ---
 % 数据目录（根据实际情况修改）
 data_dir = '260207/JNR_+50';  % 修改为你的数据目录
 if ~exist(data_dir, 'dir')
     error('数据目录不存在: %s', data_dir);
 end

 % 加载STFT数据、时域信号和bounding box
 stft_file = fullfile(data_dir, 'val_echo_stfts.mat');
 time_file = fullfile(data_dir, 'val_echo_times.mat');
 bbox_file = fullfile(data_dir, 'val_echo_bboxes.mat');

 fprintf('正在加载数据...\n');
 all_stfts = load(stft_file);
 all_times = load(time_file);
 all_bboxes = load(bbox_file);

 % 提取数据
 stfts = all_stfts.all_stfts;
 times = all_times.all_times;
 bboxes = all_bboxes.all_bboxes;

 fprintf('加载完成: %d 个样本\n', size(stfts, 1));

 % --- 3. 选择样本并绘制 ---
 sample_idx = 1;  % 选择第一个样本

 % 提取单个样本的数据
 S = squeeze(stfts(sample_idx, :, :));
 bbox_list = bboxes{sample_idx};

 fprintf('\n样本 %d 的信息:\n', sample_idx);
 fprintf('  STFT尺寸: %d x %d (频率x时间)\n', size(S, 1), size(S, 2));
 fprintf('  Bounding box数量: %d\n', size(bbox_list, 1));

 % --- 4. 计算STFT的频率和时间轴 ---
 % 频率轴
 freq_axis = linspace(-params.fs/2, params.fs/2, params.stft_nfft);

 % 时间轴（STFT的时间bin对应的时间点）
 PRI = params.PRI;
 stft_time_bins = size(S, 2);
 time_axis = linspace(0, PRI, stft_time_bins);

 % --- 5. 绘制STFT图 ---
 figure('Position', [100, 100, 1200, 500]);

 % 子图1: STFT幅度图
 subplot(1, 2, 1);
 imagesc(time_axis * 1e6, freq_axis / 1e6, 20*log10(abs(S) + eps));
 axis xy;
 colormap('jet');
 colorbar;
 title('STFT幅度谱 (dB)');
 xlabel('时间 (μs)');
 ylabel('频率 (MHz)');
 clim([max(20*log10(abs(S(:)) + eps)) - 60, max(20*log10(abs(S(:)) + eps))]);

 % 子图2: STFT幅度图 + bounding box
 subplot(1, 2, 2);
 imagesc(time_axis * 1e6, freq_axis / 1e6, 20*log10(abs(S) + eps));
 axis xy;
 colormap('jet');
 colorbar;
 title('STFT幅度谱 + Bounding Box');
 xlabel('时间 (μs)');
 ylabel('频率 (MHz)');
 clim([max(20*log10(abs(S(:)) + eps)) - 60, max(20*log10(abs(S(:)) + eps))]);

 % 绘制bounding box
 hold on;
 for i = 1:size(bbox_list, 1)
     % bbox格式: [freq_idx_min, time_idx_min, freq_idx_max, time_idx_max]
     freq_idx_min = bbox_list(i, 1);
     time_idx_min = bbox_list(i, 2);
     freq_idx_max = bbox_list(i, 3);
     time_idx_max = bbox_list(i, 4);

     % 转换为实际坐标
     x_min = time_axis(time_idx_min) * 1e6;
     x_max = time_axis(time_idx_max) * 1e6;
     y_min = freq_axis(freq_idx_min) / 1e6;
     y_max = freq_axis(freq_idx_max) / 1e6;

     % 绘制矩形框
     rectangle('Position', [x_min, y_min, x_max - x_min, y_max - y_min], ...
               'EdgeColor', 'yellow', 'LineWidth', 2, 'LineStyle', '-');

     % 添加标签
     text(x_min, y_max + 0.5, sprintf('BB%d', i), ...
          'Color', 'yellow', 'FontSize', 10, 'FontWeight', 'bold');
 end
 hold off;

 % --- 6. 绘制时域信号图（可选）---
 figure('Position', [100, 650, 1200, 300]);

 % 提取时域信号
 signal = times(sample_idx, 1:params.PRI_samp);
 t_signal = (0:length(signal)-1) / params.fs * 1e6;

 subplot(1, 2, 1);
 plot(t_signal, real(signal), 'b-', 'LineWidth', 1);
 title('时域信号 - 实部');
 xlabel('时间 (μs)');
 ylabel('幅度');
 grid on;

 subplot(1, 2, 2);
 plot(t_signal, imag(signal), 'r-', 'LineWidth', 1);
 title('时域信号 - 虚部');
 xlabel('时间 (μs)');
 ylabel('幅度');
 grid on;

 % --- 7. 输出bounding box详细信息 ---
 if ~isempty(bbox_list)
     fprintf('\nBounding box详细信息:\n');
     fprintf('  [freq_idx_min, time_idx_min, freq_idx_max, time_idx_max]\n');
     for i = 1:size(bbox_list, 1)
         fprintf('  BB%d: %s\n', i, mat2str(bbox_list(i, :)));

         % 转换为实际物理量
         freq_idx_min = bbox_list(i, 1);
         time_idx_min = bbox_list(i, 2);
         freq_idx_max = bbox_list(i, 3);
         time_idx_max = bbox_list(i, 4);

         freq_min = freq_axis(freq_idx_min) / 1e6;
         freq_max = freq_axis(freq_idx_max) / 1e6;
         time_min = time_axis(time_idx_min) * 1e6;
         time_max = time_axis(time_idx_max) * 1e6;

         fprintf('      频率范围: %.2f ~ %.2f MHz\n', freq_min, freq_max);
         fprintf('      时间范围: %.2f ~ %.2f μs\n', time_min, time_max);
     end
 end

 fprintf('\n绘图完成！\n');