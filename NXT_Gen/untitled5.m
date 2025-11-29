clear; clc; close all;

% 确保 generate_0base_signal.m 和 process_rdm.m 在MATLAB路径中

%% 1. 定义系统和目标参数
% --- 雷达系统参数 ---
params.fs = 80e6;       % 采样频率 80MHz
params.fc = 40e3;       % 中心频率 (用于计算多普勒)
params.B = 10e6;        % 带宽 10MHz
params.taup = 10e-6;    % LFM脉宽 10us
params.Np = 16;         % 脉冲个数 16
params.PRI = 200e-6;    % 脉冲重复间隔 200us
params.SNR = 20;        % 信噪比 (dB)
params.pos = 0e4*2;        % 发射脉冲在PRI内的起始位置
params.pos = 1;%round(params.pos/3e8*params.fs);
% --- 模拟目标参数 ---
target_R = 10000;       % 目标距离 (m)
target_v = 1000;         % 目标速度 (m/s, 正值表示远离雷达)

% --- 物理常量 ---
c = 3e8;                % 光速 (m/s)

%% 2. 生成发射信号与模拟回波信号
% (调用 `generate_0base_signal` 函数)
[tx, params] = generate_0base_signal(params);
% 生成纯净的真实目标回波
As = 10^(params.SNR/20); % 根据信噪比计算幅度
pure_echo = As * tx;

%% 3. 生成RGPO干扰信号
% 调用您提供的函数
% 注意：您的函数名是 generate_3rgpo_jamming，这里直接使用
% 我们只取第一个样本，因为您的函数可以生成多个样本
jam_params = params;
jam_params.JNR = 20; % 距离假目标干扰
jam_params.v = 5e4;           % 拖引速率
pure_jam_all = generate_3rgpo_jamming(tx, jam_params, 1);
pure_jam = pure_jam_all(1, :);

%% 4. 混合信号 (回波 + 干扰)
% 为了清晰显示，暂时不加噪声
rx_signal = pure_echo + pure_jam;

%% 5. 创建匹配滤波器并进行脉冲压缩
% 匹配滤波器是发射信号单个脉冲的时间反转共轭
matched_filter = conj(flip(tx(1,params.pos:params.pos+params.Ntau-1)));

% 准备一个矩阵来存储所有脉冲的脉压结果
pc_results = zeros(params.Np, params.PRI_samp + params.Ntau - 1);

fprintf('正在对每个脉冲进行脉冲压缩...\n');
for p = 0:(params.Np-1)
    % 提取当前PRI的接收信号
    pri_start_idx = p * params.PRI_samp + 1;
    pri_end_idx = (p+1) * params.PRI_samp;
    current_pri_signal = rx_signal(pri_start_idx:pri_end_idx);
    
    % 进行脉冲压缩 (通过卷积实现)
    compressed_pulse = conv(current_pri_signal, matched_filter, 'full');
    
    % 存储结果
    pc_results(p+1, :) = abs(compressed_pulse);
end
fprintf('脉冲压缩完成！\n');

%% 6. 可视化结果

% --- 可视化方式一：绘制几个代表性脉冲的脉压结果 ---
figure('Name', '代表性脉冲的脉压结果');
set(gcf, 'Position', [100, 100, 800, 600]);

% 选择要绘制的脉冲索引
pulses_to_plot = [1:4:16]; % 早期、中期、晚期

for i = 1:length(pulses_to_plot)
    pulse_idx = pulses_to_plot(i);
    subplot(length(pulses_to_plot), 1, i);
    
    % 距离轴
    range_axis = (0:size(pc_results, 2)-1) * (c / (2 * params.fs));
    
    plot(range_axis/1000, pc_results(pulse_idx, :)); % 转换为公里
    grid on;
    title(['第 ', num2str(pulse_idx), ' 个脉冲的脉压结果']);
    xlabel('距离 (km)');
    ylabel('幅度');
    
    % 找到峰值位置用于标注
    [~, true_loc] = max(abs(conv(tx(1, params.pos:params.pos+params.Ntau-1), matched_filter)));
    xlim([params.pos/1000 - 2, params.pos/1000 + 20]); % 动态调整显示范围
    hold on;
    % 标注真实目标
    stem(range_axis(true_loc)/1000, max(pc_results(pulse_idx,:)), 'r', 'filled', 'Marker','v', 'DisplayName', '真实目标');
    legend;
end

% --- 可视化方式二：绘制所有脉冲的二维热力图 (瀑布图) ---
figure('Name', 'RGPO脉冲压缩结果热力图');
set(gcf, 'Position', [950, 100, 800, 600]);

% 我们只关心目标附近的一小段距离，所以截取结果进行显示
[~, peak_loc] = max(pc_results(1,:));
range_window = peak_loc-50 : peak_loc+800; % 根据拖引速度和脉冲数调整窗口大小

% 创建距离轴和脉冲数轴
range_axis_km = (range_window-1) * (c / (2*params.fs)) / 1000;
pulse_axis = 1:params.Np;

imagesc(range_axis_km, pulse_axis, pc_results(:, range_window));
colorbar;
xlabel('距离 (km)');
ylabel('脉冲序号 (慢时间)');
title('距离拖引干扰(RGPO)脉冲压缩结果');
ax = gca;
ax.YDir = 'normal'; % 让Y轴从下到上增加

