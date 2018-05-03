export SCSOptimizer

using MathOptInterface
const MOI = MathOptInterface
const CI = MOI.ConstraintIndex
const VI = MOI.VariableIndex

const MOIU = MOI.Utilities

const SF = Union{MOI.SingleVariable, MOI.ScalarAffineFunction{Float64}, MOI.VectorOfVariables, MOI.VectorAffineFunction{Float64}}
const SS = Union{MOI.EqualTo{Float64}, MOI.GreaterThan{Float64}, MOI.LessThan{Float64}, MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives, MOI.SecondOrderCone, MOI.ExponentialCone, MOI.PositiveSemidefiniteConeTriangle}

struct MOISolution
    ret_val::Int
    primal::Vector{Float64}
    dual::Vector{Float64}
    slack::Vector{Float64}
    objval::Float64
end
MOISolution() = MOISolution(0, # SCS_UNFINISHED
                      Float64[], Float64[], Float64[], NaN)

# Used to build the data with allocate-load during `copy!`.
# When `optimize!` is called, a the data is passed to SCS
# using `SCS_solve` and the `Data` struct is discarded
mutable struct Data
    m::Int # Number of rows/constraints
    n::Int # Number of cols/variables
    I::Vector{Int} # List of rows
    J::Vector{Int} # List of cols
    V::Vector{Float64} # List of coefficients
    b::Vector{Float64} # constants
    objconstant::Float64 # The objective is min c'x + objconstant
    c::Vector{Float64}
end

mutable struct Cone
    f::Int # number of linear equality constraints
    l::Int # length of LP cone
    q::Int # length of SOC cone
    qa::Vector{Int} # array of second-order cone constraints
    s::Int # length of SD cone
    sa::Vector{Int} # array of semi-definite constraints
    ep::Int # number of primal exponential cone triples
    ed::Int # number of dual exponential cone triples
    p::Vector{Float64} # array of power cone params
    setconstant::Dict{Int, Float64} # For the constant of EqualTo, LessThan and GreaterThan, they are used for getting the `ConstraintPrimal` as the slack is Ax - b but MOI expects Ax so we need to add the constant b to the slack to get Ax
    nrows::Dict{Int, Int} # The number of rows of each vector sets
    function Cone()
        new(0, 0,
            0, Int[],
            0, Int[],
            0, 0, Float64[],
            Dict{Int, Float64}(),
            Dict{Int, UnitRange{Int}}())
    end
end

mutable struct SCSOptimizer <: MOI.AbstractOptimizer
    cone::Cone
    maxsense::Bool
    data::Union{Void, Data} # only non-Void between MOI.copy! and MOI.optimize!
    sol::MOISolution
    function SCSOptimizer()
        new(Cone(), false, nothing, MOISolution())
    end
end

function MOI.isempty(optimizer::SCSOptimizer)
    !optimizer.maxsense && optimizer.data === nothing
end
function MOI.empty!(optimizer::SCSOptimizer)
    optimizer.maxsense = false
    optimizer.data = nothing # It should already be nothing except if an error is thrown inside copy!
end

MOI.canaddvariable(optimizer::SCSOptimizer) = false

MOI.supports(::SCSOptimizer, ::MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}) = true
MOI.supportsconstraint(::SCSOptimizer, ::Type{<:SF}, ::Type{<:SS}) = true
MOI.copy!(dest::SCSOptimizer, src::MOI.ModelLike; copynames=true) = MOIU.allocateload!(dest, src, copynames)

# Implements optimize! : translate data to SCSData and call SCS_solve
using Compat.SparseArrays

const ZeroCones = Union{MOI.EqualTo, MOI.Zeros}
const LPCones = Union{MOI.GreaterThan, MOI.LessThan, MOI.Nonnegatives, MOI.Nonpositives}

_dim(s::MOI.AbstractScalarSet) = 1
_dim(s::MOI.AbstractVectorSet) = MOI.dimension(s)

# Computes cone dimensions
constroffset(cone::Cone, ci::CI{<:MOI.AbstractFunction, <:ZeroCones}) = ci.value
function _allocateconstraint!(cone::Cone, f, s::ZeroCones)
    ci = cone.f
    cone.f += _dim(s)
    ci
end
constroffset(cone::Cone, ci::CI{<:MOI.AbstractFunction, <:LPCones}) = cone.f + ci.value
function _allocateconstraint!(cone::Cone, f, s::LPCones)
    ci = cone.l
    cone.l += _dim(s)
    ci
end
constroffset(cone::Cone, ci::CI{<:MOI.AbstractFunction, <:MOI.SecondOrderCone}) = cone.f + cone.l + ci.value
function _allocateconstraint!(cone::Cone, f, s::MOI.SecondOrderCone)
    push!(cone.qa, s.dimension)
    ci = cone.q
    cone.q += _dim(s)
    ci
