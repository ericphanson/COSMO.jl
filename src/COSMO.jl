#__precompile__()
module COSMO

using SparseArrays, LinearAlgebra, SuiteSparse

export  assemble!, optimize!, warmStart!, reset!

const DefaultFloat = Float64
const DefaultInt   = Int64



include("./algebra.jl")
include("./projections.jl")
include("./settings.jl")            # TODO: unmodified - revisit
include("./types.jl")               # some types still need tidying
include("./constraint.jl")          # TODO: unmodified - revisit
include("./parameters.jl")          # TODO: unmodified - revisit
include("./residuals.jl")           # TODO: unmodified - revisit
include("./scaling.jl")             # TODO: set scaling / E scaling is broken
include("./kkt.jl")                 # TODO: unmodified - revisit.  Add lin solver type
include("./infeasibility.jl")       # TODO: stylistic fixes needed
include("./printing.jl")            # TODO: unmodified - revisit
include("./setup.jl")               # TODO: unmodified - revisit (short - consolidate?)
include("./graphs.jl")
include("./trees.jl")
include("./chordal_decomposition.jl")
include("./solver.jl")              # TODO: unmodified - revisit
include("./interface.jl")           # TODO: unmodified - revisit
include("./MOIWrapper.jl")

end #end module
