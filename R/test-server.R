#' Reactive testing for Shiny server functions and modules
#'
#' A way to test the reactive interactions in Shiny applications. Reactive
#' interactions are defined in the server function of applications and in
#' modules.
#' @param app A server function (i.e. a function with `input`, `output`,
#'   and `session`), or a module function (i.e. a function with first
#'   argument `id` that calls [moduleServer()].
#'
#'   You can also provide an app, a path an app, or anything that
#'   [`as.shiny.appobj()`] can handle.
#' @param expr Test code containing expectations. The objects from inside the
#'   server function environment will be made available in the environment of
#'   the test expression (this is done using a data mask with
#'   [rlang::eval_tidy()]). This includes the parameters of the server function
#'   (e.g. `input`, `output`, and `session`), along with any other values
#'   created inside of the server function.
#' @param args Additional arguments to pass to the module function. If `app` is
#'   a module, and no `id` argument is provided, one will be generated and
#'   supplied automatically.
#' @param session The [`MockShinySession`] object to use as the [reactive
#'   domain][shiny::domains]. The same session object is used as the domain both
#'   during invocation of the server or module under test and during evaluation
#'   of `expr`.
#' @include mock-session.R
#' @rdname testServer
#' @examples
#' # Testing a server function  ----------------------------------------------
#' server <- function(input, output, session) {
#'   x <- reactive(input$a * input$b)
#' }
#'
#' testServer(server, {
#'   session$setInputs(a = 2, b = 3)
#'   stopifnot(x() == 6)
#' })
#'
#'
#' # Testing a module --------------------------------------------------------
#' myModuleServer <- function(id, multiplier = 2, prefix = "I am ") {
#'   moduleServer(id, function(input, output, session) {
#'     myreactive <- reactive({
#'       input$x * multiplier
#'     })
#'     output$txt <- renderText({
#'       paste0(prefix, myreactive())
#'     })
#'   })
#' }
#'
#' testServer(myModuleServer, args = list(multiplier = 2), {
#'   session$setInputs(x = 1)
#'   # You're also free to use third-party
#'   # testing packages like testthat:
#'   #   expect_equal(myreactive(), 2)
#'   stopifnot(myreactive() == 2)
#'   stopifnot(output$txt == "I am 2")
#'
#'   session$setInputs(x = 2)
#'   stopifnot(myreactive() == 4)
#'   stopifnot(output$txt == "I am 4")
#'   # Any additional arguments, below, are passed along to the module.
#' })
#' @export
testServer <- function(app = NULL, expr, args = list(), session = MockShinySession$new()) {
  require(shiny)

  if (!is.null(getDefaultReactiveDomain()))
    stop("testServer() is for use only within tests and may not indirectly call itself.")

  on.exit(if (!session$isClosed()) session$close(), add = TRUE)
  quosure <- rlang::enquo(expr)

  if (isModuleServer(app)) {
    if (!("id" %in% names(args)))
      args[["id"]] <- session$genId()
    # app is presumed to be a module, and modules may take additional arguments,
    # so splice in any args.
    withMockContext(session, rlang::exec(app, !!!args))

    # If app is a module, then we must use both the module function's immediate
    # environment and also its enclosing environment to construct the mask.
    parent_clone <- rlang::env_clone(parent.env(session$env))
    clone <- rlang::env_clone(session$env, parent_clone)
    mask <- rlang::new_data_mask(clone, parent_clone)
    withMockContext(session, rlang::eval_tidy(quosure, mask, rlang::caller_env()))
    return(invisible())
  }

  if (is.null(app)) {
    path <- findEnclosingApp(".")
    app <- shinyAppDir(path)
  } else if (isServer(app)) {
    app <- shinyApp(fluidPage(), app)
  } else {
    app <- as.shiny.appobj(app)
  }

  if (!is.null(app$onStart))
    app$onStart()
  if (!is.null(app$onStop))
    on.exit(app$onStop(), add = TRUE)

  server <- app$serverFuncSource()
  if (!"session" %in% names(formals(server)))
    stop("Tested application server functions must declare input, output, and session arguments.")
  if (length(args))
    stop("Arguments were provided to a server function.")

  body(server) <- rlang::expr({
    session$setEnv(base::environment())
    !!body(server)
  })
  withMockContext(session,
    server(input = session$input, output = session$output, session = session)
  )

  # # If app is a server, we use only the server function's immediate
  # # environment to construct the mask.
  mask <- rlang::new_data_mask(rlang::env_clone(session$env))
  withMockContext(session, {
    rlang::eval_tidy(quosure, mask, rlang::caller_env())
  })
  invisible()
}

withMockContext <- function(session, expr) {
  isolate(
    withReactiveDomain(session, {
      withr::with_options(list(`shiny.allowoutputreads` = TRUE), {
        withLocalOptions({
          # Sets a cache for renderCachedPlot() with cache = "app" to use.
          shinyOptions("cache" = session$appcache)
          expr
        })
      })
    })
  )
}


# Helpers -----------------------------------------------------------------

isModuleServer <- function(x) {
  is.function(x) && names(formals(x))[[1]] == "id"
}

isServer <- function(x) {
  if (!is.function(x)) {
    return(FALSE)
  }

  if (length(formals(x)) < 3) {
    return(FALSE)
  }

  identical(names(formals(x))[1:3], c("input", "output", "session"))
}
