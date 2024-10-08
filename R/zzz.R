.onLoad <- function(...){
  op <- options()
  op.repro <- list(
    repro.dir = ".repro",
    repro.dockerfile.base = "Dockerfile_base",
    repro.dockerfile.packages = "Dockerfile_packages",
    repro.dockerfile.apt = "Dockerfile_apt",
    repro.dockerfile.renv = "Renv_base",
    repro.dockerfile.manual = "Dockerfile_manual",
    repro.dockerignore = ".dockerignore",
    repro.makefile.docker = "Makefile_Docker",
    repro.makefile.singularity = "Makefile_Singularity",
    repro.makefile.torque = "Makefile_TORQUE",
    repro.makefile.rmds = "Makefile_Rmds",
    repro.makefile.publish = "Makefile_publish",
    repro.docker = NA,
    repro.docker.running = NA,
    repro.make = NA,
    repro.git = NA,
    repro.choco = NA,
    repro.brew = NA,
    repro.ssh = NA,
    repro.renv = NA,
    repro.targets = NA,
    repro.worcs = NA,
    repro.os = NA,
    repro.github = NA,
    repro.github.ssh = NA,
    repro.github.token = NA,
    repro.github.token.access = NA,
    repro.gha.docker = ".github/workflows/push-container.yml",
    repro.gha.publish = ".github/workflows/publish.yml",
    repro.pkgtest = FALSE,
    repro.install = "ask",
    repro.reproduce.funs = reproduce_funs,
    repro.reproduce.msg = NA
    )
  toset <- !(names(op.repro) %in% names(op))
  if(any(toset)) options(op.repro[toset])
  invisible()
}

.onAttach <- function(...){
  packageStartupMessage(
    usethis::ui_info(
      "repro is BETA software! Please report any bugs:
    {usethis::ui_value('https://github.com/aaronpeikert/repro/issues')}")
  )
}

get_os <- function(){
  if(is.na(getOption("repro.os"))){
    sysinf <- Sys.info()
    if(getOption("repro.pkgtest"))stop("Set a fake os while testing os dependend functions.", call. = FALSE)
    if (!is.null(sysinf)){
      os <- sysinf['sysname']
      if (os == 'Darwin')
        os <- "osx"
    } else { ## mystery machine
      os <- .Platform$OS.type
      if (grepl("^darwin", R.version$os))
        os <- "osx"
      if (grepl("linux-gnu", R.version$os))
        os <- "linux"
    }
    os <- tolower(os)
    options(repro.os = os)
    return(os)
  } else {
    return(getOption("repro.os"))
  }
}

silent_command <- function(...){
  suppressMessages(suppressWarnings(system2(..., stdout = tempfile(), stderr = tempfile())))
}

dir_name <- function(path){
  out <- dirname(path)
  if(out == ".")return("")
  else stringr::str_c(out, "/")
}
