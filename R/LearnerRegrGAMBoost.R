#' @title Boosted Generalized Additive Regression Learner
#'
#' @aliases mlr_learners_regr.gamboost
#' @format [R6::R6Class] inheriting from [LearnerRegr].
#'
#' @description
#' A [LearnerRegr] for a regression gamboost implemented in [mboost::gamboost()] in package \CRANpkg{mboost}.
#'
#' @references
#' Peter Buhlmann and Bin Yu (2003)
#' Boosting with the L2 Loss: Regression and Classification
#' Journal of the American Statistical Association
#' \url{https://doi.org/10.1198/016214503000125}
#'
#' @export
LearnerRegrGAMBoost = R6Class("LearnerRegrGAMBoost", inherit = LearnerRegr,
  public = list(
    initialize = function() {
      ps = ParamSet$new(
        params = list(
          ParamFct$new(id = "baselearner", default = "bbs", levels = c("bbs", "bols", "btree"), tags = c("train")),
          ParamInt$new(id = "dfbase", default = 4L, tags = c("train")),
          ParamDbl$new(id = "offset", default = NULL, special_vals = list(NULL), tags = c("train")),
          ParamFct$new(id = "family", default = c("Gaussian"),
            levels = c("Gaussian", "Laplace", "Huber", "Poisson", "GammaReg", "NBinomial", "Hurdle"), tags = c("train")),
          ParamUty$new(id = "nuirange", default = c(0, 100), tags = c("train")),
          ParamDbl$new(id = "d", default = NULL, special_vals = list(NULL), tags = c("train")),
          ParamInt$new(id = "mstop", default = 100, tags = c("train")),
          ParamDbl$new(id = "nu", default = 0.1, tags = c("train")),
          ParamFct$new(id = "risk", default = "inbag", levels = c("inbag", "oobag", "none"), tags = c("train"))
        )
      )

      super$initialize(
        id = "regr.gamboost",
        packages = "mboost",
        feature_types = c("integer", "numeric", "factor", "ordered"),
        predict_types = c("response"),
        param_set = ps,
        properties = c("weights")
      )
    },

    train_internal = function(task) {

      # Set to default for switch
      if (is.null(self$param_set$values$family)) {
        self$param_set$values$family = "Gaussian"
      }

      pars = self$param_set$get_values(tags = "train")
      pars_boost = pars[which(names(pars) %in% formalArgs(mboost::boost_control))]
      pars_gamboost = pars[which(names(pars) %in% formalArgs(mboost::gamboost))]
      pars_family = pars[which(names(pars) %in% formalArgs(getFromNamespace(pars_gamboost$family, asNamespace("mboost"))))]

      f = task$formula()
      data = task$data()

      if ("weights" %in% task$properties) {
        pars_gamboost = insert_named(pars_gamboost, list(weights = task$weights$weight))
      }

      pars_gamboost$family = switch(pars$family,
        Gaussian = mboost::Gaussian(),
        Laplace = mboost::Laplace(),
        Huber = invoke(mboost::Huber, .args = pars_family),
        Poisson = mboost::Poisson(),
        GammaReg = invoke(mboost::GammaReg, .args = pars_family),
        NBinomial = invoke(mboost::NBinomial, .args = pars_family),
        Hurdle = invoke(mboost::Hurdle, .args = pars_family)
      )

      ctrl = invoke(mboost::boost_control, .args = pars_boost)
      withr::with_package("mboost", { # baselearner argument requires attached mboost package
        invoke(mboost::gamboost, formula = f, data = data, control = ctrl, .args = pars_gamboost)
      })
    },

    predict_internal = function(task) {
      newdata = task$data(cols = task$feature_names)

      p = invoke(predict, self$model, newdata = newdata, type = "response")
      PredictionRegr$new(task = task, response = p)
    }
  )
)