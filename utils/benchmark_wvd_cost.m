% ==========================================================
% benchmark_wvd_cost.m - 在少量样本上实测 WVD/PWVD/SPWVD/CWD 开销
%
% 实际调用 convert_times_to_tfr (每类 1 样本), 并打印/写入 cost report.
%
%   benchmark_wvd_cost
%   benchmark_wvd_cost('output/2D_8x9_0520/JNR_+10', 'max_classes', 1)
%   benchmark_wvd_cost('output/psp_test/JNR_+10', 'max_classes', 3)  % 快速试跑
% ==========================================================

function benchmark_wvd_cost(varargin)
    p = inputParser;
    p.addOptional('target_dir', '', @(s) ischar(s) || isstring(s));
    p.addParameter('max_classes', inf, @isnumeric);
    p.addParameter('per_class', 1, @isnumeric);
    p.addParameter('modes', {'wvd', 'pwvd', 'spwvd', 'cwd'}, @(c) iscell(c) || isstring(c));
    p.addParameter('force', true, @islogical);
    p.parse(varargin{:});

    script_path = fileparts(mfilename('fullpath'));
    addpath(script_path);

    args = { ...
        'modes', cellstr(p.Results.modes), ...
        'per_class', p.Results.per_class, ...
        'max_classes', p.Results.max_classes, ...
        'lag_len', 256, ...
        'time_win_len', 256, ...
        'native_size', 256, ...
        'target_size', [224 224], ...
        'force', p.Results.force};

    if ~isempty(p.Results.target_dir)
        convert_times_to_tfr(char(p.Results.target_dir), args{:});
    else
        convert_times_to_tfr(args{:});
    end
end
