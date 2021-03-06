#' Set up individual patient data
#'
#' Set up a network containing individual patient data (IPD). Multiple data
#' sources may be combined once created using [combine_network()].
#'
#' @template args-data_common
# #' @template args-data_rE
#' @param r column of `data` specifying a binary outcome or Poisson outcome count
#' @param E column of `data` specifying the total time at risk for Poisson
#'   outcomes
# #' @template args-data_Surv
#'
#' @return An object of class [nma_data]
#' @export
#'
#' @template args-details_trt_ref
#'
#' @seealso [set_agd_arm()] for arm-based aggregate data, [set_agd_contrast()]
#'   for contrast-based aggregate data, and [combine_network()] for combining
#'   several data sources in one network.
#' @template seealso_nma_data
#' @examples
#' # Set up network of plaque psoriasis IPD
#' head(plaque_psoriasis_ipd)
#'
#' pso_net <- set_ipd(plaque_psoriasis_ipd,
#'                    study = studyc,
#'                    trt = trtc,
#'                    r = pasi75)
#'
#' # Print network details
#' pso_net
#'
#' # Plot network
#' plot(pso_net)
#'
#' # Setting a different reference treatment
#' set_ipd(plaque_psoriasis_ipd,
#'         study = studyc,
#'         trt = trtc,
#'         r = pasi75,
#'         trt_ref = "PBO")

set_ipd <- function(data,
                    study,
                    trt,
                    y = NULL,
                    r = NULL, E = NULL,
                    # Surv = NULL,
                    trt_ref = NULL,
                    trt_class = NULL) {

  # Check data is data frame
  if (!inherits(data, "data.frame")) abort("Argument `data` should be a data frame")
  if (nrow(data) == 0) {
    return(
      structure(
        list(agd_arm = NULL,
             agd_contrast = NULL,
             ipd = NULL,
             treatments = NULL,
             classes = NULL,
             studies = NULL),
        class = "nma_data")
    )
  }

  # Pull study and treatment columns
  if (missing(study)) abort("Specify `study`")
  .study <- dplyr::pull(data, {{ study }})
  if (any(is.na(.study))) abort("`study` cannot contain missing values")

  if (missing(trt)) abort("Specify `trt`")
  .trt <- dplyr::pull(data, {{ trt }})
  if (any(is.na(.trt))) abort("`trt` cannot contain missing values")

  # Treatment classes
  .trtclass <- pull_non_null(data, enquo(trt_class))
  if (!is.null(.trtclass)) check_trt_class(.trtclass, .trt)

  if (!is.null(trt_ref) && length(trt_ref) > 1) abort("`trt_ref` must be length 1.")

  # Pull and check outcomes
  .y <- pull_non_null(data, enquo(y))
  .r <- pull_non_null(data, enquo(r))
  .E <- pull_non_null(data, enquo(E))
  # .Surv <- ...

  check_outcome_continuous(.y, with_se = FALSE)
  check_outcome_binary(.r, .E)
  # check_outcome_surv(.Surv)

  o_type <- get_outcome_type(y = .y, se = NULL,
                             r = .r, n = NULL, E = .E)

  # Create tibble in standard format
  d <- tibble::tibble(
    .study = nfactor(.study),
    .trt = nfactor(.trt)
  )

  if (!is.null(trt_ref)) {
    trt_ref <- as.character(trt_ref)
    lvls_trt <- levels(d$.trt)
    if (! trt_ref %in% lvls_trt)
      abort(sprintf("`trt_ref` does not match a treatment in the data.\nSuitable values are: %s",
                    ifelse(length(lvls_trt) <= 5,
                           paste0(lvls_trt, collapse = ", "),
                           paste0(paste0(lvls_trt[1:5], collapse = ", "), ", ..."))))
    d$.trt <- forcats::fct_relevel(d$.trt, trt_ref)
  }

  if (!is.null(.trtclass)) {
    d <- tibble::add_column(d, .trtclass = nfactor(.trtclass))
    class_lookup <- d %>%
      dplyr::distinct(.data$.trt, .data$.trtclass) %>%
      dplyr::arrange(.data$.trt)
    class_ref <- as.character(class_lookup[[1, ".trtclass"]])
    d$.trtclass <- forcats::fct_relevel(d$.trtclass, class_ref)
    classes <- forcats::fct_relevel(nfactor(class_lookup$.trtclass), class_ref)
  } else {
    classes <- NULL
  }

  if (o_type == "continuous") {
    d <- tibble::add_column(d, .y = .y)
  } else if (o_type == "binary") {
    d <- tibble::add_column(d, .r = .r)
  } else if (o_type == "rate") {
    d <- tibble::add_column(d, .r = .r, .E = .E)
  }

  d <- dplyr::bind_cols(d, data)

  # Drop original study and treatment columns
  d <- dplyr::select(d, - {{ study }}, - {{ trt }})
  if (!is.null(.trtclass)) d <- dplyr::select(d, - {{ trt_class }})

  # Produce nma_data object
  out <- structure(
    list(agd_arm = NULL,
         agd_contrast = NULL,
         ipd = d,
         treatments = forcats::fct_unique(d$.trt),
         classes = classes,
         studies = forcats::fct_unique(d$.study),
         outcome = list(agd_arm = NA, agd_contrast = NA, ipd = o_type)),
    class = "nma_data")

  # If trt_ref not specified, mark treatments factor as default, calculate
  # current reference trt
  if (is.null(trt_ref)) {
    trt_ref <- get_default_trt_ref(out)
    trt_sort <- order(forcats::fct_relevel(out$treatments, trt_ref))
    out$treatments <- .default(forcats::fct_relevel(out$treatments, trt_ref)[trt_sort])
    out$ipd$.trt <- forcats::fct_relevel(out$ipd$.trt, trt_ref)
    if (!is.null(.trtclass)) {
      class_ref <- as.character(out$classes[trt_sort[1]])
      out$ipd$.trtclass <- forcats::fct_relevel(out$ipd$.trtclass, class_ref)
      out$classes <- forcats::fct_relevel(out$classes, class_ref)[trt_sort]
    }
  }

  return(out)
}


