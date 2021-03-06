# -------------------------------------
# Results and related sub structures
# -------------------------------------

"""
	ResultTimes{T <: AbstractFloat}

Part of the Result object returned by the solver. ResultTimes contains timing results for certain parts of the algorithm:

Time Name  | Description
---  | :---
solver_time | Total time used to solve the problem
setup_time |  Setup time = graph\\_time + init\\_factor\\_time + scaling\\_time
scaling_time | Time to scale the problem data
graph_time | Time used to perform chordal decomposition
init\\_factor\\_time | Time used for initial factorisation of the system of linear equations
factor\\_update\\_time | Sum of times used to refactor the system of linear equations due to rho
iter_time | Time spent in iteration loop
proj_time | Time spent in projection functions
post_time | Time used for post processing

By default COSMO only measures `solver_time`, `setup_time` and `proj_time`. To measure the other times set `verbose_timing = true`.
"""
mutable struct ResultTimes{T <: AbstractFloat}
	solver_time::T
	setup_time::T
	scaling_time::T
	graph_time::T
	init_factor_time::T
	factor_update_time::T
	iter_time::T
	proj_time::T
	post_time::T
end

ResultTimes{T}() where{T} = ResultTimes{T}(T(NaN), T(NaN), T(NaN), T(NaN), T(NaN), T(NaN), T(NaN), T(NaN), T(NaN))
ResultTimes(T::Type = DefaultFloat) = ResultTimes{T}()

function Base.show(io::IO, obj::ResultTimes)
  obj.iter_time != 0 ? verbose = true : verbose = false
  print(io,"Solver time:\t$(round.(obj.solver_time, digits = 4))s ($(round.(obj.solver_time * 1000, digits = 2))ms)\n",
"Setup time:\t$(round.(obj.setup_time, digits = 4))s ($(round.(obj.setup_time * 1000, digits = 2))ms)\n",
"Proj time:\t$(round.(obj.proj_time, digits = 4))s ($(round.(obj.proj_time * 1000, digits = 2))ms)\n")
  if verbose
    print(io,"Iter time:\t$(round.(obj.iter_time, digits = 4))s ($(round.(obj.iter_time * 1000, digits = 2))ms)\n",
    "Scaling time:\t$(round.(obj.scaling_time, digits = 4))s ($(round.(obj.scaling_time * 1000, digits = 2))ms)\n",
    "Graph time:\t$(round.(obj.graph_time, digits = 4))s ($(round.(obj.graph_time * 1000, digits = 2))ms)\n",
    "Initial Factor time:\t$(round.(obj.init_factor_time, digits = 4))s ($(round.(obj.init_factor_time * 1000, digits = 2))ms)\n",
    "Factor update time:\t$(round.(obj.factor_update_time, digits = 4))s ($(round.(obj.factor_update_time * 1000, digits = 2))ms)\n",
    "Post time:\t$(round.(obj.post_time, digits = 4))s ($(round.(obj.post_time * 1000, digits = 2))ms)\n")
  end
end

"""
    ResultInfo{T <: AbstractFloat}

Object that contains further information about the primal residual, the dual residuals and the rho updates.
"""
struct ResultInfo{T <: AbstractFloat}
	r_prim::T
	r_dual::T
	rho_updates::Vector{T}
end

ResultInfo(rp, rd, ro, rho_updates) = ResultInfo{DefaultFloat}(rp, rd, rho_updates)

"""
    Result{T <: AbstractFloat}

Object returned by the COSMO solver after calling `optimize!(model)`. It has the following fields:


Fieldname | Type | Description
---  | :--- | :---
x | Vector{T}| Primal variable
y | Vector{T}| Dual variable
s | Vector{T}| (Primal) set variable
obj_val | T | Objective value
iter | Int64 | Number of iterations
status | Symbol | Solution status
info | COSMO.ResultInfo | Struct with more information
times | COSMO.ResultTimes | Struct with several measured times
"""
struct Result{T <: AbstractFloat}
    x::Vector{T}
    y::Vector{T}
    s::Vector{T}
    obj_val::T
    iter::Int64
    status::Symbol
    info::ResultInfo{T}
    times::ResultTimes{T}

    function Result{T}() where {T <: AbstractFloat}
      return new(zeros(T, 1), zeros(T, 1), zeros(T, 1), zero(T), 0, :Unsolved, ResultInfo{T}(0.,0., T[]), ResultTimes{T}())
    end

    function Result{T}(x, y, s, obj_val, iter, status, info, times) where {T <: AbstractFloat}
      return new(x, y, s, obj_val, iter, status, info, times)
    end

end

