% ==========================================================
% process_rdm.m - 对雷达回波信号进行距离多普勒处理
%
% 输入:
%   rx     - (1 x N_total) 的复数行向量，代表ADC采集到的原始时域回波信号
%   params - 包含雷达系统参数和预计算值的结构体
%            需要包含以下字段:
%            .PRI_samp  - 每个PRI的采样点数
%            .Np        - 脉冲个数
%            .lfm       - (1 x Ntau) 的参考LFM信号
%            .fs        - 采样频率
%            .fc        - 中心频率
%            .PRI       - 脉冲重复间隔
%
% 输出:
%   rdm_db        - (PRI_samp x Np) 的矩阵，表示以dB为单位的距离多普勒图
%   range_axis    - (1 x PRI_samp) 的向量，表示距离轴 (m)
%   velocity_axis - (1 x Np) 的向量，表示速度轴 (m/s)
% ==========================================================
function [rdm_db, range_axis, velocity_axis] = process_rdm(rx, params)

    % --- 物理常量 ---
    c = 3e8; % 光速 (m/s)

    %% 1. 数据矩阵化
    % 将1D回波信号 rx 变为 2D 矩阵
    % 矩阵的每一列是一个PRI的回波，每一行是快时间采样
    if length(rx) ~= params.PRI_samp * params.Np
        error('输入信号 rx 的长度与参数不匹配!');
    end
    rx_matrix = reshape(rx, params.PRI_samp, params.Np);

    %% 2. 距离处理 (脉冲压缩)
    % 准备匹配滤波器 (在频域中操作)
    % 对参考信号补零以匹配每个PRI的长度，然后做FFT并取共轭
    matched_filter_fft = conj(fft(params.lfm, params.PRI_samp));
    
    pc_matrix = zeros(size(rx_matrix)); % 存储脉冲压缩后的结果
    for k = 1:params.Np
        % 对每一列（每个脉冲的回波）进行FFT
        pulse_fft = fft(rx_matrix(:, k), params.PRI_samp);
        % 在频域进行匹配滤波
        compressed_fft = pulse_fft .* matched_filter_fft.';
        % IFFT返回到时域（现在是距离域）
        pc_matrix(:, k) = ifft(compressed_fft);
    end

    %% 3. 多普勒处理 (沿慢时间轴FFT)
    % 为了减少频谱泄露，先加窗（例如汉宁窗）
    window = hanning(params.Np).'; % 转置为行向量以匹配矩阵维度
    pc_matrix_windowed = pc_matrix .* window;

    % 对每一行进行FFT，得到距离多普勒矩阵
    rdm = fft(pc_matrix_windowed, params.Np, 2); % 2表示沿第二个维度(慢时间)进行FFT

    %% 4. 数据整理与坐标轴计算
    % 将0多普勒移到中心
    rdm_shifted = fftshift(rdm, 2); 
    
    % 将复数幅度转换为分贝(dB)值
    rdm_db = 20 * log10(abs(rdm_shifted));
    
    % 创建距离轴
    ts = 1 / params.fs;
    range_axis = (0:params.PRI_samp-1) * ts * c / 2;
    
    % 创建速度轴
    lambda = c / params.fc;
    PRF = 1 / params.PRI;
    doppler_freq_axis = (-params.Np/2 : params.Np/2-1) * (PRF / params.Np);
    velocity_axis = doppler_freq_axis * lambda / 2;

end
