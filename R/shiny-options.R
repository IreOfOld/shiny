.globals$options <- list()

#' @param name Name of an option to get.
#' @param default Value to be returned if the option is not currently set.
#' @rdname shinyOptions
#' @export
getShinyOption <- function(name, default = NULL) {
  # Make sure to use named (not numeric) indexing
  name <- as.character(name)

  if (name %in% names(.globals$options))
    .globals$options[[name]]
  else
    default
}

#' Get or set Shiny options
#'
#' \code{getShinyOption} retrieves the value of a Shiny option.
#' \code{shinyOptions} sets the value of Shiny options; it can also be used to
#' return a list of all currently-set Shiny options.
#'
#' There is a global option set, which is available by default. When a Shiny
#' application is run with \code{\link{runApp}}, that option set is duplicated
#' and the new option set is available for getting or setting values. If options
#' are set from global.R, app.R, ui.R, or server.R, or if they are set from
#' inside the server function, then the options will be scoped to the
#' application. When the application exits, the new option set is discarded and
#' the global option set is restored.
#'
#' @param ... Options to set, with the form \code{name = value}.
#'
#' @examples
#' \dontrun{
#' shinyOptions(myOption = 10)
#' getShinyOption("myOption")
#' }
#' @export
shinyOptions <- function(...) {
  newOpts <- list(...)

  if (length(newOpts) > 0) {
    .globals$options <- mergeVectors(.globals$options, newOpts)
    invisible(.globals$options)
  } else {
    .globals$options
  }
}


# Eval an expression with a new option set
withLocalOptions <- function(expr) {
  oldOptionSet <- .globals$options
  on.exit(.globals$options <- oldOptionSet)

  expr
}