#' Set up arm-based aggregate data
#'
#' Set up a network containing arm-based aggregate data (AgD), such as event
#' counts or mean outcomes on each arm. Multiple data sources may be combined
#' once created using [combine_network()].
#'
#' @template args-data_common
#' @template args-data_se
#' @template args-data_rE
# #' @template args-data_Surv
#' @param n column of `data` specifying Binomial outcome numerator
#' @param sample_size column of `data` giving the sample size in each arm.
#'   Optional, see details.
#'
#' @return An object of class [nma_data]
#' @export

#' @template args-details_trt_ref
#' @template args-details_sample_size
#' @details
#' If a Binomial outcome is specified and `sample_size` is omitted, `n` will be
#' used as the sample size by default.
#'
#' @seealso [set_ipd()] for individual patient data, [set_agd_contrast()] for
#'   contrast-based aggregate data, and [combine_network()] for combining
#'   several data sources in one network.
#' @template seealso_nma_data
#' @template ex_smoking_network
#' @examples
#'
#' # Plot network
#' plot(smk_net)
set_agd_arm <- function(data,
                        study,
                        trt,
                        y = NULL, se = NULL,
                        r = NULL, n = NULL, E = NULL,
                        # Surv = NULL,
                        sample_size = NULL,
                        trt_ref = NULL,
                        trt_class = NULL) {

  # Check data is data frame
  if (!inherits(data, "data.frame")) abort("Argument `data` should be a data frame")
  if (nrow(data) == 0) {
    return(
      structure(
        list(agd_arm = NULL,
             agd_contrast = NULL,
             ipd = NULL,
             treatments = NULL,
             classes = NULL,
             studies = NULL),
        class = "nma_data")
    )
  }

  # Pull study and treatment columns
  if (missing(study)) abort("Specify `study`")
  .study <- dplyr::pull(data, {{ study }})
  if (any(is.na(.study))) abort("`study` cannot contain missing values")

  if (missing(trt)) abort("Specify `trt`")
  .trt <- dplyr::pull(data, {{ trt }})
  if (any(is.na(.trt))) abort("`trt` cannot contain missing values")

  # Treatment classes
  .trtclass <- pull_non_null(data, enquo(trt_class))
  if (!is.null(.trtclass)) check_trt_class(.trtclass, .trt)

  if (!is.null(trt_ref) && length(trt_ref) > 1) abort("`trt_ref` must be length 1.")

  # Pull and check outcomes
  .y <- pull_non_null(data, enquo(y))
  .se <- pull_non_null(data, enquo(se))
  .r <- pull_non_null(data, enquo(r))
  .n <- pull_non_null(data, enquo(n))
  .E <- pull_non_null(data, enquo(E))
  # .Surv <- ...

  check_outcome_continuous(.y, .se, with_se = TRUE)
  check_outcome_count(.r, .n, .E)
  # check_outcome_surv(.Surv)

  o_type <- get_outcome_type(y = .y, se = .se,
                             r = .r, n = .n, E = .E)

  # Pull and check sample size
  .sample_size <- pull_non_null(data, enquo(sample_size))
  if (!is.null(.sample_size)) check_sample_size(.sample_size)
  else if (o_type == "count") .sample_size <- .n
  else inform("Note: Optional argument `sample_size` not provided, some features may not be available (see ?set_agd_arm).")

  # Create tibble in standard format
  d <- tibble::tibble(
    .study = nfactor(.study),
    .trt = nfactor(.trt)
  )

  if (!is.null(trt_ref)) {
    trt_ref <- as.character(trt_ref)
    lvls_trt <- levels(d$.trt)
    if (! trt_ref %in% lvls_trt)
      abort(sprintf("`trt_ref` does not match a treatment in the data.\nSuitable values are: %s",
                    ifelse(length(lvls_trt) <= 5,
                           paste0(lvls_trt, collapse = ", "),
                           paste0(paste0(lvls_trt[1:5], collapse = ", "), ", ..."))))
    d$.trt <- forcats::fct_relevel(d$.trt, trt_ref)
  }

  if (!is.null(.trtclass)) {
    d <- tibble::add_column(d, .trtclass = nfactor(.trtclass))
    class_lookup <- d %>%
      dplyr::distinct(.data$.trt, .data$.trtclass) %>%
      dplyr::arrange(.data$.trt)
    class_ref <- as.character(class_lookup[[1, ".trtclass"]])
    d$.trtclass <- forcats::fct_relevel(d$.trtclass, class_ref)
    classes <- forcats::fct_relevel(nfactor(class_lookup$.trtclass), class_ref)
  } else {
    classes <- NULL
  }

  if (o_type == "continuous") {
    d <- tibble::add_column(d, .y = .y, .se = .se)
  } else if (o_type == "count") {
    d <- tibble::add_column(d, .r = .r, .n = .n)
  } else if (o_type == "rate") {
    d <- tibble::add_column(d, .r = .r, .E = .E)
  }

  if (!is.null(.sample_size)) d <- tibble::add_column(d, .sample_size = .sample_size)

  # Bind in original data
  d <- dplyr::bind_cols(d, data)

  # Drop original study and treatment columns
  d <- dplyr::select(d, - {{ study }}, - {{ trt }})
  if (!is.null(.trtclass)) d <- dplyr::select(d, - {{ trt_class }})

  # Produce nma_data object
  out <- structure(
    list(agd_arm = d,
         agd_contrast = NULL,
         ipd = NULL,
         treatments = forcats::fct_unique(d$.trt),
         classes = classes,
         studies = forcats::fct_unique(d$.study),
         outcome = list(agd_arm = o_type, agd_contrast = NA, ipd = NA)),
    class = "nma_data")

  # If trt_ref not specified, mark treatments factor as default, calculate
  # current reference trt
  if (is.null(trt_ref)) {
    trt_ref <- get_default_trt_ref(out)
    trt_sort <- order(forcats::fct_relevel(out$treatments, trt_ref))
    out$treatments <- .default(forcats::fct_relevel(out$treatments, trt_ref)[trt_sort])
    out$agd_arm$.trt <- forcats::fct_relevel(out$agd_arm$.trt, trt_ref)
    if (!is.null(.trtclass)) {
      class_ref <- as.character(out$classes[trt_sort[1]])
      out$agd_arm$.trtclass <- forcats::fct_relevel(out$agd_arm$.trtclass, class_ref)
      out$classes <- forcats::fct_relevel(out$classes, class_ref)[trt_sort]
    }
  }

  return(out)
}


