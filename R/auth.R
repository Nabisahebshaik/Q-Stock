# Sign-in for the web UI. Accounts are stored locally with scrypt password hashes
# (libsodium, already a plumber dependency); sessions are random tokens held in memory
# by the API process, so a restart signs everyone out.
#
# Accounts come from (first found):
#   1. QSTOCK_AUTH_USERS  environment variable holding the JSON written by the script below
#                         (for a cloud container, where the file is not shipped)
#   2. data/auth/users.json (git-ignored), created by  Rscript scripts/32_create_user.R <name>
# With no accounts, sign-in is off and the API says so (/api/auth/config); the UI then
# shows how to create the first account. Passwords are never logged, returned or stored.

AUTH <- list(
  users_path = file.path("data", "auth", "users.json"),
  session_hours = 12,
  max_failures = 5,        # failed sign-ins per user name before a lock-out
  lock_minutes = 10
)

auth_read_users <- function(path = AUTH$users_path, env = Sys.getenv("QSTOCK_AUTH_USERS", "")) {
  txt <- if (nzchar(env)) env else if (file.exists(path)) paste(readLines(path, warn = FALSE), collapse = "\n") else ""
  if (!nzchar(txt)) return(list())
  u <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  stats::setNames(u, vapply(u, function(x) tolower(x$username), ""))
}

auth_hash <- function(password) sodium::password_store(password)

# Adds or replaces one account in the users file; returns the account without its hash.
auth_add_user <- function(username, password, display_name = username, role = "analyst",
                          path = AUTH$users_path) {
  if (!grepl("^[A-Za-z][A-Za-z0-9_.-]{1,31}$", username)) stop("user name: 2-32 letters, digits, . _ - (start with a letter)")
  if (nchar(password) < 8) stop("password: at least 8 characters")
  u <- auth_read_users(path, env = "")
  u[[tolower(username)]] <- list(username = username, display_name = display_name, role = role,
                                 hash = auth_hash(password), created = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(jsonlite::toJSON(unname(u), auto_unbox = TRUE, pretty = TRUE), path)
  Sys.chmod(path, "600")
  u[[tolower(username)]][c("username", "display_name", "role", "created")]
}

# Session store: tokens -> user, plus failure counters for the lock-out.
auth_store <- function(users) {
  s <- new.env(); s$users <- users; s$sessions <- new.env(); s$fails <- new.env(); s
}
auth_enabled <- function(store) length(store$users) > 0
auth_public <- function(u) list(username = u$username, display_name = u$display_name %||% u$username, role = u$role %||% "analyst")

auth_login <- function(store, username, password, now = Sys.time()) {
  key <- tolower(trimws(as.character(username %||% "")))
  f <- store$fails[[key]]
  if (!is.null(f) && f$n >= AUTH$max_failures && as.numeric(now) < f$until)
    return(list(ok = FALSE, status = 429, error = sprintf("too many failed attempts; try again in %d min",
                                                        ceiling((f$until - as.numeric(now)) / 60))))
  u <- store$users[[key]]
  ok <- !is.null(u) && is.character(password) && length(password) == 1 &&
    isTRUE(tryCatch(sodium::password_verify(u$hash, password), error = function(e) FALSE))
  if (!ok) {
    n <- if (is.null(f) || as.numeric(now) >= f$until) 1 else f$n + 1
    store$fails[[key]] <- list(n = n, until = as.numeric(now) + AUTH$lock_minutes * 60)
    return(list(ok = FALSE, status = 401, error = "wrong user name or password"))
  }
  if (!is.null(f)) rm(list = key, envir = store$fails)
  token <- sodium::bin2hex(sodium::random(32))
  exp <- as.numeric(now) + AUTH$session_hours * 3600
  store$sessions[[token]] <- list(user = key, expires = exp)
  list(ok = TRUE, token = token, expires_at = exp, user = auth_public(u))
}

auth_token_of <- function(req) {
  h <- req$HTTP_AUTHORIZATION %||% ""
  if (startsWith(h, "Bearer ")) substring(h, 8) else ""
}

auth_user <- function(store, token, now = Sys.time()) {
  if (!nzchar(token) || !exists(token, envir = store$sessions, inherits = FALSE)) return(NULL)
  s <- store$sessions[[token]]
  if (as.numeric(now) >= s$expires) { rm(list = token, envir = store$sessions); return(NULL) }
  u <- store$users[[s$user]]
  if (is.null(u)) NULL else c(auth_public(u), list(expires_at = s$expires))
}

auth_logout <- function(store, token) {
  if (nzchar(token) && exists(token, envir = store$sessions, inherits = FALSE)) rm(list = token, envir = store$sessions)
  invisible(TRUE)
}