end
constroffset(cone::Cone, ci::CI{<:MOI.AbstractFunction, <:MOI.PositiveSemidefiniteConeTriangle}) = cone.f + cone.l + cone.q + ci.value
function _allocateconstraint!(cone::Cone, f, s::MOI.PositiveSemidefiniteConeTriangle)
    push!(cone.sa, s.dimension)
    ci = cone.s
    cone.s += _dim(s)
    ci
end
constroffset(cone::Cone, ci::CI{<:MOI.AbstractFunction, <:MOI.ExponentialCone}) = cone.f + cone.l + cone.q + cone.s + ci.value
function _allocateconstraint!(cone::Cone, f, s::MOI.ExponentialCone)
    ci = 3cone.ep
    cone.ep += 1
    ci
end
constroffset(optimizer::SCSOptimizer, ci::CI) = constroffset(optimizer.cone, ci::CI)
MOIU.canallocateconstraint(::SCSOptimizer, ::Type{<:SF}, ::Type{<:SS}) = true
function MOIU.allocateconstraint!(optimizer::SCSOptimizer, f::F, s::S) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    CI{F, S}(_allocateconstraint!(optimizer.cone, f, s))
end

# Vectorized length for matrix dimension n
sympackedlen(n) = (n*(n+1)) >> 1
# Matrix dimension for vectorized length n
sympackeddim(n) = div(isqrt(1+8n) - 1, 2)
trimap(i::Integer, j::Integer) = i < j ? trimap(j, i) : div((i-1)*i, 2) + j
trimapL(i::Integer, j::Integer, n::Integer) = i < j ? trimapL(j, i, n) : i + div((2n-j) * (j-1), 2)
function _sympackedto(x, n, mapfrom, mapto)
    @assert length(x) == sympackedlen(n)
    y = similar(x)
    for i in 1:n, j in 1:i
        y[mapto(i, j)] = x[mapfrom(i, j)]
    end
    y
end
sympackedLtoU(x, n=sympackeddim(length(x))) = _sympackedto(x, n, (i, j) -> trimapL(i, j, n), trimap)
sympackedUtoL(x, n=sympackeddim(length(x))) = _sympackedto(x, n, trimap, (i, j) -> trimapL(i, j, n))

function sympackedUtoLidx(x::AbstractVector{<:Integer}, n)
    y = similar(x)
    map = sympackedLtoU(1:sympackedlen(n), n)
    for i in eachindex(y)
        y[i] = map[x[i]]
    end
    y
end


# Build constraint matrix
scalecoef(rows, coef, minus, s) = minus ? -coef : coef
scalecoef(rows, coef, minus, s::Union{MOI.LessThan, Type{<:MOI.LessThan}, MOI.Nonpositives, Type{MOI.Nonpositives}}) = minus ? coef : -coef
function _scalecoef(rows, coef, minus, d, rev)
    scaling = minus ? -1 : 1
    scaling2 = rev ? scaling / sqrt(2) : scaling * sqrt(2)
    output = copy(coef)
    diagidx = IntSet()
    for i in 1:d
        push!(diagidx, trimap(i, i))
    end
    for i in 1:length(output)
        if rows[i] in diagidx
            output[i] *= scaling
        else
            output[i] *= scaling2
        end
    end
    output
end
function scalecoef(rows, coef, minus, s::MOI.PositiveSemidefiniteConeTriangle)
    _scalecoef(rows, coef, minus, s.dimension, false)
end
function scalecoef(rows, coef, minus, ::Type{MOI.PositiveSemidefiniteConeTriangle})
    _scalecoef(rows, coef, minus, sympackeddim(length(rows)), true)
end
_varmap(f) = map(vi -> vi.value, f.variables)
_constant(s::MOI.EqualTo) = s.value
_constant(s::MOI.GreaterThan) = s.lower
_constant(s::MOI.LessThan) = s.upper
constrrows(::MOI.AbstractScalarSet) = 1
constrrows(s::MOI.AbstractVectorSet) = 1:MOI.dimension(s)
constrrows(optimizer::SCSOptimizer, ci::CI{<:MOI.AbstractScalarFunction, <:MOI.AbstractScalarSet}) = 1
constrrows(optimizer::SCSOptimizer, ci::CI{<:MOI.AbstractVectorFunction, <:MOI.AbstractVectorSet}) = 1:optimizer.cone.nrows[constroffset(optimizer, ci)]
MOIU.canloadconstraint(::SCSOptimizer, ::Type{<:SF}, ::Type{<:SS}) = true
MOIU.loadconstraint!(optimizer::SCSOptimizer, ci, f::MOI.SingleVariable, s) = MOIU.loadconstraint!(optimizer, ci, MOI.ScalarAffineFunction{Float64}(f), s)
function MOIU.loadconstraint!(optimizer::SCSOptimizer, ci, f::MOI.ScalarAffineFunction, s::MOI.AbstractScalarSet)
    a = sparsevec(_varmap(f), f.coefficients)
    # sparsevec combines duplicates with + but does not remove zeros created so we call dropzeros!
    dropzeros!(a)
    offset = constroffset(optimizer, ci)
    row = constrrows(s)
    i = offset + row
    # The SCS format is b - Ax ∈ cone
    # so minus=false for b and minus=true for A
    setconstant = _constant(s)
    optimizer.cone.setconstant[offset] = setconstant
    constant = f.constant - setconstant
    optimizer.data.b[i] = scalecoef(row, constant, false, s)
    append!(optimizer.data.I, fill(i, length(a.nzind)))
    append!(optimizer.data.J, a.nzind)
    append!(optimizer.data.V, scalecoef(row, a.nzval, true, s))
