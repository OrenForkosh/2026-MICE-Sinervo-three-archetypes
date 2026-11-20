classdef InfoTheory
    % Information theory toolbox
    methods (Static = true)
        function y = Log2(x)
            % Log2(x) computes the base 2 logarithm of the elements of X.
            % All elements of X are set to be above a threshold (default is
            % -200)
%             thresh = 1e-200;
%             t = (x < thresh);
%             if any(t(:))
%                 x = (~t).* x + (t) * thresh;
%             end
            thresh = -800;
            y = log2(x);
            y(y < thresh) = thresh;
        end

        function y = Log(x)
            % Log(x) computes the natural logarithm of the elements of X.
            % All elements of X are set to be above a threshold (default is
            % -200)
            thresh = -800;
            y = log(x);
            y(y < thresh) = thresh;
        end
        
        function R = LogSum(a_ln, b_ln)		 % ln(a + b) = ln{exp[ln(a) - ln(b)] + 1} + ln(b)
            % Method for calculating precise logarithm of a sum
            % The method is based on the notion that
            % ln(a + b) = ln{exp[ln(a) - ln(b)] + 1} + ln(b).
            %
            % The method requires calling only one exp() and one log(), instead of two exp() and one log() in the basic solution.
            % Additionally, the proposed method has the critical advantage of not overflowing in case of large numbers of a and b.
            %
            % Usage: R = LogSum(a_ln, b_ln)
            % where
            % a_ln - logarithm of first addend
            % b_ln - logarithm of second addend
            % R - precise logarithm of the result of the addition
            if (abs(a_ln - b_ln) >= 36.043653389117155)		% 2^52-1 = 4503599627370495.	log of that is 36.043653389117155867651465390794
                R = max(a_ln, b_ln);		 % this branch is necessary, to avoid shifted_a_ln = a_ln - b_ln having too big value
            else
                R = log(exp(a_ln - b_ln) + 1) + b_ln;
                
                % shifted_a_ln = a_ln - b_ln;
                % shifted_sum = exp(shifted_a_ln) + 1;
                % shifted_sum_ln = log(shifted_sum);
                % unshifted_sum_ln = shifted_sum_ln + b_ln;
                % R = unshifted_sum_ln;
            end
            
        end
        
        
        function d = KullbackLiebler(p1, p2)
            % KullbackLiebler(p1, p2) computes the Kullback-Liebler divergence.
            % p1 and p2 are the probability vectors (assumed to sum to one).
            d = p1 .* (InfoTheory.Log2(p1) - InfoTheory.Log2(p2));
            d(p1 == 0) = 0;
            d = sum(d);
        end

        function d = JensenShannon(p1, p2)
            % JensenShannon(p1, p2) computes the Jensen-Shannon divergence.
            % p1 and p2 are the probability vectors (assumed to sum to one).
            m = .5 * (p1 + p2);
            d = .5 * (InfoTheory.KullbackLiebler(p1, m) + InfoTheory.KullbackLiebler(p2, m));
        end
        
        function mi = MutualInformation(P)
            % MutualInformation(P) computes the mutual information.
            % The matrix P is the joint probability of the
            % two variables (assumed to sum to one).
            p1 = repmat(sum(P, 1), size(P,1), 1);
            p2 = repmat(sum(P, 2), 1, size(P,2));
            mi = P .* (InfoTheory.Log2(P ./ (p1 .* p2)));
            mi = sum(mi(:));
        end
        
        function h = Entropy(p1)
            % Entropy(p1) computes the Shannon Entropy.
            % p1 is a vector of probabilities (assumed to sum to one).
            p = nonzeros(p1);
            h = -sum(p .* InfoTheory.Log2(p));
        end
        
        % attempts to estimate differential entropy from samples.
        % uses the 'binless' entropy estimation approach described in:
        %  J.D. Victor, 2002
        %  Kozachenko and Leonenko, 1987
        % input:
        % x - every row is a sample, every column is a dimension
        function entropy = DiffEntropy(x)
            
            [nsamples, ndims] = size(x); % get input dimensions
            
            % for each sample, compute the distance to its nearest neighbor
            if (ndims == 1)
                % if we are univariate we can make the nearest-neighbor computation
                % more efficient by presorting the input (reduce from n^2 to nlogn),
                % so this case merits special attention    .
                x = sort(x','ascend');
                x = [-inf x inf]; % padding to deal with the edges
                distances = [x(2:(end-1)) - x(1:(end-2)); ...
                    x(3:(end)) - x(2:(end-1))];
                % one row of minval contains the distances to the left neighbors, the other
                % contains the distances to the right neighbors, we can now take the min:
                minvals = min(distances);
            else
                % compute the nearest neighbour for each sample. We compute all the
                % pairwise distances at once, which means that this current implementation
                % is quite heavy on memory for large groups of samples. We might to
                % change this to one sample at a time.
                distances = dist(x');
                for i = 1:nsamples
                    distances(i,i) = inf;
                end
                minvals = min(distances);
            end
            
            
            % volume of r-dimensional unit sphere
            Sr = (ndims*pi^(ndims/2))/gamma(ndims/2+1);
            
            % compute each of the terms of the estimation formula
            term1 = ndims * sum(log2(minvals)) / nsamples;
            term2 = log2(Sr*(nsamples-1)/ndims);
            term3 = -psi(1) / log(2);   % (-psi(1)) is the euler constant
            
            % put it all together
            entropy = term1 + term2 + term3;
        end
        
        function h = NormalEntropy(c)
            % NormalEntropy(c) computes the entropy of a multivariate
            % variable with covariance matrix c
            dim = size(c, 1);
            h = 1/2 * log2(det((2*pi*exp(1))^dim*c));
        end
        
        function h = EmpiricalEntropy(X, range)
            % EmpiricalEntropy(X) computes the Shannon Entropy from samples.
            % X is a SxN matrix where S is the number of samples, and N is 
            % the number of variables.
            [~, idx] = histc(X, range);
            dim = size(X, 2);
            nvals = length(range);
            [u, ~, ic] = unique((idx - 1) * (nvals.^(dim-1:-1:0))');
            p = histc(ic, 1:length(u));
            p = p / sum(p);
            h = -p(:)' * log2(p(:));
        end
        
        function p = IndepProbs(X, range)
            % IndepProbs(X, [range]) computes the independent probabilities of discrete values in X
            % X is a SxN matrix where S is the number of samples, and N is 
            % the number of variables.
            % range (optional) is the range of values in X.
            if ~exist('range', 'var')
                range = unique(X(:));
            end
            h = histc(X, range);
            p = bsxfun(@rdivide, h, sum(h));
        end
        
        function p = JointProbs(X, range)
            % JointProbs(X, [range]) computes the joint probabilities of discrete values in X
            % X is a SxN matrix where S is the number of samples, and N is 
            % the number of variables.
            % range (optional) is the range of values in X.
            if ~exist('range', 'var')
                range = unique(X(:));
            end
            [~, idx] = histc(X, range);
            [nsamp, dim] = size(X);
            idx = mat2cell(idx, nsamp, ones(1,dim));
            %accumarray
            p = zeros(length(range) * ones(1, dim));
            pidx = sub2ind(size(p), idx{:});
            p(:) = histc(pidx, 1:numel(p));
            p = p / sum(p(:));
        end
        
        function p = JointProbsVec(X, range)
            % p = JointProbsVec(X, [range]) computes the joint probabilities of discrete values in X
            % X is a SxN matrix where S is the number of samples, and N is 
            % the number of variables.
            % range (optional) is the range of values in X.
            % 
            % The output p is a vector of length 2^length(range) with the
            % joint probabilities of all variables in X
            if ~exist('range', 'var')
                range = unique(X(:));
            end
            [h, idx] = histc(X, range);
            probidx = (idx - 1) * (length(range).^(size(X, 2)-1:-1:0))';
            p = histc(probidx, 0:length(range)^size(X, 2)-1);
            p = p / sum(p);
        end

        function p = IndepProbsVec(X, range)
            % p = IndepProbsVec(X, [range]) computes the independent probabilities of discrete values in X
            % X is a SxN matrix where S is the number of samples, and N is 
            % the number of variables.
            % range (optional) is the range of values in X.
            % 
            % The output p is a vector of length 2^length(range) with the
            % independent probabilities of all variables in X
            if ~exist('range', 'var')
                range = unique(X(:));
            end
            indep = InfoTheory.IndepProbs(X, range);
            perms = InfoTheory.Dec2Base(0:length(range)^size(X, 2)-1, size(X, 2), length(range));
            id = repmat(1:size(X, 2), size(perms, 1), 1);
            p = prod(indep(sub2ind(size(indep), perms+1,id)), 2);
        end
        
        function P = SubJointProb(p, ind)
            % Auxilary for computing the Kirkwood approximation (see
            % InfoTheory.KirkwoodApproximation)
            nd = ndims(p);
            other = setdiff(1:nd, ind);
            P = p;
            for o=Q.torow(other)
                dim = ones(1,nd);
                dim(o) = size(P, o);
                P = repmat(sum(P, o), dim);
            end
        end
        
        function [P, joint] = KirkwoodApproximation(X, varargin)
             joint = InfoTheory.JointProbs(X, varargin{:});
             [~, dim] = size(X);
             if dim == 3
                 P = (InfoTheory.SubJointProb(joint, [1 2]) .* InfoTheory.SubJointProb(joint, [2 3]) .* InfoTheory.SubJointProb(joint, [1 3])) ./ (InfoTheory.SubJointProb(joint, 1) .* InfoTheory.SubJointProb(joint, 2) .* InfoTheory.SubJointProb(joint, 3));
             elseif dim < 2
                 P = InfoTheory.SubJointProb(joint, 1) .* InfoTheory.SubJointProb(joint, 2) .* InfoTheory.SubJointProb(joint, 3);
             else
                 error;
             end
        end

        function I = CoInformation(X, varargin)
            [P, p] = InfoTheory.KirkwoodApproximation(X, varargin{:});
            I = p .* (InfoTheory.Log2(p) - InfoTheory.Log2(P));
            I = sum(I(:));
        end
    end
   
    methods (Static = true, Access = public)
        function y = Dec2Base(d, n, base)
            % y = Dec2Bin(d, n, base) converts decimal number to another base
            % with n digits
            % y = rem(floor(d(:)*base.^(1-n:0)),base); % error with large numbers
%             y = de2bi(d, n, base, 'left-msb');
            % y = dec2base(d,base,n) - '0';
            y = de2bi(d, n, base, 'left-msb');
        end

        function y = Base2Dec(d, base)
            y = d * (base.^(size(d, 2)-1:-1:0))';
%             y = bi2de(d, base, 'left-msb');
        end
        
        function y = Dec2Bin(d, n)
            % y = Dec2Bin(d, n) converts decimal to binary number 
            % with n digits
            %            y = rem(floor(d(:)*pow2(1-n:0)),2);
            y = InfoTheory.Dec2Base(d, n, 2);
        end
    end    
end