#' Set up contrast-based aggregate data
#'
#' Set up a network containing contrast-based aggregate data (AgD), i.e.
#' summaries of relative effects between treatments such as log Odds Ratios.
#' Multiple data sources may be combined once created using [combine_network()].
#'
#' @template args-data_common
#' @template args-data_se
#' @param sample_size column of `data` giving the sample size in each arm.
#'   Optional, see details.
#'
#' @details Each study should have a single reference/baseline treatment,
#'   against which relative effects in the other arm(s) are given. For the
#'   reference arm, include a data row with continuous outcome `y` equal to
#'   `NA`. If a study has three or more arms (so two or more relative effects),
#'   set the standard error `se` for the reference arm data row equal to the
#'   standard error of the mean outcome on the reference arm (this determines
#'   the covariance of the relative effects, when expressed as differences in
#'   mean outcomes between arms).
#'
#' @template args-details_trt_ref
#' @template args-details_sample_size
#'
#' @return An object of class [nma_data]
#' @export
#'
#' @seealso [set_ipd()] for individual patient data, [set_agd_arm()] for
#'   arm-based aggregate data, and [combine_network()] for combining several
#'   data sources in one network.
#' @template seealso_nma_data
#' @examples
#' # Set up network of Parkinson's contrast data
#' head(parkinsons)
#'
#' park_net <- set_agd_contrast(parkinsons,
#'                              study = studyn,
#'                              trt = trtn,
#'                              y = diff,
#'                              se = se_diff,
#'                              sample_size = n)
#'
#' # Print details
#' park_net
#'
#' # Plot network
#' plot(park_net)

