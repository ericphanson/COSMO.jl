using COSMO, Test, LinearAlgebra, SparseArrays, Random
using QDLDL
rng = Random.MersenneTwister(2401)

function make_test_kkt(P,A,sigma,rho)

    R = length(rho)   == 1 ? ((1.)./rho[1])*I : Diagonal((1.)./rho)
    S = length(sigma) == 1 ? (sigma[1])*I : Diagonal(sigma)

    #compute the full KKT matrix
    K    = [P+S A'; A -R]
    return K
end

solver_types = [COSMO.QdldlKKTSolver
                COSMO.CholmodKKTSolver
                COSMO.PardisoDirectKKTSolver
                COSMO.PardisoIndirectKKTSolver]

solver_tols   = [1e-10,1e-10,1e-10,5e-5]

@testset "$(solver_types[i]) : KKT solver tests" for i = 1:length(solver_types)

    m = 10
    n = 20

    for rho1 in [rand(1), rand(1)[], rand(m)],
        rho2 in [rand(1), rand(m)],
        sigma in [rand(1), rand(1)[], rand(n)]

        P  = sparse(generate_pos_def_matrix(n,rng))
        A  = sprandn(m,n,0.2)
        b = randn(m+n)

        F = solver_types[i](P,A,sigma,rho1)
        J = make_test_kkt(P,A,sigma,rho1)
        x = copy(b)

        #test a single solve
        COSMO.solve!(F,x,b)
        @test norm(x - J\b) <= solver_tols[i]

        #test a rho update and solve
        J = make_test_kkt(P,A,sigma,rho2)
        x = copy(b)
        COSMO.update_rho!(F,rho2)
        COSMO.solve!(F,x,b)
        @test norm(x - J\b) <= solver_tols[i]

    end

end

nothing
