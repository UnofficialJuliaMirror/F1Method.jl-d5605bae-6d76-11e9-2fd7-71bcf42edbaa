module FormulaOneMethod

using LinearAlgebra
using DualNumbers, HyperDualNumbers, DiffEqBase

mutable struct Buffer
    s   # s(p)
    A   # factors of ∇ₓF(s, p)
    ∇s  # ∇s(p)
    ∇ₓf # ∇ₓf(s, p)
    p   # p
end

function update_buffer!(f, F, ∇ₓf, ∇ₓF, buffer, p, alg; options...)
    if p ≠ buffer.p       # only update if p has changed
        update_solution_only!(F, ∇ₓF, buffer, p, alg; options...)
        s, m = buffer.s.u, length(p)
        ∇ₚF = hcat([𝔇(F(s, p + ε * e(j,m))) for j in 1:m]...) # Eq.(?)
        buffer.A = factorize(∇ₓF(s,p))  # update factors of ∇ₓF(s, p)
        buffer.∇s .= buffer.A \ -∇ₚF    # update ∇s via Eq.(?)
        buffer.∇ₓf .= ∇ₓf(s,p)          # update ∇ₓf(s, p)
        buffer.p = p      # update p
    end
end

function update_solution_only!(F, ∇ₓF, buffer, p, alg; options...)
    if ~(buffer.s isa SteadyStateSolution) || p ≠ buffer.s.prob.p
        buffer.s isa SteadyStateSolution ? x = buffer.s.u : x = buffer.s
        prob = SteadyStateProblem(F, ∇ₓF, x, p) # define problem
        buffer.s = solve(prob, alg; options...) # update s (inner solver)
    end
end

function f̂(f, F, ∇ₓF, buffer, p, alg; options...) # objective
    update_solution_only!(F, ∇ₓF, buffer, p, alg; options...)
    return f(buffer.s,p)
end

function ∇f̂(f, F, ∇ₓf, ∇ₓF, buffer, p, alg; options...) # gradient
    update_buffer!(f, F, ∇ₓf, ∇ₓF, buffer, p, alg; options...)
    s, ∇s, m = buffer.s, buffer.∇s, length(p)
    ∇ₚf = [𝔇(f(s,p + ε * e(j,m))) for j in 1:m]' # Eq. (?)
    return buffer.∇ₓf * ∇s + ∇ₚf               # Eq. (?)
end

function ∇²f̂(f, F, ∇ₓf, ∇ₓF, buffer, p, alg; options...) # Hessian
    update_buffer!(f, F, ∇ₓf, ∇ₓF, buffer, p, alg; options...)
    s, A, ∇s, m = buffer.s, buffer.A, buffer.∇s, length(p)
    A⁻ᵀ∇ₓfᵀ = vec(A' \ buffer.∇ₓf') # independent of (j,k)
    out = zeros(m,m)       # preallocate
    for j in 1:m, k in j:m # Loop for Eq.(?)
        pⱼₖ = p + ε₁ * e(j,m) + ε₂ * e(k,m)           # Hyperdual p
        xⱼₖ = s + ε₁ * ∇s * e(j,m) + ε₂ * ∇s * e(k,m) # Hyperdual x
        out[j,k] = ℌ(f(xⱼₖ,pⱼₖ)) - ℌ(F(xⱼₖ,pⱼₖ))' * A⁻ᵀ∇ₓfᵀ # Eq.(?)
        j ≠ k ? out[k,j] = out[j,k] : nothing   # symmetry
    end
    return out
end

function initialize_buffer(x, p)
    n, m = length(x), length(p)
    return Buffer(copy(x), nothing, zeros(n,m), zeros(1,n), nothing)
end

# Helper functions
e(j, m) = [i == j for i in 1:m]      # j-th basis vector
𝔇(x) = DualNumbers.dualpart.(x)      # dual part
ℌ(x) = HyperDualNumbers.ε₁ε₂part.(x) # hyperdual part

end # module