end
MOIU.loadconstraint!(optimizer::SCSOptimizer, ci, f::MOI.VectorOfVariables, s) = MOIU.loadconstraint!(optimizer, ci, MOI.VectorAffineFunction{Float64}(f), s)
orderval(val, s) = val
function orderval(val, s::MOI.PositiveSemidefiniteConeTriangle)
    sympackedUtoL(val, s.dimension)
end
orderidx(idx, s) = idx
function orderidx(idx, s::MOI.PositiveSemidefiniteConeTriangle)
    sympackedUtoLidx(idx, s.dimension)
end
function MOIU.loadconstraint!(optimizer::SCSOptimizer, ci, f::MOI.VectorAffineFunction, s::MOI.AbstractVectorSet)
    A = sparse(f.outputindex, _varmap(f), f.coefficients)
    # sparse combines duplicates with + but does not remove zeros created so we call dropzeros!
    dropzeros!(A)
    colval = zeros(Int, length(A.rowval))
    for col in 1:A.n
        colval[A.colptr[col]:(A.colptr[col+1]-1)] = col
    end
    @assert !any(iszero.(colval))
    offset = constroffset(optimizer, ci)
    rows = constrrows(s)
    optimizer.cone.nrows[offset] = length(rows)
    i = offset + rows
    # The SCS format is b - Ax ∈ cone
    # so minus=false for b and minus=true for A
    optimizer.data.b[i] = scalecoef(rows, orderval(f.constant, s), false, s)
    append!(optimizer.data.I, offset + orderidx(A.rowval, s))
    append!(optimizer.data.J, colval)
    append!(optimizer.data.V, scalecoef(A.rowval, A.nzval, true, s))
end

function MOIU.allocatevariables!(optimizer::SCSOptimizer, nvars::Integer)
    optimizer.cone = Cone()
    VI.(1:nvars)
end

function MOIU.loadvariables!(optimizer::SCSOptimizer, nvars::Integer)
    cone = optimizer.cone
    m = cone.f + cone.l + cone.q + cone.s + 3cone.ep + cone.ed
    I = Int[]
    J = Int[]
    V = Float64[]
    b = zeros(m)
    c = zeros(nvars)
    optimizer.data = Data(m, nvars, I, J, V, b, 0., c)
end

MOIU.canallocate(::SCSOptimizer, ::MOI.ObjectiveSense) = true
function MOIU.allocate!(optimizer::SCSOptimizer, ::MOI.ObjectiveSense, sense::MOI.OptimizationSense)
    optimizer.maxsense = sense == MOI.MaxSense
end
MOIU.canallocate(::SCSOptimizer, ::MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}) = true
function MOIU.allocate!(::SCSOptimizer, ::MOI.ObjectiveFunction, ::MOI.ScalarAffineFunction) end

MOIU.canload(::SCSOptimizer, ::MOI.ObjectiveSense) = true
function MOIU.load!(::SCSOptimizer, ::MOI.ObjectiveSense, ::MOI.OptimizationSense) end
MOIU.canload(::SCSOptimizer, ::MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}) = true
function MOIU.load!(optimizer::SCSOptimizer, ::MOI.ObjectiveFunction, f::MOI.ScalarAffineFunction)
    c0 = full(sparsevec(_varmap(f), f.coefficients, optimizer.data.n))
    optimizer.data.objconstant = f.constant
    optimizer.data.c = optimizer.maxsense ? -c0 : c0
end

function MOI.optimize!(optimizer::SCSOptimizer)
    cone = optimizer.cone
    m = optimizer.data.m
    n = optimizer.data.n
    A = sparse(optimizer.data.I, optimizer.data.J, optimizer.data.V)
    b = optimizer.data.b
    objconstant = optimizer.data.objconstant
    c = optimizer.data.c
    optimizer.data = nothing # Allows GC to free optimizer.data before A is loaded to SCS
    sol = SCS_solve(SCS.Indirect, m, n, A, b, c, cone.f, cone.l, cone.qa, cone.sa, cone.ep, cone.ed, cone.p)
    ret_val = sol.ret_val
    primal = sol.x
    dual = sol.y
    slack = sol.s
    objval = (optimizer.maxsense ? -1 : 1) * dot(c, primal) + objconstant
    optimizer.sol = MOISolution(ret_val, primal, dual, slack, objval)
