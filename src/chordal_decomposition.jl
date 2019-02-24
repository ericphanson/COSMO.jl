function _contains(convex_sets::COSMO.CompositeConvexSet, t::Type{<:COSMO.AbstractConvexCone})
  for set in convex_sets.sets
    if typeof(set) <: t
      return true
    end
  end
  return false
end

function chordal_decomposition!(ws::COSMO.Workspace)
  # do nothing if no psd cones present in the problem
  if !_contains(ws.p.C, Union{COSMO.PsdConeTriangle{Float64}, COSMO.PsdCone{Float64}})
    ws.settings.decompose = false
    return nothing
  end
  ws.ci = ChordalInfo{Float64}(ws.p)

  find_sparsity_patterns!(ws)

  if ws.ci.num_decomp > 0
    # find transformation matrix H and new composite convex set
    find_decomposition_matrix!(ws)

    # augment the original system
    augment_system!(ws)
  else
    ws.settings.decompose = false
  end
  nothing
end

# analyse PSD cone constraints for chordal sparsity pattern
function find_sparsity_patterns!(ws)
  row_ranges = get_set_indices(ws.p.C.sets)
  sp_ind = 1
  for (k, C) in enumerate(ws.p.C.sets)
    psd_row_range = row_ranges[k]
    csp = find_aggregate_sparsity(ws.p.A, ws.p.b, psd_row_range, C)
    sp_ind = analyse_sparsity_pattern!(ws.ci, csp, ws.p.C.sets, C, k, sp_ind)
  end
end

function analyse_sparsity_pattern!(ci, csp, sets, C::PsdCone{T}, k, sp_ind) where {T <: Real}
  if length(csp) < C.dim
    ci.sp_arr[sp_ind] = COSMO.SparsityPattern(csp, C.sqrt_dim, C)
    push!(ci.psd_cones_ind, k)
    ci.num_decomp += 1
    return sp_ind + 1
  else
   sets[k] = COSMO.DensePsdCone{T}(C.dim)
   return sp_ind
  end
end

function analyse_sparsity_pattern!(ci, csp, sets, C::PsdConeTriangle{T}, k, sp_ind) where {T <: Real}
  if length(csp) < C.dim
    ci.sp_arr[sp_ind] = COSMO.SparsityPattern(csp, C.sqrt_dim, C)
    push!(ci.psd_cones_ind, k)
    ci.num_decomp += 1
    return sp_ind + 1
  else
   sets[k] = COSMO.DensePsdConeTriangle{T}(C.dim)
    return sp_ind
  end
end

analyse_sparsity_pattern!(ci, csp, sets, C::AbstractConvexSet, k, sp_ind) = sp_ind

function nz_rows(a::SparseMatrixCSC, ind::UnitRange{Int64}, DROP_ZEROS_FLAG::Bool)
  DROP_ZEROS_FLAG && dropzeros!(a)
  active = falses(length(ind))
  for r in a.rowval
    if in(r, ind)
      active[r - ind.start + 1] = true
    end
  end
  return findall(active)
end

function number_of_overlaps_in_rows(A::SparseMatrixCSC)
  # sum the entries row-wise
  numOverlaps = sum(A, dims = 2)
  ri = findall(x -> x > 1, numOverlaps)
  return ri, numOverlaps[ri]
end


function find_aggregate_sparsity(A, b, ind, C::Union{PsdCone{<: Real}, PsdConeTriangle{<: Real}})
  AInd = nz_rows(A, ind, false)
  # commonZeros = AInd[find(x->x==0,b[AInd])]
  bInd = findall(x -> x != 0, view(b, ind))
  commonNZeros = union(AInd, bInd)
  return commonNZeros
end
find_aggregate_sparsity(A, b, ind, C::AbstractConvexSet) = Int64[]

function vec_to_mat_ind(ind::Int64, n::Int64)
  ind > n^2 && error("Index ind out of range.")
  ind == 1 && (return 1, 1)

  r = ind % n

  if r == 0
    j = Int(ind / n)
    i = n
  else
    j = Int(floor(ind / n) + 1)
    i = r
  end
  return i, j
end

# Converts the matrix element (i, j) of A ∈ m x n into the corresponding linear index of v = vec(A)
function mat_to_vec_ind(i::Int64, j::Int64, m::Int64)
  (i > m || i <= 0 || j <= 0) && throw(BoundsError("Indices outside matrix bounds."))
  return (j - 1) * m + i
