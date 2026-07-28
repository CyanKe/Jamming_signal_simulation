function out = resize_persistence_map(P, target_size)
% RESIZE_PERSISTENCE_MAP 将 persistence 图双线性插值到目标尺寸
%
% 输入:
%   P           - [Nfreq, Npower] 单通道持续时间谱
%   target_size - [H, W] = [freq_out, power_out]
%
% 输出:
%   out         - [H, W] (与 P 同类: single/double)

    if nargin < 2 || isempty(target_size)
        out = P;
        return;
    end

    Ht = target_size(1);
    Wt = target_size(2);
    [Nf, Nb] = size(P);

    if Nf == Ht && Nb == Wt
        out = P;
        return;
    end

    % 归一化网格: 将源图映射到目标分辨率 (双线性, 边界外填 0)
    [X0, Y0] = meshgrid(1:Nb, 1:Nf);
    [X, Y] = meshgrid(linspace(1, Nb, Wt), linspace(1, Nf, Ht));
    out = interp2(X0, Y0, double(P), X, Y, 'linear', 0);

    if isa(P, 'single')
        out = single(out);
    end
end