set_agd_contrast <- function(data,
                             study,
                             trt,
                             y = NULL, se = NULL,
                             sample_size = NULL,
                             trt_ref = NULL,
                             trt_class = NULL) {

  # Check data is data frame
  if (!inherits(data, "data.frame")) abort("Argument `data` should be a data frame")
  if (nrow(data) == 0) {
    return(
      structure(
        list(agd_arm = NULL,
             agd_contrast = NULL,
             ipd = NULL,
             treatments = NULL,
             classes = NULL,
             studies = NULL),
        class = "nma_data")
    )
  }


  # Pull study and treatment columns
  if (missing(study)) abort("Specify `study`")
  .study <- dplyr::pull(data, {{ study }})
  if (any(is.na(.study))) abort("`study` cannot contain missing values")

  if (missing(trt)) abort("Specify `trt`")
  .trt <- dplyr::pull(data, {{ trt }})
  if (any(is.na(.trt))) abort("`trt` cannot contain missing values")


  # Treatment classes
  .trtclass <- pull_non_null(data, enquo(trt_class))
  if (!is.null(.trtclass)) check_trt_class(.trtclass, .trt)

  if (!is.null(trt_ref) && length(trt_ref) > 1) abort("`trt_ref` must be length 1.")

  # Pull and check outcomes
  .y <- pull_non_null(data, enquo(y))
  .se <- pull_non_null(data, enquo(se))

  if (is.null(.y)) abort("Specify continuous outcome `y`")
  if (is.null(.se)) abort("Specify standard error `se`")

  # Pull and check sample size
  .sample_size <- pull_non_null(data, enquo(sample_size))
  if (!is.null(.sample_size)) {
    check_sample_size(.sample_size)
  } else {
    inform("Note: Optional argument `sample_size` not provided, some features may not be available (see ?set_agd_contrast).")
  }

  # Determine baseline arms by .y = NA
  bl <- is.na(.y)

  # if (anyDuplicated(.study[bl])) abort("Multiple baseline arms (where y = NA) for a study.")

  tibble::tibble(.study, .trt, bl, .se) %>%
    dplyr::group_by(.data$.study) %>%
    dplyr::mutate(n_arms = dplyr::n(),
                  n_bl = sum(.data$bl)) %>%
    {
      if (any(.$n_bl > 1))
        abort("Multiple baseline arms (where y = NA) in a study or studies.")
      else if (any(.$n_bl == 0))
        abort("Study or studies without a specified baseline arm (where y = NA).")
      else .
    } %>%
    dplyr::filter(.data$bl, .data$n_arms > 2) %>%
    {
      check_outcome_continuous(1, .$.se, with_se = TRUE,
                               append = " on baseline arms in studies with >2 arms.")
    }

  check_outcome_continuous(.y[!bl], .se[!bl], with_se = TRUE,
    append = " for non-baseline rows (i.e. those specifying contrasts against baseline).")

  o_type <- get_outcome_type(y = .y[!bl], se = .se[!bl],
                             r = NULL, n = NULL, E = NULL)

  # Create tibble in standard format
  d <- tibble::tibble(
    .study = nfactor(.study),
    .trt = nfactor(.trt),
    .y = .y,
    .se = .se)

  if (!is.null(trt_ref)) {
    trt_ref <- as.character(trt_ref)
    lvls_trt <- levels(d$.trt)
    if (! trt_ref %in% lvls_trt)
      abort(sprintf("`trt_ref` does not match a treatment in the data.\nSuitable values are: %s",
                    ifelse(length(lvls_trt) <= 5,
                           paste0(lvls_trt, collapse = ", "),
                           paste0(paste0(lvls_trt[1:5], collapse = ", "), ", ..."))))
    d$.trt <- forcats::fct_relevel(d$.trt, trt_ref)
  }

  if (!is.null(.trtclass)) {
    d <- tibble::add_column(d, .trtclass = nfactor(.trtclass))
    class_lookup <- d %>%
      dplyr::distinct(.data$.trt, .data$.trtclass) %>%
      dplyr::arrange(.data$.trt)
    class_ref <- as.character(class_lookup[[1, ".trtclass"]])
    d$.trtclass <- forcats::fct_relevel(d$.trtclass, class_ref)
    classes <- forcats::fct_relevel(nfactor(class_lookup$.trtclass), class_ref)
  } else {
    classes <- NULL
  }

  if (!is.null(.sample_size)) {
    d <- tibble::add_column(d, .sample_size = .sample_size)
  }

  # Bind in original data
  d <- dplyr::bind_cols(d, data)

  # Drop original study and treatment columns
  d <- dplyr::select(d, - {{ study }}, - {{ trt }})
  if (!is.null(.trtclass)) d <- dplyr::select(d, - {{ trt_class }})

  # Make sure rows from each study are next to each other (required for Stan resdev/log_lik code)
  d <- dplyr::mutate(d, .study_inorder = forcats::fct_inorder(.data$.study)) %>%
    dplyr::arrange(.data$.study_inorder) %>%
    dplyr::select(-.data$.study_inorder)

  # Produce nma_data object
  out <- structure(
    list(agd_arm = NULL,
         agd_contrast = d,
         ipd = NULL,
         treatments = forcats::fct_unique(d$.trt),
         classes = classes,
         studies = forcats::fct_unique(d$.study),
         outcome = list(agd_arm = NA, agd_contrast = o_type, ipd = NA)),
    class = "nma_data")

  # If trt_ref not specified, mark treatments factor as default, calculate
  # current reference trt
  if (is.null(trt_ref)) {
    trt_ref <- get_default_trt_ref(out)
    trt_sort <- order(forcats::fct_relevel(out$treatments, trt_ref))
    out$treatments <- .default(forcats::fct_relevel(out$treatments, trt_ref)[trt_sort])
    out$agd_contrast$.trt <- forcats::fct_relevel(out$agd_contrast$.trt, trt_ref)
    if (!is.null(.trtclass)) {
      class_ref <- as.character(out$classes[trt_sort[1]])
      out$agd_contrast$.trtclass <- forcats::fct_relevel(out$agd_contrast$.trtclass, class_ref)
      out$classes <- forcats::fct_relevel(out$classes, class_ref)[trt_sort]
    }
  }

  return(out)
}