end

# Converts the matrix element (i, j) of A ∈ m x n into the corresponding linear index of v = svec(A, ::UpperTriangle)
function mat_to_svec_ind(i::Int64, j::Int64)
  if i <= j
    return div((j - 1) * j, 2) + i
  else
    return div((i - 1) * i, 2) + j
  end
end

# function svec_to_mat_ind(k::Int64)
#   j = isqrt(2 * k)
#   i = k - div((j - 1) * j, 2)
#   return i, j
# end


# function finds the transformation matrix H to decompose the vector s into its parts and stacks them into sbar
function find_decomposition_matrix!(ws)

  # allocate H and new decomposed cones
  n = COSMO.find_H_col_dimension(ws.p.C.sets, ws.ci.sp_arr)
  ws.ci.H = spzeros(ws.ci.originalM, n)

  # find number of decomposed and total sets and allocate structure for new compositve convex set
  num_total, num_new_psd_cones = COSMO.num_cone_decomposition(ws)
  @show(n, num_total, num_new_psd_cones)
  # decomposed_psd_cones = Array{COSMO.PsdCone}(undef, 0)
  C_new = Array{COSMO.AbstractConvexSet{Float64}}(undef, num_total)
  C_new[1] = COSMO.ZeroSet{Float64}(ws.ci.originalM)

  # loop over all convex sets and fill H and composite convex set accordingly
  row = 1
  col = 1
  sp_ind = 1
  set_ind = 2
  for (kkk, C) in enumerate(ws.p.C.sets)
    set_ind, sp_ind, col = COSMO.decompose!(ws.ci.H, C_new, set_ind, C, row, col, ws.ci.sp_arr, sp_ind)
    row += C.dim
  end
  ws.p.C = COSMO.CompositeConvexSet(C_new)
end

function decompose!(H::SparseMatrixCSC, C_new, set_ind::Int64, C::COSMO.AbstractConvexSet, row::Int64, col::Int64, sp_arr::Array{SparsityPattern}, sp_ind::Int64)
  H[row:row + C.dim - 1, col:col + C.dim - 1] = sparse(1.0I, C.dim, C.dim)
  C_new[set_ind] = C

  return set_ind + 1, sp_ind, col + C.dim
end

function decompose!(H::SparseMatrixCSC, C_new, set_ind::Int64,  C::COSMO.PsdCone{Float64}, row_start::Int64, col_start::Int64, sp_arr::Array{SparsityPattern}, sp_ind::Int64)
  sparsity_pattern = sp_arr[sp_ind]
  sntree = sparsity_pattern.sntree
  # original matrix size
  original_size = C.sqrt_dim

  for iii = 1:num_cliques(sntree)
    # new stacked size
    block_size = isqrt(sntree.nBlk[iii])

    c = COSMO.get_clique(sntree, iii)
    # the graph and tree algorithms determined the cliques vertices of an AMD-permuted matrix. Since the location of the data hasn't changed in reality, we have to map the clique vertices back
    c = map(v -> sparsity_pattern.ordering[v], c)
    sort!(c)
    col_start = COSMO.add_subblock_map!(H, c, block_size, original_size, row_start, col_start, C)

    # create and add new cone for subblock
    C_new[set_ind] = COSMO.PsdCone(block_size^2)
    set_ind += 1
  end
  return set_ind, sp_ind + 1, col_start
end

function decompose!(H::SparseMatrixCSC, C_new, set_ind::Int64,  C::COSMO.PsdConeTriangle{Float64}, row_start::Int64, col_start::Int64, sp_arr::Array{SparsityPattern}, sp_ind::Int64)
  sparsity_pattern = sp_arr[sp_ind]
  sntree = sparsity_pattern.sntree
  original_size = C.sqrt_dim

  for iii = 1:num_cliques(sntree)
    # new stacked size
    d = isqrt(sntree.nBlk[iii])
    block_dim = div((d + 1) * d, 2)

    c = COSMO.get_clique(sntree, iii)
    c = map(v -> sparsity_pattern.ordering[v], c)

    sort!(c)
    col_start = COSMO.add_subblock_map!(H, c, block_dim, original_size, row_start, col_start, C)

    # create and add new cone for subblock
    C_new[set_ind] = COSMO.PsdConeTriangle(block_dim)
    set_ind += 1
  end
  return set_ind, sp_ind + 1, col_start
