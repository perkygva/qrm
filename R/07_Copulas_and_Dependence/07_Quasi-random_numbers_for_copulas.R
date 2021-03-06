## By Marius Hofert

## Pseudo-random numbers vs quasi-random numbers


library(qrng)
library(copula)

n <- 1000 # sample size


### 1 Examples #################################################################

### 1.1 Independence copula ####################################################

## Sample
set.seed(271) # for reproducibility
U <- matrix(runif(n*2), ncol = 2) # pseudo-random numbers
U. <- ghalton(n, d = 2) # quasi-random numbers (faster alternative: sobol())

## Plot
layout(rbind(1:2))
plot(U,  xlab = expression(U[1]), ylab = expression(U[2]))
plot(U., xlab = expression(U[1]), ylab = expression(U[2]))


### 1.2 t copula ###############################################################

## Define the copula
nu <- 3 # degrees of freedom
th <- iTau(tCopula(df = nu), tau = 0.5) # correlation parameter
cop.t3 <- tCopula(param = th, df = nu) # t copula

## Sample
U.t <-  cCopula(U,  copula = cop.t3, inverse = TRUE)
U.t. <- cCopula(U., copula = cop.t3, inverse = TRUE)

## Plot
layout(rbind(1:2))
plot(U.t,  xlab = expression(U[1]), ylab = expression(U[2]))
plot(U.t., xlab = expression(U[1]), ylab = expression(U[2]))
layout(1) # reset layout

## 3d plot
U.3d. <- ghalton(n, d = 3)
cop <- tCopula(param = th, dim = 3, df = nu)
U.t.3d. <- cCopula(U.3d., copula = cop, inverse = TRUE)
cloud2(U.t.3d., xlab = expression(U[1]), ylab = expression(U[2]),
       zlab = expression(U[3])) # not much visible
pairs2(U.t.3d., labels.null.lab = "U")
## Structure doesn't *look* very convincing, but it is a low-discrepancy sequence


### 1.3 Clayton copula #########################################################

## Define the copula
th <- iTau(claytonCopula(), tau = 0.5)
cop.C <- claytonCopula(th)

## Sample
U.C <-  cCopula(U,  copula = cop.C, inverse = TRUE)
U.C. <- cCopula(U., copula = cop.C, inverse = TRUE)

## Plot
layout(rbind(1:2))
plot(U.C,  xlab = expression(U[1]), ylab = expression(U[2]))
plot(U.C., xlab = expression(U[1]), ylab = expression(U[2]))
layout(1) # reset layout


### 2 Why considering quasi-random numbers? ####################################

## Auxiliary function for approximately computing P(U_1 > u_1, U_2 > u_2) by
## simulation (also known as Monte Carlo integration)
survival_prob <- function(n, copula, u)
{
    stopifnot(n >= 1, inherits(copula, "Copula"), length(u) == 2, 0 < u, u < 1)

    ## Pseudo-sampling
    ## Note: Using (*) below would be significantly faster but the comparison
    ##       would be unfair (unless we also use a faster QRNG copula method)
    clock <- proc.time() # start watch
    U  <- cCopula(matrix(runif(n * 2), ncol = 2), copula = copula, inverse = TRUE) # (*) rCopula(n, copula = copula)
    prob <- mean(rowSums(U > rep(u, each = n)) == 2) # = sum(<rows with both entries TRUE>) / n
    usr.time <- 1000 * (proc.time() - clock)[[1]] # time in ms

    ## Quasi-sampling
    clock <- proc.time() # start clock
    U. <- cCopula(ghalton(n, d = 2), copula = copula, inverse = TRUE)
    prob. <- mean(rowSums(U. > rep(u, each = n)) == 2) # = sum(<rows with both entries TRUE>) / n
    usr.time. <- 1000 * (proc.time() - clock)[[1]] # time in ms

    ## Return
    list(PRNG = c(prob = prob,  rt = usr.time),
         QRNG = c(prob = prob., rt = usr.time.))
}

## Simulate the probabilities of falling in (u_1,1] x (u_2,1].
B <- 500 # number of replications
n <- 2000 # sample size
u <- c(0.99, 0.99) # lower-left endpoint of the considered cube
set.seed(271) # for reproducibility
system.time(res <- lapply(1:B, function(b) survival_prob(n, copula = cop.t3, u = u))) # simulate
## ~ 18s (mostly because of cCopula(); see profiling below)

## Grab out the values
str(res, max.level = 1) # structure of the result
prob  <- sapply(res, function(x) x[["PRNG"]][["prob"]])
prob. <- sapply(res, function(x) x[["QRNG"]][["prob"]])
rt    <- sapply(res, function(x) x[["PRNG"]][["rt"]])
rt.   <- sapply(res, function(x) x[["QRNG"]][["rt"]])

## Estimate the probabilities and compare with true probability
probs <- c(PRNG = mean(prob), QRNG = mean(prob.),
           true = 1 - u[1] - u[2] + pCopula(u, copula = cop.t3))
abs(probs["PRNG"] - probs["true"])
abs(probs["QRNG"] - probs["true"]) # => slightly closer...
##... but not necessarily for smaller B or n

## Boxplot of the computed probabilities
boxplot(list(PRNG = prob, QRNG = prob.),
        main = "Simulated exceedance probability"~P(U[1] > u[1], U[2] > u[2]))
## => QRNGs provide a smaller variance
(vr <- var(prob.)/var(prob)) # estimated variance-reduction fraction

## Boxplot of the measured run times in milliseconds
boxplot(list(PRNG = rt, QRNG = rt.))
boxplot(list(PRNG = rt, QRNG = rt.), outline = FALSE) # without outliers (points)
## => QRNG takes a bit longer
(rtf <- mean(rt.)/mean(rt)) # estimated run-time factor

## Effort comparison
vr * rtf # => effort of QRNG only a fraction of PRNG

## Remark:
## - QRNGs can estimate high quantile probabilities with a smaller variance
##   (=> need less random variates to obtain the same precision => good for
##   memory/storage-intensive methods).
## - QRNGs can also be faster than PRNGs (see sobol() below) but that's not
##   the case for the generalized Halton sequence used here; this may depend
##   on the dimension, too.
## - If (*) is used for pseudo-sampling from the t copula, run time is
##   significantly smaller, the total effort slightly above 1. It can
##   then still be advantages to use quasi-random numbers (because of
##   memory/storage limitations)
## - Both methods could be made significantly faster by not using cCopula(),
##   but that requires more work; see Cambou, Hofert, Lemieux ("Quasi-random
##   numbers for copula models")

## Profiling: See where run time is spent
Rprof(profiling <- tempfile(), line.profiling = TRUE) # enable profiling
res <- lapply(1:B, function(b) survival_prob(n, copula = cop.t3, u = u))
Rprof(NULL) # disable profiling
(profile <- summaryRprof(profiling, lines = "both")) # get a summary
## => by.total => most of the run time is spent in cCopula()

## Just comparing drawing pseudo- and quasi-random numbers
n <- 1e7 # 10 Mio
system.time(runif(n)) # PRNG
system.time(ghalton(n, d = 1)) # QRNG
system.time(sobol(n,   d = 1)) # Faster QRNG
## => also depends on the *type* of QRNG
