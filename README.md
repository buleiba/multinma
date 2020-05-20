
<!-- README.md is generated from README.Rmd. Please edit that file -->

# multinma

<!-- badges: start -->

[![CRAN
status](https://www.r-pkg.org/badges/version/multinma)](https://CRAN.R-project.org/package=multinma)
<!-- badges: end -->

The `multinma` package implements network meta-analysis, network
meta-regression, and multilevel network meta-regression models which
combine evidence from a network of studies and treatments using either
aggregate data or individual patient data from each study (Phillippo et
al., n.d.; Phillippo 2019). Models are estimated in a Bayesian framwork
using Stan (Carpenter et al. 2017).

## Installation

You can install the released version of multinma from
[CRAN](https://CRAN.R-project.org) with:

``` r
install.packages("multinma")
```

And the development version from [GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("dmphillippo/multinma")
```

## References

<div id="refs" class="references">

<div id="ref-Carpenter2017">

Carpenter, Bob, Andrew Gelman, Matthew D. Hoffman, Daniel Lee, Ben
Goodrich, Michael Betancourt, Marcus Brubaker, Jiqiang Guo, Peter Li,
and Allen Riddell. 2017. “Stan: A Probabilistic Programming Language.”
*Journal of Statistical Software* 76 (1).
<https://doi.org/10.18637/jss.v076.i01>.

</div>

<div id="ref-Phillippo_thesis">

Phillippo, David Mark. 2019. “Calibration of Treatment Effects in
Network Meta-Analysis Using Individual Patient Data.” PhD thesis,
University of Bristol.

</div>

<div id="ref-methods_paper">

Phillippo, David M., Sofia Dias, A. E. Ades, Mark Belger, Alan Brnabic,
Alexander Schacht, Daniel Saure, Zbigniew Kadziola, and Nicky J. Welton.
n.d. “Multilevel Network Meta-Regression for Population-Adjusted
Treatment Comparisons.” *Journal of the Royal Statistical Society:
Series A (Statistics in Society)*.

</div>

</div>