#' Combine multiple data sources into one network
#'
#' Multiple data sources created using [set_ipd()], [set_agd_arm()], or
#' [set_agd_contrast()] can be combined into a single network for analysis.
#'
#' @param ... multiple data sources, as defined using the `set_*` functions
#' @param trt_ref reference treatment for the entire network, as a string (or
#'   coerced as such) referring to the levels of the treatment factor variable
#'
#' @return An object of class [nma_data]
#' @export
#'
#' @seealso [set_ipd()], [set_agd_arm()], and [set_agd_contrast()] for defining
#'   different data sources.
#' @template seealso_nma_data
#'
#' @examples ## Parkinson's - combining contrast- and arm-based data
#' studies <- parkinsons$studyn
#' (parkinsons_arm <- parkinsons[studies %in% 1:3, ])
#' (parkinsons_contr <- parkinsons[studies %in% 4:7, ])
#'
#' park_arm_net <- set_agd_arm(parkinsons_arm,
#'                             study = studyn,
#'                             trt = trtn,
#'                             y = y,
#'                             se = se,
#'                             sample_size = n)
#'
#' park_contr_net <- set_agd_contrast(parkinsons_contr,
#'                                    study = studyn,
#'                                    trt = trtn,
#'                                    y = diff,
#'                                    se = se_diff,
#'                                    sample_size = n)
#'
#' park_net <- combine_network(park_arm_net, park_contr_net)
#'
#' # Print network details
#' park_net
#'
#' # Plot network
#' plot(park_net, weight_edges = TRUE, weight_nodes = TRUE)
#'
#' @examples ## Plaque Psoriasis - combining IPD and AgD in a network
#' @template ex_plaque_psoriasis_network
#' @examples
#'
#' # Plot network
#' plot(pso_net, weight_nodes = TRUE, weight_edges = TRUE, show_trt_class = TRUE)
combine_network <- function(..., trt_ref) {
  s <- list(...)

  # Check that arguments all inherit from nma_data class
  if (!purrr::every(s, inherits, what = "nma_data")) {
    abort("Expecting to combine objects of class `nma_data`, created using set_* functions")
  }

  # Combine treatment code factor
  trts <- stringr::str_sort(forcats::lvls_union(purrr::map(s, "treatments")), numeric = TRUE)
  if (!missing(trt_ref)) {
    if (! trt_ref %in% trts) {
      abort(sprintf("`trt_ref` does not match a treatment in the network.\nSuitable values are: %s",
                      ifelse(length(trts) <= 5,
                             paste0(trts, collapse = ", "),
                             paste0(paste0(trts[1:5], collapse = ", "), ", ..."))))
    }
    trts <- c(trt_ref, setdiff(trts, trt_ref))
  }

  # Combine classes factor
  has_classes <- purrr::map_lgl(purrr::map(s, "classes"), ~!is.null(.))

  if (all(has_classes)) {
    class_lookup <- tibble::tibble(.trt = forcats::fct_c(!!! purrr::map(s, "treatments")),
                                   .trtclass = forcats::fct_c(!!! purrr::map(s, "classes"))) %>%
      dplyr::mutate(.trt = forcats::fct_relevel(.data$.trt, trts)) %>%
      dplyr::distinct(.data$.trt, .data$.trtclass) %>%
      dplyr::arrange(.data$.trt)

    check_trt_class(class_lookup$.trtclass, class_lookup$.trt)

    class_lvls <- stringr::str_sort(levels(class_lookup$.trtclass), numeric = TRUE)
    class_ref <- as.character(class_lookup[[1, ".trtclass"]])
    class_lvls <- c(class_ref, setdiff(class_lvls, class_ref))

    class_lookup$.trtclass <- forcats::fct_relevel(class_lookup$.trtclass, class_ref)

    classes <- class_lookup$.trtclass
  } else if (any(has_classes)) {
    warn("Not all data sources have defined treatment classes. Removing treatment class information.")
    classes <- NULL
  } else {
    classes <- NULL
  }

  # Check that no studies are duplicated between data sources
  all_studs <- purrr::flatten_chr(purrr::map(s, ~levels(.$studies)))
  if (anyDuplicated(all_studs)) {
    abort(sprintf("Studies with same label found in multiple data sources: %s",
                  paste0(unique(all_studs[duplicated(all_studs)]), collapse = ", ")))
  }

  # Combine study code factor
  studs <- stringr::str_sort(forcats::lvls_union(purrr::map(s, "studies")), numeric = TRUE)

  # Get ipd
  ipd <- purrr::map(s, "ipd")
  if (!rlang::is_empty(ipd)) {
    for (j in 1:length(ipd)) {
      if (rlang::is_empty(ipd[[j]])) next
      ipd[[j]]$.trt <- forcats::lvls_expand(ipd[[j]]$.trt, trts)
      ipd[[j]]$.study <- forcats::lvls_expand(ipd[[j]]$.study, studs)
      if (!is.null(classes)) ipd[[j]]$.trtclass <- forcats::lvls_expand(ipd[[j]]$.trtclass, class_lvls)
    }
  }
  ipd <- dplyr::bind_rows(ipd)

  # Get agd_arm
  agd_arm <- purrr::map(s, "agd_arm")
  if (!rlang::is_empty(agd_arm)) {
    for (j in 1:length(agd_arm)) {
      if (rlang::is_empty(agd_arm[[j]])) next
      agd_arm[[j]]$.trt <- forcats::lvls_expand(agd_arm[[j]]$.trt, trts)
      agd_arm[[j]]$.study <- forcats::lvls_expand(agd_arm[[j]]$.study, studs)
      if (!is.null(classes))
        agd_arm[[j]]$.trtclass <- forcats::lvls_expand(agd_arm[[j]]$.trtclass, class_lvls)
    }
  }
  agd_arm <- dplyr::bind_rows(agd_arm)

  # Get agd_contrast
  agd_contrast <- purrr::map(s, "agd_contrast")
  if (!rlang::is_empty(agd_contrast)) {
    for (j in 1:length(agd_contrast)) {
      if (rlang::is_empty(agd_contrast[[j]])) next
      agd_contrast[[j]]$.trt <- forcats::lvls_expand(agd_contrast[[j]]$.trt, trts)
      agd_contrast[[j]]$.study <- forcats::lvls_expand(agd_contrast[[j]]$.study, studs)
      if (!is.null(classes))
        agd_contrast[[j]]$.trtclass <- forcats::lvls_expand(agd_contrast[[j]]$.trtclass, class_lvls)
    }
  }
  agd_contrast <- dplyr::bind_rows(agd_contrast)

  # Get outcome type
  o_ipd <- unique(purrr::map_chr(purrr::map(s, "outcome"), "ipd"))
  o_ipd <- o_ipd[!is.na(o_ipd)]
  if (length(o_ipd) > 1) abort("Multiple outcome types present in IPD.")
  if (length(o_ipd) == 0) o_ipd <- NA

  o_agd_arm <- unique(purrr::map_chr(purrr::map(s, "outcome"), "agd_arm"))
  o_agd_arm <- o_agd_arm[!is.na(o_agd_arm)]
  if (length(o_agd_arm) > 1) abort("Multiple outcome types present in AgD (arm-based).")
  if (length(o_agd_arm) == 0) o_agd_arm <- NA

  o_agd_contrast <- unique(purrr::map_chr(purrr::map(s, "outcome"), "agd_contrast"))
  o_agd_contrast <- o_agd_contrast[!is.na(o_agd_contrast)]
  if (length(o_agd_contrast) > 1) abort("Multiple outcome types present in AgD (contrast-based).")
  if (length(o_agd_contrast) == 0) o_agd_contrast <- NA

  outcome <- list(agd_arm = o_agd_arm,
                  agd_contrast = o_agd_contrast,
                  ipd = o_ipd)

  # Check outcome combination
  check_outcome_combination(outcome)

  # Produce nma_data object
  out <- structure(
    list(agd_arm = agd_arm,
         agd_contrast = agd_contrast,
         ipd = ipd,
         treatments = factor(trts, levels = trts),
         classes = classes,
         studies = factor(studs, levels = studs),
         outcome = outcome),
    class = "nma_data")

  # If trt_ref not specified, mark treatments factor as default, calculate
  # current reference trt
  if (missing(trt_ref)) {
    trt_ref <- get_default_trt_ref(out)
    trt_sort <- order(forcats::fct_relevel(out$treatments, trt_ref))
    out$treatments <- .default(forcats::fct_relevel(out$treatments, trt_ref)[trt_sort])

    if (has_ipd(out))
      out$ipd$.trt <- forcats::fct_relevel(out$ipd$.trt, trt_ref)
    if (has_agd_arm(out))
      out$agd_arm$.trt <- forcats::fct_relevel(out$agd_arm$.trt, trt_ref)
    if (has_agd_contrast(out))
      out$agd_contrast$.trt <- forcats::fct_relevel(out$agd_contrast$.trt, trt_ref)

    if (!is.null(classes)) {
      class_ref <- as.character(out$classes[trt_sort[1]])
      out$classes <- forcats::fct_relevel(out$classes, class_ref)[trt_sort]

      if (has_ipd(out))
        out$ipd$.trtclass <- forcats::fct_relevel(out$ipd$.trtclass, class_ref)
      if (has_agd_arm(out))
        out$agd_arm$.trtclass <- forcats::fct_relevel(out$agd_arm$.trtclass, class_ref)
      if (has_agd_contrast(out))
        out$agd_contrast$.trtclass <- forcats::fct_relevel(out$agd_contrast$.trtclass, class_ref)
    }
  }

  return(out)
}

