% ==========================================================
% process_rdm_with_keystone.m - 对雷达回波信号进行距离多普勒处理，并集成Keystone变换
%
% 输入:
%   rx     - (1 x N_total) 的复数行向量，代表ADC采集到的原始时域回波信号
%   params - 包含雷达系统参数和预计算值的结构体
%            需要包含以下字段:
%            .PRI_samp  - 每个PRI的采样点数 (快时间样本数)
%            .Np        - 脉冲个数 (慢时间样本数)
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
function [rdm_db, range_axis, velocity_axis] = process_rdm_with_keystone(rx, params)

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

    %% 3. Keystone 变换 (新增步骤)
    % 对距离压缩后的数据进行Keystone变换以校正距离徙动
    fprintf('正在执行Keystone变换以校正距离徙动...\n');
    pc_matrix_keystone = keystone_transform(pc_matrix, params.fc, params.fs, params.Np);
    fprintf('Keystone变换完成。\n');

    %% 4. 多普勒处理 (沿慢时间轴FFT)
    % 为了减少频谱泄露，先加窗（例如汉宁窗）
    window = hanning(params.Np).'; % 转置为行向量以匹配矩阵维度
    % *** 注意：现在对经过Keystone校正后的矩阵进行操作 ***
    pc_matrix_windowed = pc_matrix_keystone .* window;

    % 对每一行进行FFT，得到距离多普勒矩阵
    rdm = fft(pc_matrix_windowed, params.Np, 2); % 2表示沿第二个维度(慢时间)进行FFT

    %% 5. 数据整理与坐标轴计算
    % 将0多普勒移到中心
    rdm_shifted = fftshift(rdm, 2); 
    
    % 将复数幅度转换为分贝(dB)值
    rdm_db = 20 * log10(abs(rdm_shifted) + 1e-6); % 加一个小值避免log(0)
    
    % 创建距离轴
    ts = 1 / params.fs;
    range_axis = (0:params.PRI_samp-1) * ts * c / 2;
    
    % 创建速度轴
    lambda = c / params.fc;
    PRF = 1 / params.PRI;
    doppler_freq_axis = (-params.Np/2 : params.Np/2-1) * (PRF / params.Np);
    velocity_axis = doppler_freq_axis * lambda / 2;

end

% ==========================================================
% Keystone 变换子函数
% ==========================================================
function pc_matrix_out = keystone_transform(pc_matrix_in, fc, fs, Np)
    % 输入:
    %   pc_matrix_in - (N_range x Np) 距离压缩后的矩阵
    %   fc           - 中心频率 (Hz)
    %   fs           - 采样频率 (Hz)
    %   Np           - 脉冲数
    % 输出:
    %   pc_matrix_out - (N_range x Np) Keystone变换后的矩阵

    [N_range, ~] = size(pc_matrix_in);

    % --- 1. 沿快时间/距离维FFT，进入距离频域-慢时间域 ---
    % 使用fftshift将零频移到中心，便于后续处理
    S_ft = fftshift(fft(pc_matrix_in, [], 1), 1);
    
    % --- 2. 准备Keystone变换参数 ---
    % 创建快时间频率轴 (对应于fftshift后的顺序)
    fast_freq_axis = (-N_range/2 : N_range/2 - 1) * (fs / N_range);
    
    % 创建慢时间轴 (以CPI中心为0)
    if mod(Np, 2) == 0
        slow_time_axis_in = (-Np/2 : Np/2 - 1);
    else
        slow_time_axis_in = -(Np-1)/2 : (Np-1)/2;
    end

    % 初始化输出矩阵
    S_kt = zeros(size(S_ft));
    
    % --- 3. 遍历每个频率单元，进行慢时间重采样 ---
    for k = 1:N_range
        % 当前快时间频率
        fk = fast_freq_axis(k);
        
        denominator = fc + fk;
        if abs(denominator) < 1e-9 % 增加一个更稳健的检查
            resample_factor = 1; % 如果分母接近0，则不进行重采样
        else
            resample_factor = fc / denominator;
        end
        
        % 定义新的慢时间轴
        slow_time_axis_new = slow_time_axis_in * resample_factor;
        
        % 获取当前频率单元的慢时间信号
        slow_time_signal = S_ft(k, :);
        
        % 使用插值进行重采样
        % interp1是MATLAB内置函数，'spline'插值效果好且速度快
        % 注意：对于超出原始范围的点，interp1会返回NaN，需填充为0
        resampled_signal = interp1(slow_time_axis_new, slow_time_signal, slow_time_axis_in, 'spline', 0);

        % 将重采样后的信号放回新矩阵
        S_kt(k, :) = resampled_signal;
    end
    
    % --- 4. 沿快时间/距离维IFFT，返回距离时域-慢时间域 ---
    % 先ifftshift将零频移回原位，再IFFT
    pc_matrix_out = ifft(ifftshift(S_kt, 1), [], 1);
end

