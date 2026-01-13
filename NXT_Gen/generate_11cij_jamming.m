function [pure_jam] = generate_11cij_jamming(tx, params, ~)
% generate_11cij_jamming: 切片与交织干扰 (Chopping and Interleaving Jamming)
% tx: 原始雷达信号
% params: 包含 fs(采样率), T(脉宽), JNR, a(重复次数), b(子脉冲数)

fs = params.fs;         % 采样频率
T = params.T;           % 信号脉宽
N_total = length(tx);   % 总采样点数
a = params.a_cij;       % 每个片段的重复次数 (对应描述中的 a)
b = params.b_cij;       % 采样的子脉冲个数 (对应描述中的 b)

% 计算功率增益
Aj = 10^(params.JNR / 20);

% 初始化干扰信号
pure_jam = zeros(1, N_total);

% 计算基本参数
N_pulse = floor(T * fs);        % 整个脉冲的采样点数
N_seg = floor(N_pulse / b);     % 每个大段(b分之一)的长度
N_slice = floor(N_seg / a);     % 每次采样的切片长度 (1/ab)

% 找到信号开始的位置（假设信号是从第一个非零点开始，或根据params.pos）
% 如果tx是generate_0base_signal生成的，它通常已经根据pos放好了位置
start_idx = find(abs(tx) > 0, 1);
if isempty(start_idx)
    return;
end

% 执行切片与交织过程
% 对应公式 (7) 的采样和 (6) 的重构
for i = 0 : b-1
    % 1. 确定当前大段的起始位置
    current_seg_start = start_idx + i * N_seg;
    
    % 边界检查，防止超出tx范围
    if current_seg_start + N_slice - 1 > N_total
        break;
    end
    
    % 2. 采样：获取当前段最前面的切片 (Chopping)
    % 对应公式 (7) 中的 p(t)
    slice = tx(current_seg_start : current_seg_start + N_slice - 1);
    
    % 3. 交织/填充：将切片重复 a 次 (Interleaving)
    % 对应公式 (6) 中的求和重构
    for k = 0 : a-1
        fill_start = current_seg_start + k * N_slice;
        fill_end = fill_start + N_slice - 1;
        
        if fill_end <= N_total
            pure_jam(fill_start : fill_end) = slice;
        end
    end
end

% 应用干扰增益
pure_jam = Aj * pure_jam;

end