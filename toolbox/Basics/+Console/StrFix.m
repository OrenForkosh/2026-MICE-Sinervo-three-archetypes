function StrFix(pre, suf, varargin)
% add prefix and sufix to string
fprintf([pre varargin{1} suf], varargin{2:end});
