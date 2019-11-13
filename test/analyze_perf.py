import numpy as np
import sys

# We assume time = C * n^k
# log(time) = log(C) + k*log(n)

data = np.loadtxt(sys.argv[1])
n = data[:, 0]
time = data[:, 1]

coeffs = np.polyfit(np.log(n), np.log(time), 1)

k = coeffs[0]
C = np.exp(coeffs[1])

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
