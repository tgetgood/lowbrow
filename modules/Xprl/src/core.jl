include("./Reader.jl")
import .Reader: read, readall

import DataStructures as ds

f = readall(open("./test.xprl"))
