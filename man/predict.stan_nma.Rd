% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/predict.R
\name{predict.stan_nma}
\alias{predict.stan_nma}
\title{Predictions of absolute effects from NMA models}
\usage{
\method{predict}{stan_nma}(
  object,
  ...,
  baseline = NULL,
  newdata = NULL,
  study = NULL,
  trt_ref = NULL,
  type = c("link", "response"),
  level = c("aggregate", "individual"),
  probs = c(0.025, 0.25, 0.5, 0.75, 0.975),
  summary = TRUE
)
}
\arguments{
\item{object}{A \code{stan_nma} object created by \code{\link[=nma]{nma()}}.}

\item{...}{Additional arguments (not used).}

\item{baseline}{An optional \code{\link[=distr]{distr()}} distribution for the baseline response
(i.e. intercept) on the linear predictor scale, about which to produce
absolute effects. For example, in a model with a logit link, this would be
a distribution for the baseline log odds of an event. If \code{NULL},
predictions are produced using the baseline response for each study in the
network with IPD or arm-based AgD.}

\item{newdata}{Only required if a regression model is fitted and \code{baseline}
is specified. A data frame of covariate details, for which to produce
predictions. Column names must match variables in the regression model.

If \code{type = "aggregate"} this should either be a data frame with integration
points as produced by \code{\link[=add_integration]{add_integration()}} (one row per study), or a data
frame with individual covariate values (one row per individual) which are
summarised over.

If \code{type = "individual"} this should be a data frame of individual
covariate values, one row per individual.

If \code{NULL}, predictions are produced for all studies with IPD and/or
arm-based AgD in the network, depending on the value of \code{type}.}

\item{study}{Column of \code{newdata} which specifies study names or IDs. When not
specified: if \code{newdata} contains integration points produced by
\code{\link[=add_integration]{add_integration()}}, studies will be labelled sequentially by row;
otherwise data will be assumed to come from a single study.}

\item{trt_ref}{Treatment to which the \code{baseline} response distribution
refers, if \code{baseline} is specified. By default, the baseline response
distribution will refer to the network reference treatment. Coerced to
character string.}

\item{type}{Whether to produce predictions on the \code{"link"} scale (the
default, e.g. log odds) or \code{"response"} scale (e.g. probabilities).}

\item{level}{The level at which predictions are produced, either
\code{"aggregate"} (the default), or \code{"individual"}. If \code{baseline} is not
specified, predictions are produced for all IPD studies in the network if
\code{type} is \code{"individual"} or \code{"aggregate"}, and for all arm-based AgD
studies in the network if \code{type} is \code{"aggregate"}.}

\item{probs}{Numeric vector of quantiles of interest to present in computed
summary, default \code{c(0.025, 0.25, 0.5, 0.75, 0.975)}}

\item{summary}{Logical, calculate posterior summaries? Default \code{TRUE}.}
}
\value{
A \link{nma_summary} object if \code{summary = TRUE}, otherwise a list
containing a 3D MCMC array of samples and (for regression models) a data
frame of study information.
}
\description{
Obtain predictions of absolute effects from NMA models fitted with \code{\link[=nma]{nma()}}.
For example, if a model is fitted to binary data with a logit link, predicted
outcome probabilities or log odds can be produced.
}
\examples{
## Smoking cessation
# Set up network of smoking cessation data
head(smoking)

smk_net <- set_agd_arm(smoking,
                       study = studyn,
                       trt = trtc,
                       r = r,
                       n = n,
                       trt_ref = "No intervention")

# Print details
smk_net

\donttest{
# Fitting a random effects model
smk_fit_RE <- nma(smk_net,
                  trt_effects = "random",
                  prior_intercept = normal(scale = 100),
                  prior_trt = normal(scale = 100),
                  prior_het = normal(scale = 5))

smk_fit_RE
}

\donttest{
# Predicted log odds of success in each study in the network
predict(smk_fit_RE)

# Predicted probabilities of success in each study in the network
(smk_pred_RE <- predict(smk_fit_RE, type = "response"))
plot(smk_pred_RE, ref_line = c(0, 1))

# Predicted probabilities in a population with a baseline log odds of
# response on No Intervantion given a Normal distribution with mean -2
# and SD 0.15
predict(smk_fit_RE, baseline = distr(qnorm, mean = -2, sd = 0.15))
}

## Plaque psoriasis ML-NMR
# Set up plaque psoriasis network combining IPD and AgD
library(dplyr)
pso_ipd <- filter(plaque_psoriasis_ipd,
                  studyc \%in\% c("UNCOVER-1", "UNCOVER-2", "UNCOVER-3"))

pso_agd <- filter(plaque_psoriasis_agd,
                  studyc == "FIXTURE")

head(pso_ipd)
head(pso_agd)

pso_ipd <- pso_ipd \%>\%
  mutate(# Variable transformations
    bsa = bsa / 100,
    prevsys = as.numeric(prevsys),
    psa = as.numeric(psa),
    weight = weight / 10,
    durnpso = durnpso / 10,
    # Treatment classes
    trtclass = case_when(trtn == 1 ~ "Placebo",
                         trtn \%in\% c(2, 3, 5, 6) ~ "IL blocker",
                         trtn == 4 ~ "TNFa blocker"),
    # Check complete cases for covariates of interest
    complete = complete.cases(durnpso, prevsys, bsa, weight, psa)
  )

pso_agd <- pso_agd \%>\%
  mutate(
    # Variable transformations
    bsa_mean = bsa_mean / 100,
    bsa_sd = bsa_sd / 100,
    prevsys = prevsys / 100,
    psa = psa / 100,
    weight_mean = weight_mean / 10,
    weight_sd = weight_sd / 10,
    durnpso_mean = durnpso_mean / 10,
    durnpso_sd = durnpso_sd / 10,
    # Treatment classes
    trtclass = case_when(trtn == 1 ~ "Placebo",
                         trtn \%in\% c(2, 3, 5, 6) ~ "IL blocker",
                         trtn == 4 ~ "TNFa blocker")
  )

# Exclude small number of individuals with missing covariates
pso_ipd <- filter(pso_ipd, complete)

pso_net <- combine_network(
  set_ipd(pso_ipd,
          study = studyc,
          trt = trtc,
          r = pasi75,
          trt_class = trtclass),
  set_agd_arm(pso_agd,
              study = studyc,
              trt = trtc,
              r = pasi75_r,
              n = pasi75_n,
              trt_class = trtclass)
)

# Print network details
pso_net

# Add integration points to the network
pso_net <- add_integration(pso_net,
  durnpso = distr(qgamma, mean = durnpso_mean, sd = durnpso_sd),
  prevsys = distr(qbern, prob = prevsys),
  bsa = distr(qlogitnorm, mean = bsa_mean, sd = bsa_sd),
  weight = distr(qgamma, mean = weight_mean, sd = weight_sd),
  psa = distr(qbern, prob = psa),
  n_int = 1000)

\donttest{
# Fitting a ML-NMR model.
# Specify a regression model to include effect modifier interactions for five
# covariates, along with main (prognostic) effects. We use a probit link and
# specify that the two-parameter Binomial approximation for the aggregate-level
# likelihood should be used. We set treatment-covariate interactions to be equal
# within each class. We narrow the possible range for random initial values with
# init_r = 0.1, since probit models in particular are often hard to initialise.
# Using the QR decomposition greatly improves sampling efficiency here, as is
# often the case for regression models.
pso_fit <- nma(pso_net,
               trt_effects = "fixed",
               link = "probit",
               likelihood = "bernoulli2",
               regression = ~(durnpso + prevsys + bsa + weight + psa)*.trt,
               class_interactions = "common",
               prior_intercept = normal(scale = 10),
               prior_trt = normal(scale = 10),
               prior_reg = normal(scale = 10),
               init_r = 0.1,
               QR = TRUE)
}

\donttest{
# Predicted probabilities of response in each study in the network
(pso_pred <- predict(pso_fit, type = "response"))
plot(pso_pred, ref_line = c(0, 1))

# Predicted probabilites of response in a new target population, with means
# and SDs or proportions given by
new_agd_int <- data.frame(
  bsa_mean = 0.6,
  bsa_sd = 0.3,
  prevsys = 0.1,
  psa = 0.2,
  weight_mean = 10,
  weight_sd = 1,
  durnpso_mean = 3,
  durnpso_sd = 1
)

# We need to add integration points to this data frame of new data
# We use the weighted mean correlation matrix computed from the IPD studies
new_agd_int <- add_integration(new_agd_int,
                               durnpso = distr(qgamma, mean = durnpso_mean, sd = durnpso_sd),
                               prevsys = distr(qbern, prob = prevsys),
                               bsa = distr(qlogitnorm, mean = bsa_mean, sd = bsa_sd),
                               weight = distr(qgamma, mean = weight_mean, sd = weight_sd),
                               psa = distr(qbern, prob = psa),
                               cor = pso_net$int_cor,
                               n_int = 1000)

# Predicted probabilities of achieving PASI 75 in this target population, given
# a Normal(-1.75, 0.08^2) distribution on the baseline probit-probability of
# response on Placebo (at the reference levels of the covariates), are given by
(pso_pred_new <- predict(pso_fit,
                         type = "response",
                         newdata = new_agd_int,
                         baseline = distr(qnorm, -1.75, 0.08)))
plot(pso_pred_new, ref_line = c(0, 1))
}
}
\seealso{
\code{\link[=plot.nma_summary]{plot.nma_summary()}} for plotting the predictions.
}