#' Pull non-null variables from data
#'
#' @param data data frame
#' @param var quosure (possibly NULL) for variable to pull
#'
#' @noRd
pull_non_null <- function(data, var) {
  var_null <- rlang::quo_is_missing(var) | rlang::quo_is_null(var)
  if (!var_null) return(dplyr::pull(data, {{ var }}))
  else return(NULL)
}

#' Get outcome type
#'
#' Determines outcome type based on which inputs are NA
#'
#' @noRd
get_outcome_type <- function(y, se, r, n, E) {
  o <- c()
  if (!is.null(y)) o <- c(o, "continuous")
  if (!is.null(r)) {
    if (!is.null(E)) o <- c(o, "rate")
    if (!is.null(n)) o <- c(o, "count")
    if (is.null(n) && is.null(E)) o <- c(o, "binary")
  }
  if (length(o) == 0) abort("Please specify one and only one outcome.")
  if (length(o) > 1) abort(glue::glue("Please specify one and only one outcome, instead of ",
                                      glue::glue_collapse(o, sep = ", ", last = " and "), "."))

  return(o)
}

#' Check continuous outcomes
#'
#' @param y vector
#' @param se vector
#' @param with_se continuous outcome with SE?
#' @param append text to append to error message
#'
#' @noRd
check_outcome_continuous <- function(y, se = NULL, with_se = TRUE, append = NULL) {
  null_y <- is.null(y)
  null_se <- is.null(se)

  if (with_se) {
    if (!null_y && !null_se) {
      if (!is.numeric(y)) abort(paste0("Continuous outcome `y` must be numeric", append))
      if (!is.numeric(se)) abort(paste0("Standard error `se` must be numeric", append))
      if (any(is.nan(se))) abort(paste0("Standard error `se` cannot be NaN", append))
      if (any(is.na(y))) abort(paste0("Continuous outcome `y` contains missing values", append))
      if (any(is.na(se))) abort(paste0("Standard error `se` contains missing values", append))
      if (any(is.infinite(se))) abort(paste0("Standard error `se` cannot be infinite", append))
      if (any(se <= 0)) abort(paste0("Standard errors must be positive", append))
    } else {
      if (!null_y) abort(paste0("Specify standard error `se` for continuous outcome `y`", append))
      if (!null_se) abort(paste0("Specify continuous outcome `y`", append))
    }
    invisible(list(y = y, se = se))
  } else {
    if (!null_y) {
      if (any(is.na(y))) abort(paste0("Continuous outcome `y` contains missing values", append))
      if (!is.numeric(y)) abort(paste0("Continuous outcome `y` must be numeric", append))
    }
    invisible(list(y = y))
  }
}