end

# Implements getter for result value and statuses
# SCS returns one of the following integers:
# -7 SCS_INFEASIBLE_INACCURATE
# -6 SCS_UNBOUNDED_INACCURATE
# -5 SCS_SIGINT
# -4 SCS_FAILED
# -3 SCS_INDETERMINATE
# -2 SCS_INFEASIBLE  : primal infeasible, dual unbounded
# -1 SCS_UNBOUNDED   : primal unbounded, dual infeasible
#  0 SCS_UNFINISHED  : never returned, used as placeholder
#  1 SCS_SOLVED
#  2 SCS_SOLVED_INACCURATE
MOI.canget(optimizer::SCSOptimizer, ::MOI.TerminationStatus) = true
function MOI.get(optimizer::SCSOptimizer, ::MOI.TerminationStatus)
    s = optimizer.sol.ret_val
    @assert -7 <= s <= 2
    @assert s != 0
    if s in (-7, -6, 2)
        MOI.AlmostSuccess
    elseif s == -5
        MOI.Interrupted
    elseif s == -4
        MOI.NumericalError
    elseif s == -3
        MOI.SlowProgress
    else
        @assert -2 <= s <= 1
        MOI.Success
    end
end

MOI.canget(optimizer::SCSOptimizer, ::MOI.ObjectiveValue) = true
MOI.get(optimizer::SCSOptimizer, ::MOI.ObjectiveValue) = optimizer.sol.objval

MOI.canget(optimizer::SCSOptimizer, ::MOI.PrimalStatus) = true
function MOI.get(optimizer::SCSOptimizer, ::MOI.PrimalStatus)
    s = optimizer.sol.ret_val
    if s in (-3, 1, 2)
        MOI.FeasiblePoint
    elseif s in (-6, -1)
        MOI.InfeasibilityCertificate
    else
        MOI.InfeasiblePoint
    end
end
function MOI.canget(optimizer::SCSOptimizer, ::Union{MOI.VariablePrimal, MOI.ConstraintPrimal}, ::Type{<:MOI.Index})
    optimizer.sol.ret_val in (-6, -3, -1, 1, 2)
end
function MOI.get(optimizer::SCSOptimizer, ::MOI.VariablePrimal, vi::VI)
    optimizer.sol.primal[vi.value]
end
MOI.get(optimizer::SCSOptimizer, a::MOI.VariablePrimal, vi::Vector{VI}) = MOI.get.(optimizer, a, vi)
_unshift(optimizer::SCSOptimizer, offset, value, s) = value
_unshift(optimizer::SCSOptimizer, offset, value, s::Type{<:MOI.AbstractScalarSet}) = value + optimizer.cone.setconstant[offset]
reorderval(val, s) = val
function reorderval(val, ::Type{MOI.PositiveSemidefiniteConeTriangle})
    sympackedLtoU(val)
end
function MOI.get(optimizer::SCSOptimizer, ::MOI.ConstraintPrimal, ci::CI{<:MOI.AbstractFunction, S}) where S <: MOI.AbstractSet
    offset = constroffset(optimizer, ci)
    rows = constrrows(optimizer, ci)
    _unshift(optimizer, offset, scalecoef(rows, reorderval(optimizer.sol.slack[offset + rows], S), false, S), S)
end

MOI.canget(optimizer::SCSOptimizer, ::MOI.DualStatus) = true
function MOI.get(optimizer::SCSOptimizer, ::MOI.DualStatus)
    s = optimizer.sol.ret_val
    if s in (-3, 1, 2)
        MOI.FeasiblePoint
    elseif s in (-7, -2)
        MOI.InfeasibilityCertificate
    else
        MOI.InfeasiblePoint
    end
end
function MOI.canget(optimizer::SCSOptimizer, ::MOI.ConstraintDual, ::Type{<:CI})
    optimizer.sol.ret_val in (-7, -3, -2, 1, 2)
end
function MOI.get(optimizer::SCSOptimizer, ::MOI.ConstraintDual, ci::CI{<:MOI.AbstractFunction, S}) where S <: MOI.AbstractSet
    offset = constroffset(optimizer, ci)
    rows = constrrows(optimizer, ci)
    scalecoef(rows, reorderval(optimizer.sol.dual[offset + rows], S), false, S)
end

MOI.canget(optimizer::SCSOptimizer, ::MOI.ResultCount) = true
MOI.get(optimizer::SCSOptimizer, ::MOI.ResultCount) = 1