end



# fills the corresponding entries of H for clique c
function add_subblock_map!(H::SparseMatrixCSC, clique_vertices::Array{Int64}, block_size::Int64, original_size::Int64, row_shift::Int64, col_shift::Int64, ::PsdCone{<: Real})
  num = 1
  for vj in clique_vertices
    for vi in clique_vertices
      row = mat_to_vec_ind(vi, vj, original_size)
      H[row_shift + row - 1, col_shift + num - 1] = 1.
      num += 1
    end
  end
  return (col_shift + block_size^2)::Int64
end

function add_subblock_map!(H::SparseMatrixCSC, clique_vertices::Array{Int64}, block_dim::Int64, original_size::Int64, row_shift::Int64, col_shift::Int64, ::PsdConeTriangle{<: Real})
  num = 1
  for vj in clique_vertices
    for vi in clique_vertices
      if vi <= vj
        row = mat_to_svec_ind(vi, vj)
        H[row_shift + row - 1, col_shift + num - 1] = 1.
        num += 1
      end
    end
  end
  return (col_shift + block_dim)::Int64
end


function find_H_col_dimension(sets, sp_arr)
  num_cols = 0
  sp_arr_ind = 1
  for C in sets
    dim, sp_arr_ind = decomposed_dim(C, sp_arr, sp_arr_ind)
    @show(C, dim ,sp_arr_ind)
    num_cols += dim
  end
  return num_cols::Int64
end

decomposed_dim(C::AbstractConvexSet, sp_arr::Array{SparsityPattern}, sp_arr_ind::Int64) = (C.dim, sp_arr_ind)
function decomposed_dim(C::PsdCone{<: Real}, sp_arr::Array{SparsityPattern}, sp_arr_ind::Int64)
  dim = sum(sp_arr[sp_arr_ind].sntree.nBlk)
  return dim::Int64, (sp_arr_ind + 1)::Int64
end

function decomposed_dim(C::PsdConeTriangle{<: Real}, sp_arr::Array{SparsityPattern}, sp_arr_ind::Int64)
  dim = sum(map(d -> div((d + 1) * d, 2), map(x -> isqrt(x), sp_arr[sp_arr_ind].sntree.nBlk)))
  return dim::Int64, (sp_arr_ind + 1)::Int64
end


function num_cone_decomposition(ws)
  num_sets = length(ws.p.C.sets)
  num_old_psd_cones = length(ws.ci.psd_cones_ind)
  num_new_psd_cones = 0
  for iii = 1:num_old_psd_cones
    sp = ws.ci.sp_arr[iii]
    num_new_psd_cones += COSMO.num_cliques(sp.sntree)
  end
  # the total number is the number of original non-psd cones + number of decomposed psd cones + 1 zeroset for the augmented system
  num_total = num_sets - num_old_psd_cones + num_new_psd_cones + 1
  return num_total, num_new_psd_cones
end

function augment_system!(ws)
  _augment!(ws.p, ws.ci.H)

  # increase the variable dimension
  ws.vars = Variables{Float64}(ws.p.model_size[1], ws.p.model_size[2], ws.p.C)
  nothing
end

function _augment!(problem, H::SparseMatrixCSC)
  mH, nH = size(H)
  m, n = size(problem.A)
  problem.P = blockdiag(problem.P, spzeros(nH, nH))
  problem.q = vec([problem.q; zeros(nH)])
  problem.A = [problem.A H; spzeros(nH, n) -sparse(1.0I, nH, nH)]
  problem.b = vec([problem.b; zeros(nH)])
  problem.model_size[1] = size(problem.A, 1)
  problem.model_size[2] = size(problem.A, 2)
  nothing
end


function reverse_decomposition!(ws::COSMO.Workspace, settings::COSMO.Settings)
  mO = ws.ci.originalM
  nO = ws.ci.originalN

  H = ws.ci.H

  vars = Variables{Float64}(mO, nO, ws.ci.originalC)
  vars.x .= ws.vars.x[1:nO]
  vars.s  .= SplitVector{Float64}(H * ws.vars.s[mO + 1:end], ws.ci.originalC)

  # fill dual variables such that μ_k  = H_k μ for k=1,...,p
  fill_dual_variables!(ws, vars)

  # if user requests, perform positive semidefinite completion on entries of μ that were not in the decomposed blocks
  ws.vars = vars
  ws.p.C = ws.ci.originalC
  settings.complete_dual && psd_completion!(ws)

  return nothing
