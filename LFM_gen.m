function [fs,ts,T,N,t] = LFM_gen(inputArg1,inputArg2)
%LFM_GEN 用于生成LFM信号，并返回相关参数
%   此处显示详细说明
fs = 80e6;          % 采样频率 80MHz
ts = 1/fs;          % 采样时间间隔
T = 100e-6;         % 信号时宽 100μs
N = round(T*fs);    % 采样点数
t = (0:N-1)*ts;     % 时间窗口
% t = linspace(0,taup,taup*fs);          %时间序列

%% 1.定义线性调频信号
taup = 20e-6;       % 信号脉宽 20μs
Ntau = round(taup*fs);    % 采样点数
ttau = (-Ntau/2:1:Ntau/2-1)*ts;     % LFM时间窗口
B  = 10e6;          % 信号带宽 10MHz
fc = 40e6           % 中心频率 40MHz
f0 = fc - B/2;      % 起始频率
f1 = fc + B/2;      % 终止频率
% lfm = exp(1j*2*pi*(f0*ttau + (B/(2*taup))*ttau.^2));
lfm = exp(1j*pi*B/taup*ttau.^2);          %LFM信号
end

