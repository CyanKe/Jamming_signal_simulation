function [pure_jam, jam_info] = generate_ncj_sf_jamming(tx, params, data_num)
    % generate_ncj_sf_jamming - 噪声卷积干扰（NCJ）的存储-转发变体
    %
    % 与 generate_ncj_jamming 的唯一区别：一个「存储块」的波形在 U 个 PRI 内
    % 完全复用，而不是原版的「每个样本抽一次噪声再 repmat」。
    %
    %   原版：每个样本抽一次噪声 → 复制到 Np 个 PRI（= U = Np 的特例）
    %   本版：每 U 个 PRI 抽一次噪声 → 块内所有脉冲共用同一段存储波形
    %
    % 为什么需要这个参数：
    %   噪声干扰机每个 PRI 重新产生噪声时，脉间不相关，雷达的 MTD 不会给出
    %   相干增益；而 DRFM 噪声转发机把一段噪声存下来重复播放，脉间相干，
    %   MTD 后可获得约 10·log10(Np) 的相干增益。两者的单 PRI 波形统计相同，
    %   只有脉间维度能区分，所以生成器必须显式支持 Np>1。
    %
    % params 字段：
    %   Np              脉冲数（<=1 时本函数与原版等价）
    %   U               【可选】更新周期，以 PRI 计。缺省 = Np（整帧同一波形），
    %                   即与原版一致；U=1 表示每脉冲重新产生噪声。
    %   drift_per_pulse 【可选】块内每脉冲附加相位漂移（rad），缺省 0。
    %                   非零用于模拟 DRFM 相位漂移，会削弱相干积累。
    %
    % 约定：输出整帧 RMS 归一化到 Aj = 10^(JNR/20)，与原版一致。
    %       当 Np=1、U=1 时本函数与原版逐位一致（随机数调用顺序保持一致）。

    fs       = params.fs;
    N_total  = params.N_total;
    Aj       = 10^(params.JNR/20);
    PRI_samp = params.PRI_samp;
    taup     = params.taup;
    ttau     = params.ttau;
    Ntau     = params.Ntau;
    Np       = params.Np;

    U = Np;
    if isfield(params, 'U') && ~isempty(params.U)
        U = round(params.U);
    end
    U = min(max(U, 1), max(Np, 1));

    drift = 0;
    if isfield(params, 'drift_per_pulse') && ~isempty(params.drift_per_pulse)
        drift = params.drift_per_pulse;
    end

    pure_jam = zeros(data_num, N_total);
    jam_info = struct('U', {}, 'n_blocks', {}, 'delay_samp', {}, 'is_continuous', {});

    for m = 1:data_num
        jam_frame = zeros(1, N_total);
        stored_seg   = [];
        stored_delay = 0;
        n_blocks     = 0;

        for p = 0:Np-1
            % ---- 块边界：抽一次噪声并卷积，块内复用 ----
            if mod(p, U) == 0
                n_blocks = n_blocks + 1;

                % 以下随机数调用顺序与原版 generate_ncj_jamming 保持一致，
                % 以便 Np=1 时两者逐位相同。
                convolution_noise = randn([1, PRI_samp]) + 1j*randn([1, PRI_samp]);
                convolution_noise = convolution_noise / std(convolution_noise);

                sampling_period = taup / (5 + randi(10));
                sampling_duty   = 20 + randi(30);
                squa = (square((1/sampling_period)*2*pi*ttau, sampling_duty) + 1) / 2; %#ok<NASGU>
                % 原版此处为 jam_kernel = lfm ; % .* squa;
                % 门控被原作者注释掉，故 NCJ 的支撑段正好等于一个脉宽。
                % 保留 squa 的计算只为维持随机流一致，不参与合成。

                lfm = tx(1, params.pos : params.pos + Ntau - 1);
                jam_kernel = lfm;
                jam_conv_result = conv(convolution_noise, jam_kernel, 'same');
                jam_conv_result = jam_conv_result / std(jam_conv_result);

                delay_time   = (-2 + rand() * 4) * 1e-6;
                stored_delay = round(delay_time * fs);
                start_point  = randi(length(jam_conv_result) - Ntau);
                stored_seg   = jam_conv_result(start_point : start_point + Ntau - 1);
            end

            left  = params.pos + stored_delay;
            right = left + Ntau - 1;
            if left < 1 || right > PRI_samp
                continue;   % 与原版一致：越界则本脉冲不放置
            end

            seg = Aj * sqrt(PRI_samp / Ntau) * stored_seg .* exp(1j * drift * p);
            idx = p * PRI_samp + (left:right);
            jam_frame(idx) = jam_frame(idx) + seg;
        end

        pwr = mean(abs(jam_frame).^2);
        if pwr > 0
            jam_frame = jam_frame / sqrt(pwr) * Aj;
        end
        pure_jam(m, :) = jam_frame;

        jam_info(m).U             = U;
        jam_info(m).n_blocks      = n_blocks;
        jam_info(m).delay_samp    = stored_delay;
        jam_info(m).is_continuous = true;
    end
end
