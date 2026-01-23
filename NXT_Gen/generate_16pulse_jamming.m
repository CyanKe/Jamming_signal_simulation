function [pure_jam] = generate_16pulse_jamming(tx, params, data_num)
% GENERATE_PULSE_JAMMING 生成脉冲干扰 (Pulse Jamming, PJ)
%
% 输入:
%   tx        - 发射信号矩阵 (用于提取时间轴结构)
%   params    - 参数结构体，必须包含:
%               fs        - 采样率 (Hz)
%               N_total   - 总采样点数
%               JNR       - 干噪比 (dB)
%               Np        - 重复脉冲数 (干扰脉冲重复次数)
%               Ntau      - 单个干扰脉冲宽度 (采样点数)
%               freq_j    - 干扰载波频率 (Hz) [新增参数]
%               duty_cycle- 占空比 (0~1, 可选，默认0.5)
%               phase_j   - 干扰初始相位 (弧度, 可选，默认随机)
%               pulse_type- 脉冲类型 ('rect', 'raise_cos', 'hamming', 'kaiser')
%   data_num  - 生成的样本数量
%
% 输出:
%   pure_jam  - 生成的纯干扰信号矩阵 (data_num x N_total)

    % --- 参数解包 ---
    fs = params.fs;
    N_total = params.N_total;
    Aj = 10^(params.JNR/20); % 干扰幅度
    Np = params.Np;          % 重复次数
    Ntau = params.Ntau;      % 单个干扰脉冲宽度
    freq_j = params.freq_j;  % 干扰载频
    
    % 可选参数
    if isfield(params, 'duty_cycle')
        duty_cycle = params.duty_cycle;
    else
        duty_cycle = 0.5; % 默认50%占空比
    end
    
    if isfield(params, 'phase_j')
        phase_j = params.phase_j;
    else
        phase_j = rand() * 2 * pi; % 随机初始相位
    end
    
    if isfield(params, 'pulse_type')
        pulse_type = params.pulse_type;
    else
        pulse_type = 'rect';
    end

    % --- 初始化 ---
    pure_jam = zeros(data_num, N_total);
    
    % 计算脉冲重复间隔 (PRI) 和 空闲时间 (LOI)
    % 假设每个干扰脉冲占据 Ntau 长度，然后空闲一段时间
    pulse_total_len = floor(Ntau / duty_cycle);
    
    for m = 1:data_num
        % 生成时间轴
        t = (0 : pulse_total_len - 1) / fs;
        
        % --- 1. 生成调制载波 (高频正弦) ---
        carrier = cos(2 * pi * freq_j * t + phase_j);
        
        % --- 2. 生成矩形/加窗脉冲包络 ---
        envelope = zeros(1, pulse_total_len);
        
        % 定义脉冲持续时间内的索引
        on_idx = 1:Ntau;
        
        switch pulse_type
            case 'rect'
                % 矩形脉冲 (Rectangular)
                envelope(on_idx) = 1.0;
                
            case 'raise_cos'
                % 升余弦脉冲 (Raised Cosine)
                % 能够减少带外频谱扩散
                alpha = 0.22; % 滚降系数
                tau = pulse_total_len;
                for i = 1:length(envelope)
                    if i <= Ntau
                        term1 = cos(pi * i / Ntau);
                        term2 = alpha * sin(pi * i / Ntau) / (1 - (2 * alpha * i / Ntau)^2);
                        envelope(i) = sinc(i / Ntau) * term2 + (1 - alpha) * term1;
                    end
                end
                envelope = envelope / max(abs(envelope)); % 归一化
                
            case 'hamming'
                % 汉明窗 (Hamming) - 标准
                envelope(on_idx) = hamming(Ntau);
                
            case 'hanning'
                % 汉宁窗 (Hanning)
                envelope(on_idx) = hanning(Ntau);
                
            case 'hamming_center'
                % 汉明窗，但能量主要集中在中间，两端衰减
                win = hamming(Ntau);
                envelope = win.';
                
            case 'kaiser'
                % Kaiser窗 (可控制旁瓣)
                beta = 3.0; % 控制主瓣宽度和旁瓣
                envelope(on_idx) = kaiser(Ntau, beta);
                
            otherwise
                % 默认矩形
                envelope(on_idx) = 1.0;
        end
        
        % --- 3. 合成单个 PRI 的干扰信号 ---
        % J(t) = envelope(t) * A_j * cos(2πf_j t + φ_j)
        single_jam_pri = envelope .* carrier;
        
        % 应用幅度
        single_jam_pri = Aj * single_jam_pri;
        
        % --- 4. 构建重复脉冲串 ---
        % 将单个 PRI 干扰复制 Np 次
        jam_pattern = repmat(single_jam_pri, 1, Np);
        
        % --- 5. 定位并填充到总时间轴 ---
        % 确定干扰起始位置 (通常在信号开始后)
        start_idx = 100; % 可根据需求调整，或使用 params.pos
        
        % 确保不超出边界
        end_idx = start_idx + length(jam_pattern) - 1;
        
        if end_idx <= N_total
            pure_jam(m, start_idx:end_idx) = jam_pattern;
        else
            % 如果超出，只填充到 N_total
            pure_jam(m, start_idx:N_total) = jam_pattern(1:(N_total-start_idx+1));
        end
    end
end
