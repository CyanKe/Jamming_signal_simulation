function varargout = choiwilliams(x, varargin)
%CHOIWILLIAMS Choi-Williams Time-Frequency Distribution.
%   Fully compatible with MATLAB's spectrogram arguments, including 
%   'centered', 'onesided', and 'twosided'.

    narginchk(1, 10);
    nargoutchk(0, 3);

    % --- 1. Parse String Arguments ---
    % Default freqrange
    freqrange = 'onesided'; 
    if ~isreal(x), freqrange = 'twosided'; end
    
    % Extract 'Sigma' if provided
    sigma = 1;
    idx_sigma = find(strcmpi(varargin, 'Sigma'));
    if ~isempty(idx_sigma)
        sigma = varargin{idx_sigma+1};
        varargin([idx_sigma, idx_sigma+1]) = [];
    end

    % Extract structural string arguments like 'centered'
    is_str = cellfun(@(c) ischar(c) || isstring(c), varargin);
    str_args = varargin(is_str);
    varargin(is_str) = []; % Remove from numeric parsing
    
    for k = 1:length(str_args)
        str = lower(str_args{k});
        if ismember(str, {'onesided', 'twosided', 'centered'})
            freqrange = str;
        end
    end
    
    % Complex signals cannot be truly 'onesided'
    if ~isreal(x) && strcmpi(freqrange, 'onesided')
        freqrange = 'twosided';
    end

    % --- 2. Parse Numeric Arguments ---
    num_args = length(varargin);
    
    window = 256;
    if num_args >= 1 && ~isempty(varargin{1}), window = varargin{1}; end
    
    noverlap = [];
    if num_args >= 2 && ~isempty(varargin{2}), noverlap = varargin{2}; end
    
    nfft = [];
    if num_args >= 3 && ~isempty(varargin{3}), nfft = varargin{3}; end
    
    fs = 1;
    if num_args >= 4 && ~isempty(varargin{4}), fs = varargin{4}; end

    % Format signal
    x = x(:);
    Nx = length(x);

    % WVD/CWD standard: use analytic signal for real inputs to suppress cross-terms
    if isreal(x)
        x_ana = hilbert(x);
    else
        x_ana = x;
    end
    
    % --- 3. 2x Upsampling (Crucial for Cohen's Class alias-free mapping) ---
    % Upsampling by 2 prevents WVD/CWD frequency aliasing and ensures the
    % NFFT bins strictly span [-Fs/2, Fs/2) matching `spectrogram`.
    x_up = interpft(x_ana, 2 * Nx); 
    
    % --- 4. Process Window and Parameters ---
    if isscalar(window)
        win_length = window;
        window_vec = hamming(win_length);
    else
        win_length = length(window);
        window_vec = window(:);
    end
    
    if isempty(noverlap), noverlap = fix(win_length / 2); end
    if isempty(nfft), nfft = max(256, 2^nextpow2(win_length)); end

    % Upsample the window to match the 2x signal
    win_up_length = 2 * win_length;
    window_up = interp1(1:win_length, window_vec, linspace(1, win_length, win_up_length)', 'linear');
    
    % Force odd length for symmetric lag processing
    if mod(win_up_length, 2) == 0
        win_up_length = win_up_length + 1;
        window_up = [window_up; 0]; 
    end
    M = (win_up_length - 1) / 2; % Max lag

    % --- 5. Align Time Vector Exactly with Spectrogram ---
    step_size = win_length - noverlap;
    start_idx = 1:step_size:(Nx - win_length + 1);
    t_idx = start_idx + (win_length - 1) / 2; % precise segment centers
    Nt = length(t_idx);
    T = (t_idx - 1) / fs; % output Time vector
    
    % Map indices to upsampled domain
    t_idx_up = round(t_idx * 2);

    % --- 6. Precompute Choi-Williams Kernel W(k, m) ---
    K = M; 
    k_vec = (-K:K)';
    W = zeros(2*K+1, M+1);
    W(K+1, 1) = 1;
    for m = 1:M
        val = exp(-sigma * (k_vec.^2) / (4 * m^2));
        W(:, m+1) = val / sum(val);
    end

    % Zero-Pad upsampled signal
    pad_len = K + M;
    x_up_pad = [zeros(pad_len, 1); x_up; zeros(pad_len, 1)];
    t_idx_up_pad = t_idx_up + pad_len;

    % --- 7. Compute Distribution ---
    S = zeros(nfft, Nt);
    half_window = window_up(M+2:end);

    for t = 1:Nt
        idx_t = t_idx_up_pad(t);
        R_local = zeros(M+1, 1);
        
        R_local(1) = x_up_pad(idx_t) * conj(x_up_pad(idx_t)); % m=0
        for m = 1:M
            i1 = idx_t + k_vec + m;
            i2 = idx_t + k_vec - m;
            R_local(m+1) = sum(W(:, m+1) .* x_up_pad(i1) .* conj(x_up_pad(i2)));
        end
        R_local(2:end) = R_local(2:end) .* half_window;
        
        % Form symmetric autocorrelation sequence (Length = 2M+1)
        R_sym = zeros(2*M+1, 1);
        R_sym(1) = R_local(1);
        R_sym(2:M+1) = R_local(2:end);
        R_sym(M+2:end) = conj(R_local(end:-1:2));
        
        % Data Wrapping (Crucial when NFFT < Window Length, e.g., 64 < 128)
        R_wrap = zeros(nfft, 1);
        for idx = 1:length(R_sym)
            wrap_i = mod(idx-1, nfft) + 1;
            R_wrap(wrap_i) = R_wrap(wrap_i) + R_sym(idx);
        end
        
        S(:, t) = real(fft(R_wrap));
    end

    % --- 8. Frequency Axis Mapping (onesided / twosided / centered) ---
    if strcmpi(freqrange, 'onesided')
        valid_idx = 1:fix(nfft/2)+1;
        S = S(valid_idx, :);
        F = (0:length(valid_idx)-1)' * (fs / nfft);
        
    elseif strcmpi(freqrange, 'twosided')
        F = (0:nfft-1)' * (fs / nfft);
        
    elseif strcmpi(freqrange, 'centered')
        S = fftshift(S, 1);
        if mod(nfft, 2) == 0
            F = (-nfft/2 : nfft/2 - 1)' * (fs / nfft);
        else
            F = (-(nfft-1)/2 : (nfft-1)/2)' * (fs / nfft);
        end
    end

    % --- 9. Output Processing ---
    if nargout == 0
        figure;
        S_dB = 10 * log10(abs(S) + eps);
        surf(T, F, S_dB, 'EdgeColor', 'none');
        axis xy; axis tight; colormap(parula); view(0, 90);
        ylabel('Frequency (Hz)'); xlabel('Time (s)');
        title('Choi-Williams Distribution');
    else
        varargout{1} = S;
        if nargout >= 2, varargout{2} = F; end
        if nargout >= 3, varargout{3} = T; end
    end
end