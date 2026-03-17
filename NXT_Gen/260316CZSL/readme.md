# 组合零样本小测试

## 欺骗+压制+组合3+3+9

train = ['DFTJ', 'ISRJ', 'SMSPJ', 'AJ', 'BJ','SJ']
test  = ['DFTJ', 'ISRJ', 'SMSPJ', 'AJ', 'BJ','SJ']
val   = ['DFTJ', 'ISRJ', 'SMSPJ', 'AJ', 'BJ','SJ'+九种组合]

样本个数:train 每个种类210个样本,test 90个,val 500个
7:3:16.7的神秘比例
SNR = 15 dB，JNR = 0，10，20, 30，40, 50 dB
HDF5‌ -v7.3保存
xx_echo_label.mat 多热标签
xx_echo_stfts.mat 时频域数据 每张图大小为124x64，complex double
xx_echo_times.mat 时域数据 每段回波长度为1x8000，complex double

self.classes = [
    'DFTJ',         # 密集假目标干扰
    'ISRJ',         # 间歇采样转发干扰
    'VDJ',          # 速度欺骗干扰
    'DDJ',          # 距离-速度联合欺骗干扰
    'AJ',           # 瞄准干扰
    'BJ',           # 阻塞干扰
    'SJ',           # 扫频干扰
    'NCJ',          # 噪声卷积干扰
    'NPJ',          # 噪声乘积干扰
    'SPSMJ',        # 弥散谱干扰
    'C&IJ',         # 切片交织干扰
    'NFMJ',         # 噪声频率调制干扰
    'NPMJ',         # 噪声相位调制干扰
    'NAMJ',         # 噪声幅度调制干扰
    'CSJ',          # 梳状谱干扰
    'PJ'            # 脉冲干扰
]

## 每个类别的文本描述（用于零样本学习）

self.descriptions = {
    'DFTJ': [
        'a radar signal with dense false target jamming',
        'a radar echo with multiple delayed and stacked false targets',
        'a radar signal intercepted, delayed and retransmitted many times to create false targets'
    ],
    'ISRJ': [
        'a radar signal with interrupted sampling repeater jamming',
        'a radar echo with periodic sampled and forwarded interference',
        'a radar signal with interference sampling and immediate forwarding jamming'
    ],
    'VDJ': [
        'a radar signal with velocity deception jamming',
        'a radar echo with false Doppler frequency modulation',
        'a radar signal with velocity drag deception interference'
    ],
    'DDJ': [
        'a radar signal with distance and velocity joint deception jamming',
        'a radar echo with combined range and Doppler deception',
        'a radar signal with simultaneous range-velocity deception interference'
    ],
    'AJ': [
        'a radar signal with aiming suppression jamming',
        'a radar echo with frequency-aligned narrowband jamming',
        'a radar signal with targeted frequency coverage jamming'
    ],
    'BJ': [
        'a radar signal with barrage suppression jamming',
        'a radar echo with wideband barrage interference',
        'a radar signal with broadband noise covering multiple frequencies'
    ],
    'SJ': [
        'a radar signal with swept frequency jamming',
        'a radar echo with periodically varying center frequency interference',
        'a radar signal with sweeping carrier frequency jamming'
    ],
    'NCJ': [
        'a radar signal with noise convolution jamming',
        'a radar echo with convolved gaussian noise interference',
        'a radar signal with noise convolution smart jamming'
    ],
    'NPJ': [
        'a radar signal with noise multiplication jamming',
        'a radar echo with multiplied gaussian noise interference',
        'a radar signal with noise product smart jamming'
    ],
    'SPSMJ': [
        'a radar signal with smeared spectrum jamming',
        'a radar echo with spread spectrum interference from sub-pulses',
        'a radar signal with interval-sampled and compressed sub-pulse jamming'
    ],
    'C&IJ': [
        'a radar signal with chopping and interleaved jamming',
        'a radar echo with sliced and reconstructed interference',
        'a radar signal with time-sliced and repeatedly filled jamming'
    ],
    'NFMJ': [
        'a radar signal with noise frequency modulation jamming',
        'a radar echo with instantaneous frequency modulated by noise',
        'a radar signal with noise-modulated instantaneous frequency'
    ],
    'NPMJ': [
        'a radar signal with noise phase modulation jamming',
        'a radar echo with instantaneous phase modulated by noise',
        'a radar signal with noise-modulated instantaneous phase'
    ],
    'NAMJ': [
        'a radar signal with noise amplitude modulation jamming',
        'a radar echo with amplitude modulated by gaussian noise',
        'a radar signal with noise-modulated signal amplitude'
    ],
    'CSJ': [
        'a radar signal with comb spectrum jamming',
        'a radar echo with comb-shaped frequency distribution',
        'a radar signal with multiple false targets from multi-frequency modulation'
    ],
    'PJ': [
        'a radar signal with pulse jamming',
        'a radar echo with rectangular pulse interference on carrier',
        'a radar signal with repetitive high-frequency pulse jamming'
    ]
}