end

function fill_dual_variables!(ws::COSMO.Workspace, vars::COSMO.Variables)
  mO = ws.ci.originalM
  H = ws.ci.H

  # this performs the operation μ = sum H_k^T *  μ_k causing an addition of (identical valued) overlapping blocks
  vars.μ .= H * ws.vars.μ[mO + 1:end]

  # # to remove the overlaps we take the average of the values for each overlap by dividing by the number of blocks that overlap in a particular entry, i.e. number of 1s in each row of H
  rowInd, nnzs = number_of_overlaps_in_rows(H)

  for iii=1:length(rowInd)
    ri = rowInd[iii]
    vars.μ[ri] .= vars.μ[ri] / nnzs[iii]
  end
end

# The psd entries of μ that correspond to the zeros in s are not constrained by the problem
# however, in order to make the dual psd cone positive semidefinite we have to do a
# positive semidefinite completion routine to choose the values
function psd_completion!(ws::COSMO.Workspace)

  # loop over psd cones
  row_ranges = get_set_indices(ws.p.C.sets)
  sp_ind = 1
  for (kkk, C) in enumerate(ws.p.C.sets)
    sp_ind = complete!(ws.vars.μ, C, ws.ci.sp_arr, sp_ind, row_ranges[kkk])
  end

  return nothing
end

complete!(μ::AbstractVector, ::AbstractConvexSet, sp_arr::Array{SparsityPattern}, sp_ind::Int64, rows::UnitRange{Int64}) = sp_ind

function complete!(μ::AbstractVector, C::PsdCone{<: Real}, sp_arr::Array{SparsityPattern}, sp_ind::Int64, rows::UnitRange{Int64})
  sp = sp_arr[sp_ind]
  M = reshape(view(μ, rows), C.sqrt_dim, C.sqrt_dim)
  psd_complete!(M, C.sqrt_dim, sp.sntree, sp.ordering)
  return sp_ind + 1
end

function complete!(μ::AbstractVector, C::PsdConeTriangle{<: Real}, sp_arr::Array{SparsityPattern}, sp_ind::Int64, rows::UnitRange{Int64})
  sp = sp_arr[sp_ind]

  μ_view = view(μ, rows)
  populate_upper_triangle!(C.X, μ_view, 1. / sqrt(2))
  psd_complete!(C.X, C.sqrt_dim, sp.sntree, sp.ordering)
  extract_upper_triangle!(C.X, μ_view, sqrt(2))
  return sp_ind + 1
end

# positive semidefinite completion (from Vandenberghe - Chordal Graphs..., p. 362)
# input: A - positive definite completable matrix
function psd_complete!(A::AbstractMatrix, N::Int64, sntree::SuperNodeTree, p::Array{Int64})

  ip = zeros(Int64, length(p))
  ip[p] = 1:length(p)

  # permutate matrix based on ordering p (p must be a vector type), W is in the order that the cliques are based on
  W = A[p, p]
  W = Matrix(W)
  num_cliques = COSMO.num_cliques(sntree)
  # go through supernode tree in descending order (given a post-ordering)
  snd_post_order = sntree.snd_post
  for j = (num_cliques - 1):-1:1
    snd_id = snd_post_order[j]

    # in order to obtain ν, α the vertex numbers of the supernode are mapped to the new position of the permuted matrix
    # index set of snd(i) sorted using the numerical ordering i,i+1,...i+ni
    ν = get_snd(sntree, snd_id)
    clique = get_clique(sntree, snd_id)
    # index set containing the elements of col(i) \ snd(i) sorted using numerical ordering σ(i)
    α = filter(x -> !in(x, ν), clique)

    # index set containing the row indizes of the lower-triangular zeros in column i (i: representative index) sorted by σ(i)
    i = ν[end]
    η = collect(i + 1:1:N)
    # filter out elements in lower triangular part of column i that are non-zero
    filter!(x -> !in(x, α), η)

    Waa = view(W, α, α)
    Waa = view(W, α, α)
    Wαν = view(W, α, ν)
    Wηα = view(W, η, α)

    Y = Waa \ Wαν

    W[η, ν] =  Wηα * Y
    # symmetry condition
    W[ν, η] = view(W, η, ν)'
  end

  # invert the permutation
  A[:, :] = W[ip, ip]
end


