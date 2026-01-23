% ==========================================================
% Comb Spectrum Jamming (CSJ) generator
% 梳状谱干扰：LFM × comb
% ==========================================================
function [pure_jam] = generate_15csj_jamming(tx, params, data_num)
% 解包参数
fs      = params.fs;
fc      = params.fc;
B       = params.B;
taup    = params.taup;          % LFM 脉宽 (s)
Np      = params.Np;            % PRI 个数
PRI     = params.PRI;           % PRI 时间 (s)
PRI_samp= params.PRI_samp;      % PRI 采样点
Ntau    = params.Ntau;          % LFM 点数
pos     = params.pos;           % LFM 在 PRI 中的位置
N_total = params.N_total;

As = 10^(params.SNR/20);
Aj = 10^(params.JNR/20);

% 输出
pure_jam = zeros(data_num, N_total);

% 时间轴（LFM脉内）
t_pulse = params.ttau;

% 循环生成样本
for m = 1:data_num

    % ---------- 1. 梳状谱参数（可随机） ----------
    M = 3%randi([3, 10]);              % 梳齿数
    Q = 0.08%0.05 + 0.05 * rand();       % 频率间隔系数
    P = 0.6%0.5  + 0.5  * rand();       % 幅度系数

    % ---------- 2. 生成梳状谱信号 ----------
    comb_pulse = zeros(1, Ntau);

    for k = 1:M
        fk = k * Q * fc;
        comb_pulse = comb_pulse + P * exp(1j * 2*pi*fk * real(t_pulse));
    end

    subplot(1,2,1);
    plot(params.ttau*1e3, real(comb_pulse));
    % axis([0 3.2 -1.1 1.1])
    axis tight;
    xlabel('Time / ms'); ylabel('Amplitude');

    subplot(1,2,2);

    [S,F,T] = spectrogram(comb_pulse,128,64,256,params.fs, 'centered');
    % S = all_S(50*i-49,:,:);
    S = squeeze(S);
    imagesc(T*1e6,F/1e6,abs(S));
    xlabel('Time/μs'); ylabel('Frequency/MHz');

    % ---------- 3. 被干扰的 LFM ----------
    lfm_pulse = tx(1, pos : pos + Ntau - 1);
    jammed_lfm = As * lfm_pulse .* comb_pulse;

    % ---------- 4. 构造 PRI 内干扰模板 ----------
    jam_pri = zeros(1, PRI_samp);
    right_pos = pos + Ntau - 1;
    if right_pos <= PRI_samp
        jam_pri(pos:right_pos) = Aj * jammed_lfm;
    end

    % ---------- 5. 复制到整个信号 ----------
    pure_jam(m, :) = repmat(jam_pri, 1, Np);


end
end
