# Create or reset a sign-in account for the web UI (R/auth.R). Run from the project root:
#   Rscript scripts/32_create_user.R Nabi            -> asks for the password twice
#   Rscript scripts/32_create_user.R Nabi --print-env
#        also prints a QSTOCK_AUTH_USERS value for a cloud container (Render environment)
# The password is read from the terminal (hidden when the 'getPass' package is installed)
# and only its scrypt hash is written, to data/auth/users.json (git-ignored).
# Restart the API afterwards so it reads the new account.
for (f in c("R/auth.R")) source(f)
`%||%` <- function(x, y) if (is.null(x)) y else x
a <- commandArgs(trailingOnly = TRUE)
user <- a[!startsWith(a, "--")][1]
if (is.na(user)) stop("usage: Rscript scripts/32_create_user.R <user name> [--print-env]")
ask <- function(prompt) {
  if (requireNamespace("getPass", quietly = TRUE)) return(getPass::getPass(prompt))
  cat(prompt, "(visible: install.packages('getPass') to hide it) "); readLines(file("stdin"), n = 1)
}
p1 <- ask(sprintf("New password for %s: ", user)); p2 <- ask("Repeat it: ")
if (!identical(p1, p2)) stop("the two passwords differ; nothing was changed")
u <- auth_add_user(user, p1, display_name = user)
cat(sprintf("saved account '%s' (%s) to %s\n", u$username, u$role, AUTH$users_path))
if ("--print-env" %in% a)
  cat("\nQSTOCK_AUTH_USERS=", paste(readLines(AUTH$users_path), collapse = ""), "\n", sep = "")
