# Primal infeasible test problems
# Problems with m1 feasible equality constraints, and one infeasible psd constraint
# x >= 0, elements in A >=0, elements in b < 0 and s=[s1,s2,s3] with s1 in {0}, s2 in {R+} and s3 in psd-cone
# s3 cannot be found since Ax > 0 and b < 0 (Ax + s = b)

nn = 1
rng = Random.MersenneTwister(1313)

@testset "Primal infeasible QP problems - Testset 2" begin
  for iii = 1:nn

    # choose size of problem
    n = rand(rng,10:50)
    r = rand(rng,2:10)
    m2 = r^2 # one sdp cone constraint of size r
    m1 = m2 #m1 equality constraints
    m = m1+m2
    A = sprand(rng,m,n,0.8)*50
    xtrue = rand(rng,n,1)*50
    s1 = zeros(m1,1)
    b1 = A[1:m1,:]*xtrue + s1 #find feasible part of b that corresponds to the equality constraints
    b2 = -rand(m2,1) #pick vectorized matrix with all entries <= 0 --> to enforce infeasibility

    # add the constraint x >= 0
    b = [b1;zeros(n);b2]
    b = vec(b)
    A = [A[1:m1,:]; -sparse(1.0I,n,n);A[m1+1:end,:]]

    # create dual feasible problem Px+q+A'y = 0, and y in K*
    P = Helper.generatePosDefMatrix(n,rng)
    ytrue_1 = randn(rng,m1,1)*50
    ytrue_2 = rand(rng,n,1)*50
    ytrue_3 = vec(Helper.generatePosDefMatrix(r,rng))
    ytrue = [ytrue_1;ytrue_2;ytrue_3]
    q = (-P*xtrue - A'*ytrue)[:]

    Kf = m1
    Kl = n
    Kq = []
    Ks = [r^2]

     K = QOCS.Cone(Kf,Kl,Kq,Ks)
     settings = QOCS.Settings(rho=0.1,sigma=1e-6,alpha=1.6,max_iter=3000,verbose=false,check_termination=10,scaling = 10,eps_abs = 1e-5,eps_rel=1e-5,adaptive_rho=true)

     res,nothing = QOCS.solve(P,q,A,b,K,settings);
     @test res.status == :Primal_infeasible
  end
end