#' Check count outcomes
#'
#' @param r vector
#' @param n vector
#' @param E vector
#'
#' @noRd
check_outcome_count <- function(r, n, E) {
  null_r <- is.null(r)
  null_n <- is.null(n)
  null_E <- is.null(E)

  if (!null_n) {
    if (!is.numeric(n)) abort("Denominator `n` must be numeric")
    if (any(is.na(n))) abort("Denominator `n` contains missing values")
    if (any(n != trunc(n))) abort("Denominator `n` must be integer-valued")
    if (any(n <= 0)) abort("Denominator `n` must be greater than zero")
    if (null_r) abort("Specify outcome count `r`.")
  }

  if (!null_E) {
    if (!is.numeric(E)) abort("Time at risk `E` must be numeric")
    if (any(is.na(E))) abort("Time at risk `E` contains missing values")
    if (any(E <= 0)) abort("Time at risk `E` must be positive")
    if (null_r) abort("Specify outcome count `r`.")
  }

  if (!null_r) {
    if (null_n && null_E) abort("Specify denominator `n` (count outcome) or time at risk `E` (rate outcome)")
    if (!is.numeric(r)) abort("Outcome count `r` must be numeric")
    if (any(is.na(r))) abort("Outcome count `r` contains missing values")
    if (any(r != trunc(r))) abort("Outcome count `r` must be integer-valued")
    if (!null_n && any(n < r | r < 0)) abort("Count outcome `r` must be between 0 and `n`")
    if (!null_E && any(r < 0)) abort("Rate outcome count `r` must be non-negative")
  }

  invisible(list(r = r, n = n, E = E))
}