function Base.show(io::IO, obj::Result)
	print(io,">>> COSMO - Results\nStatus: $(obj.status)\nIterations: $(obj.iter)\nOptimal Objective: $(round.(obj.obj_val, digits = 2))\nRuntime: $(round.(obj.times.solver_time * 1000, digits = 2))ms\nSetup Time: $(round.(obj.times.setup_time * 1000, digits = 2))ms\n")
	!isnan(obj.times.iter_time) && print("Avg Iter Time: $(round.((obj.times.iter_time / obj.iter) * 1000, digits = 2))ms")
end

# -------------------------------------
# Problem scaling
# -------------------------------------

struct ScaleMatrices{Tf <: AbstractFloat}
	D::Union{UniformScaling{Bool}, Diagonal{Tf, Vector{Tf}} }
	Dinv::Union{UniformScaling{Bool}, Diagonal{Tf, Vector{Tf}} }
	E::Union{UniformScaling{Bool}, Diagonal{Tf, Vector{Tf}} }
	Einv::Union{UniformScaling{Bool}, Diagonal{Tf, Vector{Tf}} }
	c::Base.RefValue{Tf}
	cinv::Base.RefValue{Tf}
end

ScaleMatrices(args...) = ScaleMatrices{DefaultFloat}(args...)

ScaleMatrices{T}() where {T} = ScaleMatrices(I, I, I, I, Base.RefValue{T}(one(T)), Base.RefValue{T}(one(T)))

function ScaleMatrices{T}(m, n) where{T}
	D    = Diagonal(ones(T, n))
	Dinv = Diagonal(ones(T, n))
	E    = Diagonal(ones(T, m))
	Einv = Diagonal(ones(T, m))
	c    = Base.RefValue{T}(one(T))
	cinv = Base.RefValue{T}(one(T))
	ScaleMatrices(D, Dinv, E, Einv, c, cinv)
end

# -------------------------------------
# a collection of flags
# -------------------------------------

mutable struct Flags
	FACTOR_LHS::Bool
	INFEASIBILITY_CHECKS::Bool
	REVERSE_SCALE_PROBLEM_DATA::Bool
	Flags() = new(true, true, true)
end

# -------------------------------------
# Problem data
# -------------------------------------

mutable struct ProblemData{T<:Real}
	P::AbstractMatrix{T}
	q::Vector{T}
	A::AbstractMatrix{T}
	b::Vector{T}
	C::CompositeConvexSet{T}
	model_size::Array{Integer,1}

	function ProblemData{T}() where{T}
		return new(
			spzeros(T, 1, 1),             #P
			T[],                        #q
			spzeros(T, 1, 1),             #A
			T[],                        #b
			COSMO.CompositeConvexSet([COSMO.ZeroSet{T}(1)]),     #C
			[0; 0])                 #model size
	end
end

ProblemData(args...) = ProblemData{DefaultFloat}(args...)

# ---------------------------
# Struct to hold clique and sparsity data for a constraint
# ---------------------------

mutable struct SparsityPattern
  sntree::SuperNodeTree
  ordering::Array{Int64}
  reverse_ordering::Array{Int64}
  row_range::UnitRange{Int64} # the starting row of the psd cone in the original problem
  cone_ind::Int64 # this is the ind of the original psd cone in ws.p.C that is decomposed
  nz_ind_map::SparseVector{Int64, Int64} # maps a matrix entry k = svec(i, j) to the location of the entry in the sparse data structure

  # constructor for sparsity pattern
  function SparsityPattern(L::SparseMatrixCSC, N::Int64, ordering::Array{Int64, 1}, merge_strategy::Union{Type{<: AbstractMergeStrategy}, OptionsFactory{<: AbstractMergeStrategy}}, row_range::UnitRange{Int64}, cone_ind::Int64, nz_ind_map::SparseVector{Int64, Int64})

    merge_strategy = merge_strategy()
    sntree = SuperNodeTree(L, merge_strategy)

    # clique merging
    sntree.num > 1 && merge_cliques!(sntree)

    # reorder vertices in supernodes to have consecutive order
    # necessary for equal column structure for psd completion
    reorder_snd_consecutively!(sntree, ordering)

    # undo the reordering and sort
    # for iii = 1:sntree.num
    #   sep = get_sep(sntree, iii)
    #   snd = get_snd(sntree, iii)
    #   map!(v -> ordering[v], sep)
    #   map!(v -> ordering[v], snd)
    #   sort!(sep)
    #   sort!(snd)
    # end

    # for each clique determine the number of entries of the block represented by that clique
    calculate_block_dimensions!(sntree)#, merge_strategy)

    return new(sntree, ordering, invperm(ordering), row_range, cone_ind, nz_ind_map)
  end

  # For debugging
  function SparsityPattern(sntree::SuperNodeTree, ordering::Array{Int64}, reverse_ordering::Array{Int64}, row_range::UnitRange{Int64}, cone_ind::Int64)
    return new(sntree, ordering, reverse_ordering, row_range, cone_ind)
  end
