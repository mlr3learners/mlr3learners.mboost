#' @title Boosted Generalized Additive Survival Learner
#'
#' @name mlr_learners_surv.gamboost
#'
#' @description
#' Boosted generalized additive survival learner.
#' Calls [mboost::gamboost()] from package \CRANpkg{mboost}.
#'
#' @details
#' `distr` prediction made by [mboost::survFit()].
#'
#' @templateVar id surv.gamboost
#' @template section_dictionary_learner
#'
#' @references
#' \cite{mlr3learners.mboost}{buhlmann_2003}
#'
#' @export
#' @template seealso_learner
#' @template example
LearnerSurvGAMBoost = R6Class("LearnerSurvGAMBoost",
  inherit = LearnerSurv,
  public = list(
    #' @description
    #' Creates a new instance of this [R6][R6::R6Class] class.
    initialize = function() {
      ps = ParamSet$new(
        params = list(
          ParamFct$new(
            id = "family", default = "coxph",
            levels = c(
              "coxph", "weibull", "loglog", "lognormal", "gehan", "cindex",
              "custom"), tags = "train"),
          ParamUty$new(id = "custom.family", tags = "train"),
          ParamUty$new(id = "nuirange", default = c(0, 100), tags = "train"),
          ParamUty$new(id = "offset", tags = "train"),
          ParamLgl$new(id = "center", default = TRUE, tags = "train"),
          ParamInt$new(id = "mstop", default = 100L, lower = 0L, tags = "train"),
          ParamDbl$new(id = "nu", default = 0.1, lower = 0, upper = 1, tags = "train"),
          ParamFct$new(id = "risk", levels = c("inbag", "oobag", "none"), tags = "train"),
          ParamLgl$new(id = "stopintern", default = FALSE, tags = "train"),
          ParamLgl$new(id = "trace", default = FALSE, tags = "train"),
          ParamUty$new(id = "oobweights", tags = "train"),
          ParamFct$new(
            id = "baselearner", default = "bbs",
            levels = c("bbs", "bols", "btree"), tags = "train"),
          ParamInt$new(id = "dfbase", default = 4, lower = 0, tags = "train"),
          ParamDbl$new(
            id = "sigma", default = 0.1, lower = 0, upper = 1,
            tags = "train"),
          ParamUty$new(id = "ipcw", default = 1, tags = "train"),
          ParamUty$new(id = "na.action", default = na.omit, tags = "train")
        )
      )

      ps$values = list(family = "coxph")
      ps$add_dep("sigma", "family", CondEqual$new("cindex"))
      ps$add_dep("ipcw", "family", CondEqual$new("cindex"))

      super$initialize(
        id = "surv.gamboost",
        param_set = ps,
        feature_types = c("integer", "numeric", "factor", "logical"),
        predict_types = c("distr", "crank", "lp", "response"),
        properties = c("weights", "importance", "selected_features"),
        packages = "mboost"
      )
    },

    #' @description
    #' The importance scores are extracted with the function [mboost::varimp()]
    #' with the default arguments.
    #' @return Named `numeric()`.
    importance = function() {
      if (is.null(self$model)) {
        stopf("No model stored")
      }

      vimp = as.numeric(mboost::varimp(self$model))
      names(vimp) = unname(variable.names(self$model))

      sort(vimp, decreasing = TRUE)
    },

    #' @description
    #' Selected features are extracted with the function
    #' [mboost::variable.names.mboost()], with
    #' `used.only = TRUE`.
    #' @return `character()`.
    selected_features = function() {
      if (is.null(self$model)) {
        stopf("No model stored")
      }

      unname(variable.names(self$model, usedonly = TRUE))
    }
  ),

  private = list(
    .train = function(task) {

      pars = self$param_set$get_values(tags = "train")

      if ("weights" %in% task$properties) {
        pars$weights = task$weights$weight
      }

      # Save control settings and return on exit
      saved_ctrl = mboost::boost_control()
      on.exit(mlr3misc::invoke(mboost::boost_control, .args = saved_ctrl))
      is_ctrl_pars = (names(pars) %in% names(saved_ctrl))

      # ensure only relevant pars passed to fitted model
      if (any(is_ctrl_pars)) {
        pars$control = do.call(mboost::boost_control, pars[is_ctrl_pars])
        pars = pars[!is_ctrl_pars]
      }

      # convert data to model matrix
      # x = model.matrix(~., as.data.frame(task$data(cols = task$feature_names)))

      family = switch(pars$family,
        coxph = mboost::CoxPH(),
        weibull = mlr3misc::invoke(mboost::Weibull,
          .args = pars[names(pars) %in% formalArgs(mboost::Weibull)]),
        loglog = mlr3misc::invoke(mboost::Loglog,
          .args = pars[names(pars) %in% formalArgs(mboost::Loglog)]),
        lognormal = mlr3misc::invoke(mboost::Lognormal,
          .args = pars[names(pars) %in% formalArgs(mboost::Lognormal)]),
        gehan = mboost::Gehan(),
        cindex = mlr3misc::invoke(mboost::Cindex,
          .args = pars[names(pars) %in% formalArgs(mboost::Cindex)]),
        custom = pars$custom.family
      )

      # FIXME - until issue closes
      pars = pars[!(names(pars) %in% formalArgs(mboost::Weibull))]
      pars = pars[!(names(pars) %in% formalArgs(mboost::Cindex))]
      pars = pars[!(names(pars) %in% c("family", "custom.family"))]


      mlr3misc::with_package("mboost", {
        mlr3misc::invoke(mboost::gamboost,
          formula = task$formula(task$feature_names),
          data = task$data(), family = family, .args = pars)
      })
    },

    .predict = function(task) {

      newdata = task$data(cols = task$feature_names)
      # predict linear predictor
      lp = as.numeric(mlr3misc::invoke(predict, self$model,
        newdata = newdata,
        type = "link"))

      # predict survival
      surv = mlr3misc::invoke(mboost::survFit, self$model, newdata = newdata)
      surv$cdf = 1 - surv$surv

      # define WeightedDiscrete distr6 object from predicted survival function
      x = rep(list(list(x = surv$time, cdf = 0)), task$nrow)
      for (i in 1:task$nrow) {
        x[[i]]$cdf = surv$cdf[, i]
      }

      distr = distr6::VectorDistribution$new(
        distribution = "WeightedDiscrete", params = x,
        decorators = c("CoreStatistics", "ExoticStatistics"))

      response = NULL
      if (!is.null(self$param_set$values$family)) {
        if (self$param_set$values$family %in% c("weibull", "loglog", "lognormal", "gehan")) {
          response = exp(lp)
        }
      }

      mlr3proba::PredictionSurv$new(
        task = task, crank = lp, distr = distr,
        lp = lp, response = response)
    }
  )
)