#' Check binary outcomes
#'
#' @param r vector
#' @param E vector
#'
#' @noRd
check_outcome_binary <- function(r, E) {
  null_r <- is.null(r)
  null_E <- is.null(E)

  if (!null_E) {
    if (null_r) {
      abort("Specify count `r` for rate outcome")
    } else {
      if (!is.numeric(E)) abort("Time at risk `E` must be numeric")
      if (any(is.na(E))) abort("Time at risk `E` contains missing values")
      if (any(E <= 0)) abort("Time at risk `E` must be positive")
      if (!is.numeric(r)) abort("Rate outcome count `r` must be numeric")
      if (any(is.na(r))) abort("Rate outcome count `r` contains missing values")
      if (any(r != trunc(r))) abort("Rate outcome count `r` must be non-negative integer")
      if (any(r < 0)) abort("Rate outcome count `r` must be non-negative integer")
    }
  } else if (!null_r) {
    if (!is.numeric(r)) abort("Binary outcome `r` must be numeric")
    if (any(is.na(r))) abort("Binary outcome `r` contains missing values")
    if (any(! r %in% c(0, 1))) abort("Binary outcome `r` must equal 0 or 1")
  }

  invisible(list(r = r, E = E))
}

#' Check valid outcome combination across data sources
#'
#' @param outcomes outcome list, see nma_data-class
#'
#' @noRd
check_outcome_combination <- function(outcomes) {
  valid <- list(
    list(agd_arm = c("count", NA),
         agd_contrast = c("continuous", NA),
         ipd = c("binary", NA)),
    list(agd_arm = c("rate", NA),
         agd_contrast = c("continuous", NA),
         ipd = c("rate", NA)),
    list(agd_arm = c("continuous", NA),
         agd_contrast = c("continuous", NA),
         ipd = c("continuous", NA))
  )

  if (!any(purrr::map_lgl(valid,
                 ~all(c(outcomes$agd_arm %in% .$agd_arm,
                        outcomes$agd_contrast %in% .$agd_contrast,
                        outcomes$ipd %in% .$ipd))))) {
    rlang::abort(glue::glue("Combining ",
                     glue::glue_collapse(outcomes[!is.na(outcomes)], sep = ', ', last = ' and '),
                     " outcomes is not supported."))
  }
}

#' Check sample size
#'
#' @param sample_size vector
#'
#' @noRd
check_sample_size <- function(sample_size) {
    if (!is.numeric(sample_size))
      abort("Sample size `sample_size` must be numeric")
    if (any(is.nan(sample_size)))
      abort("Sample size `sample_size` cannot be NaN")
    if (any(is.na(sample_size)))
      abort("Sample size `sample_size` contains missing values")
    if (any(sample_size != trunc(sample_size)))
      abort("Sample size `sample_size` must be integer-valued")
    if (any(sample_size <= 0))
      abort("Sample size `sample_size` must be greater than zero")
    if (any(is.infinite(sample_size)))
      abort("Sample size `sample_size` cannot be infinite")
}

#' Check treatment class coding
#'
#' @param trt_class Class vector
#' @param trt Treatment vector
#'
#' @noRd
check_trt_class <- function(trt_class, trt) {
  if (any(is.na(trt)))
    abort("`trt` cannot contain missing values")
  if (any(is.na(trt_class)))
    abort("`trt_class` cannot contain missing values")
  if (anyDuplicated(unique(cbind(trt, trt_class))[, "trt"]))
    abort("Treatment present in more than one class (check `trt` and `trt_class`)")
}

#' Check for IPD and AgD in network
#'
#' @param network nma_data object
#'
#' @return logical TRUE/FALSE
#' @noRd
has_ipd <- function(network) {
  if (!inherits(network, "nma_data")) abort("Not nma_data object.")
  return(!rlang::is_empty(network$ipd))
}

has_agd_arm <- function(network) {
  if (!inherits(network, "nma_data")) abort("Not nma_data object.")
  return(!rlang::is_empty(network$agd_arm))
}

has_agd_contrast <- function(network) {
  if (!inherits(network, "nma_data")) abort("Not nma_data object.")
  return(!rlang::is_empty(network$agd_contrast))
}

#' Check whether AgD sample size columns are available
#'
#' @param network nma_data object
#'
#' @return logical TRUE/FALSE
#' @noRd
has_agd_sample_size <- function(network) {
  if (!inherits(network, "nma_data")) abort("Not nma_data object.")
  ss_a <- !has_agd_arm(network) || tibble::has_name(network$agd_arm, ".sample_size")
  ss_c <- !has_agd_contrast(network) || tibble::has_name(network$agd_contrast, ".sample_size")
  return(ss_a && ss_c)
}

#' Natural-order factors
#'
#' Produces factors with levels in natural sort order (i.e. 1 5 10 not 1 10 5)
#'
#' @noRd
nfactor <- function(x, ..., numeric = TRUE) {
  return(factor(x, levels = stringr::str_sort(unique(x), numeric = numeric), ...))
}
