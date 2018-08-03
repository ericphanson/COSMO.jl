using PyPlot, JLD

data = JLD.load("./meszarosComparison.jld")
resCost = data["resCost"]
resIter = data["resIter"]
resX = data["resX"]
fileNames = data["fileNames"]
ind = find(x->x == :Max_iter_reached,resStatus[1:129,1])
ind = find(x->x < 1500,resIter[1:129,3])



cc =  ["#1f77b4" "#ff7f0e" "#2ca02c" "#d62728" "#9467bd" "#8c564b"]

PyPlot.figure(1,facecolor="white",figsize=(12,5))
PyPlot.xticks(fontsize=15)
PyPlot.yticks(fontsize=15)
PyPlot.plot(1:1:nn,resIter[1:nn,1],label="OSSDP(off)","--",color=cc[1])
PyPlot.plot(1:1:nn,resIter[1:nn,2],label="OSSDP(on)",color=cc[1])
PyPlot.plot(1:1:nn,resIter[1:nn,3],label="OSQP1(off)","--",color=cc[2])
PyPlot.plot(1:1:nn,resIter[1:nn,4],label="OSQP1(on)",color=cc[2])
PyPlot.grid(true)
PyPlot.xticks(1:1:nn)
PyPlot.xlabel("Problem",fontsize=15)
PyPlot.ylabel("Iterations to Convergence",fontsize=15)
PyPlot.legend(ncol = 4,bbox_to_anchor=(0., 1.02, 1., .102),loc=3)
PyPlot.savefig("/Users/Micha/Dropbox/Research/OSSDP/Notes/Scaling_experiments/figs/qp_compare.eps")

PyPlot.figure(2,facecolor="white",figsize=(12,5))
 PyPlot.xticks(fontsize=15)
      PyPlot.yticks(fontsize=15)
PyPlot.plot(1:1:nn,resIter[1:nn,1],label=L"\rho=1.0 (off)","--",color=cc[1])
PyPlot.plot(1:1:nn,resIter[1:nn,2],label=L"\rho=1.0 (on)",color=cc[1])
PyPlot.plot(1:1:nn,resIter[1:nn,3],label=L"\rho=100.0 (off)","--",color=cc[2])
PyPlot.plot(1:1:nn,resIter[1:nn,4],label=L"\rho=100.0 (on)",color=cc[2])
PyPlot.plot(1:1:nn,resIter[1:nn,5],label=L"\rho=1000.0 (off)","--",color=cc[3])
PyPlot.plot(1:1:nn,resIter[1:nn,6],label=L"\rho=1000.0 (on)",color=cc[3])
PyPlot.grid(true)
PyPlot.xticks(1:1:nn)
PyPlot.xlabel("Problem number",fontsize=15)
PyPlot.ylabel("Iterations to Convergence",fontsize=15)
PyPlot.legend(ncol = 6,bbox_to_anchor=(0., 1.02, 1., .102),loc=3)

PyPlot.savefig("/Users/Micha/Dropbox/Research/OSSDP/Notes/Scaling_experiments/figs/qp_rho.eps")