end

# -------------------------------------
# Chordal Decomposition Information
# -------------------------------------
mutable struct ChordalInfo{T <: Real}
  decompose::Bool # an internal flag to check if problem has been decomposed
  originalM::Int64
  originalN::Int64
  originalC::CompositeConvexSet{T}
  H::SparseMatrixCSC{T}
  sp_arr::Array{COSMO.SparsityPattern}
  psd_cones_ind::Array{Int64} # stores the position of decomposable psd cones in the composite convex set
  num_psd_cones::Int64 # number of psd cones of original problem
  num_decomposable::Int64 #number of decomposable cones
  num_decom_psd_cones::Int64 #total number of psd cones after decomposition
  L::SparseMatrixCSC{T} #pre allocate memory for QDLDL
  cone_map::Dict{Int64, Int64} # map every cone in the decomposed problem to the equivalent or undecomposed cone in the original problem
  function ChordalInfo{T}(problem::COSMO.ProblemData{T}, settings::COSMO.Settings) where {T}
    originalM = problem.model_size[1]
    originalN = problem.model_size[2]
    originalC = deepcopy(problem.C)
    num_psd_cones = length(findall(x -> typeof(x) <: Union{PsdConeTriangle{Float64}, PsdCone{Float64}} , problem.C.sets))
    # allocate sparsity pattern for each cone
    sp_arr = Array{COSMO.SparsityPattern}(undef, num_psd_cones)
    cone_map = Dict{Int64, Int64}()

    return new(settings.decompose, originalM, originalN, originalC, spzeros(1, 1), sp_arr, Int64[], num_psd_cones, 0, 0, spzeros(1, 1), cone_map)
  end

	function ChordalInfo{T}() where{T}
		C = COSMO.CompositeConvexSet([COSMO.ZeroSet{T}(1)])
		return new(false, 0, 0, C, spzeros(1, 1), COSMO.SparsityPattern[], [1])
	end

end

# -------------------------------------
# Structure of internal iterate variables
# -------------------------------------

struct Variables{T}
	x::Vector{T}
	s::SplitVector{T}
	μ::Vector{T}

	function Variables{T}(m::Int, n::Int, C::AbstractConvexSet{T}) where{T}
		m == C.dim || throw(DimensionMismatch("set dimension is not m"))
		x = zeros(T, n)
		s = SplitVector(zeros(T, m), C)
		μ = zeros(T, m)
		new(x, s, μ)
	end
end

Variables(args...) = Variables{DefaultFloat}(args...)

struct UtilityVariables{T}
  vec_m::Vector{T}
  vec_n::Vector{T}
  vec_n2::Vector{T}

  function UtilityVariables{T}(m::Int64, n::Int64) where {T}
    new(zeros(T, m), zeros(T, n), zeros(T, n))
  end
end

UtilityVariables(args...) = UtilityVariables{DefaultFloat}(args...)

# -------------------------------------
# Top level container for all solver data
# -------------------------------------
"""
	Workspace()

Initializes an empty COSMO model that can be filled with problem data using `assemble!(model, P, q,constraints; [settings, x0, s0, y0])`.
"""
mutable struct Workspace{T}
	p::ProblemData{T}
	settings::Settings
	sm::ScaleMatrices{T}
	ci::ChordalInfo{T}
	vars::Variables{T}
  	utility_vars::UtilityVariables{T}
	ρ::T
	ρvec::Vector{T}
	kkt_solver::Union{AbstractKKTSolver,Nothing}
	flags::Flags
	rho_updates::Vector{T} #keep track of the rho updates and the number of refactorisations
	times::ResultTimes{Float64} #Always 64 bit regardless of data type?

	#constructor
	function Workspace{T}() where {T}
		p = ProblemData{T}()
		sm = ScaleMatrices{T}()
		vars = Variables{T}(1, 1, p.C)
    	uvars = UtilityVariables{T}(1, 1)
		ci = ChordalInfo{T}()
		return new(p, Settings(), sm, ci, vars,  uvars, zero(T), T[], nothing, Flags(), T[], ResultTimes())
	end
end
Workspace(args...) = Workspace{DefaultFloat}(args...)

Base.show(io::IO, model::COSMO.Workspace{T}) where {T} = println(io, "A COSMO Model")


# Type alias facing the user
"""
	Model()

Initializes an empty COSMO model that can be filled with problem data using `assemble!(model, P, q,constraints; [settings, x0, s0, y0])`.
"""
const Model = Workspace;
