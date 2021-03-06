#' @import data.table
#' @import paradox
#' @import mlr3misc
#' @import survival
#' @importFrom R6 R6Class
#' @importFrom mlr3 mlr_learners LearnerClassif LearnerRegr
#' @importFrom mlr3proba LearnerSurv
"_PACKAGE"

# nocov start
register_mlr3 = function(libname, pkgname) {
  # get mlr_learners dictionary from the mlr3 namespace

  x = utils::getFromNamespace("mlr_learners", ns = "mlr3")

  # add the learner to the dictionary
  x$add("classif.gamboost", LearnerClassifGAMBoost)
  x$add("regr.gamboost", LearnerRegrGAMBoost)
  x$add("surv.gamboost", LearnerSurvGAMBoost)
  x$add("classif.glmboost", LearnerClassifGLMBoost)
  x$add("regr.glmboost", LearnerRegrGLMBoost)
  x$add("surv.glmboost", LearnerSurvGLMBoost)
  x$add("surv.blackboost", LearnerSurvBlackBoost)
  x$add("surv.mboost", LearnerSurvMBoost)
}

.onLoad = function(libname, pkgname) { # nolint
  register_mlr3()
  setHook(packageEvent("mlr3", "onLoad"), function(...) register_mlr3(),
    action = "append")
}

.onUnload = function(libpath) { # nolint
  event = packageEvent("mlr3", "onLoad")
  hooks = getHook(event)
  pkgname = vapply(hooks, function(x) environment(x)$pkgname, NA_character_)
  setHook(event, hooks[pkgname != "mlr3learners.mboost"],
    action = "replace")
}
# nocov end
