# Bridge from R on the Windows host to the Cloudera QuickStart VM.
#
#   * HDFS: WebHDFS REST API on the NameNode (port 50070, NAT-forwarded).
#     Data-node redirects point at quickstart.cloudera:50075, which the host
#     cannot resolve, so the host part is rewritten to 127.0.0.1 (also forwarded).
#   * Commands (hadoop jar, beeline): ssh to the VM on host port 2222.

VM <- list(
  webhdfs = "http://127.0.0.1:50070/webhdfs/v1",
  user = "cloudera",
  ssh_key = file.path(Sys.getenv("USERPROFILE"), ".ssh", "qstock_vm_rsa"),
  ssh_port = 2222
)

webhdfs_url <- function(path, op, ...) {
  extra <- list(...)
  q <- paste0("op=", op, "&user.name=", VM$user,
              if (length(extra)) paste0("&", paste(names(extra), unlist(extra), sep = "=", collapse = "&")) else "")
  paste0(VM$webhdfs, path, "?", q)
}

webhdfs_call <- function(method, url, body = NULL) {
  h <- curl::new_handle(customrequest = method, followlocation = FALSE)
  if (!is.null(body)) curl::handle_setopt(h, post = TRUE, postfieldsize = length(body), postfields = body)
  curl::curl_fetch_memory(url, handle = h)
}

hdfs_mkdirs <- function(path) {
  r <- webhdfs_call("PUT", webhdfs_url(path, "MKDIRS"))
  stopifnot(r$status_code == 200)
  invisible(TRUE)
}

hdfs_put <- function(local, path, overwrite = TRUE) {
  r1 <- webhdfs_call("PUT", webhdfs_url(path, "CREATE", overwrite = tolower(overwrite)))
  if (r1$status_code != 307) stop("CREATE redirect failed: HTTP ", r1$status_code, " ", rawToChar(r1$content))
  loc <- curl::parse_headers_list(r1$headers)$location
  loc <- sub("^http://[^/:]+:", "http://127.0.0.1:", loc)
  body <- readBin(local, "raw", file.info(local)$size)
  r2 <- webhdfs_call("PUT", loc, body)
  if (r2$status_code != 201) stop("upload failed: HTTP ", r2$status_code, " ", rawToChar(r2$content))
  invisible(TRUE)
}

hdfs_ls <- function(path) {
  r <- webhdfs_call("GET", webhdfs_url(path, "LISTSTATUS"))
  if (r$status_code != 200) stop("LISTSTATUS failed: HTTP ", r$status_code)
  fs <- jsonlite::fromJSON(rawToChar(r$content))$FileStatuses$FileStatus
  if (length(fs) == 0) return(data.frame())
  data.frame(name = fs$pathSuffix, type = fs$type, size = fs$length,
             replication = fs$replication, block_size = fs$blockSize)
}

hdfs_get_text <- function(path) {
  r1 <- webhdfs_call("GET", webhdfs_url(path, "OPEN"))
  if (r1$status_code != 307) stop("OPEN redirect failed: HTTP ", r1$status_code)
  loc <- sub("^http://[^/:]+:", "http://127.0.0.1:", curl::parse_headers_list(r1$headers)$location)
  rawToChar(webhdfs_call("GET", loc)$content)
}

hdfs_delete <- function(path, recursive = TRUE) {
  webhdfs_call("DELETE", webhdfs_url(path, "DELETE", recursive = tolower(recursive)))
  invisible(TRUE)
}

vm_ssh <- function(cmd, echo = TRUE) {
  # Windows command-line quoting: ssh.exe receives `cmd` as one argument and the
  # remote bash parses it.
  q <- function(x) shQuote(x, type = if (.Platform$OS.type == "windows") "cmd" else "sh")
  args <- c("-i", q(VM$ssh_key), "-p", VM$ssh_port, "-o", "BatchMode=yes",
            "-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
            "-o", "KexAlgorithms=+diffie-hellman-group14-sha1",
            paste0(VM$user, "@127.0.0.1"), q(cmd))
  out <- suppressWarnings(system2("ssh", args, stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status"); if (is.null(status)) status <- 0L
  if (echo) cat(out, sep = "\n")
  if (status != 0) stop("remote command failed (", status, "): ", cmd)
  invisible(out)
}
