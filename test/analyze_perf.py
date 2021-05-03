import numpy as np
import scipy.optimize as opt
import sys

# We assume time = C * n^k
# log(time) = log(C) + k*log(n)

def model(n, C, k):
    return C * n**k

data = np.loadtxt(sys.argv[1])
n = data[:, 0]
time = data[:, 1]

popt, pcov = opt.curve_fit(model, n, time)
C, k = popt

print("C = %g" % C)
print("n^{%.3f}" % k)

fitted = C * n**k

import matplotlib.pyplot as plt
plt.plot(n, time, 'x', label="actual")
plt.plot(n, fitted, label="fitted")
plt.xlabel("n")
plt.ylabel("time [s]")
plt.legend(loc="best")
plt.show()
