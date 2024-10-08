#' Automate the use of Docker & Make
#'
#' `automate()` & friends use yaml metadata from RMarkdowns to create
#' `Dockerfile`'s and `Makefile`'s. It should be clear which is created by
#' `automate_docker()` & which by `automate_make()`.
#' @param path Where should we look for RMarkdowns?
#' @seealso [automate_load_packages()], [automate_load_data()], [automate_load_scripts()]
#' @name automate
NULL

#' @rdname automate
#' @export
automate <- function(path = "."){
  automate_docker(path)
  #automate_publish(path)
  automate_make(path)
  if(uses_gha_publish(silent = TRUE))
    automate_make_rmd_check(path, target = "publish/")
  return(invisible(NULL))
}

#' @rdname automate
#' @export
automate_make <- function(path = "."){
  automate_make_rmd(path)
  # automate_make_bookdown()
  use_make(docker = FALSE, singularity = FALSE, torque = FALSE)
  if(uses_make_rmds(silent = TRUE))
    automate_make_rmd_check(path, target ="all")
}

#' @rdname automate
#' @export
automate_publish <- function(path = "."){
  if(automate_dir()){
    use_gha_docker()
    use_gha_publish()
    use_make_publish()
    automate_make_rmd_check(path = ".", target = "publish/")
  }
}

automate_make_rmd <- function(path){
  if(automate_dir()){
    yamls <- get_yamls(path)
    entries <- lapply(yamls, function(x)do.call(yaml_to_make, x))
    entries <- sort(unlist(entries))
    if(is.null(entries))xfun::write_utf8("", getOption("repro.makefile.rmds"))
    else {
      entries <- stringr::str_c(entries, "\n", collapse = "\n")
      xfun::write_utf8(entries, getOption("repro.makefile.rmds"))
    }
    usethis::ui_done("Writing {usethis::ui_path(getOption('repro.makefile.rmds'))}")
  }
}

automate_make_rmd_check <- function(path, edit = FALSE, target = "all"){
  if(!uses_make(silent = TRUE)){
    return(invisible())
  }
  yamls <- get_yamls(path)
  output_files <- lapply(yamls, function(x)do.call(get_output_files, x))
  output_files <- unlist(output_files)
  makefile <- xfun::read_utf8("Makefile")
  target_line <- makefile[stringr::str_detect(makefile, stringr::str_c("^", target, ":"))]
  which_missing <- lapply(output_files, function(x)!stringr::str_detect(target_line, x))
  missing <- output_files[unlist(which_missing)]
  if (length(target_line) > 1L) {
    usethis::ui_oops(
      "Ther are multiple {usethis::ui_value('Makefile')}-targets {usethis::ui_value(target)}. This is confusing, so consider joining them into one."
    )
  }
  else if (length(target_line) == 0L) {
    usethis::ui_todo(
      "There is no {usethis::ui_value('Makefile')}-target {usethis::ui_value(target)}. Create one with one or more dependencies:\n{usethis::ui_value(output_files)}"
    )
  }
  else if (length(missing) > 0){
    usethis::ui_todo(
      "Maybe you want to add:\n{usethis::ui_value(missing)}\nto the {usethis::ui_value('Makefile')}-target {usethis::ui_value(target)}."
    )
  }
  if(edit){
    usethis::edit_file("Makefile")
  }
}

yaml_to_make <- function(file, output, data = NULL, scripts = NULL, bibliography = NULL, images = NULL, files = NULL, ...){
  if(missing(file) || missing(output))return(NULL)
  output_file <- stringr::str_c(get_output_files(file, output), collapse = " ")
  deps <- stringr::str_c(c(file, data, scripts, bibliography, images, files), collapse = " ")
  stringr::str_c(output_file, ": ", deps, "\n\t",
                 "$(RUN1) Rscript -e 'rmarkdown::render(\"$(WORKDIR)/$<\", \"all\")' $(RUN2)")
}

get_output_files <- function(file, output, ...){
  if(missing(output))return(NULL)
  unlist(lapply(output, function(x)get_output_file(file, x)))
}

get_output_file <- function(file, output){
  get_fun <- function(x) {
    # from https://stackoverflow.com/a/38984214/7682760
    if(grepl("::", x)) {
      parts<-strsplit(x, "::")[[1]]
    } else {
      parts <- c("rmarkdown", x)
    }
    getExportedValue(parts[1], parts[2])
  }
  render_func <- do.call(get_fun(output), list())
  out <- do.call(utils::getFromNamespace("pandoc_output_file", "rmarkdown"),
          list(input = file,
               pandoc_options = render_func$pandoc))
  out <- stringr::str_c(dir_name(file), out)

}


#' @rdname automate
#' @export
automate_renv <- function(path = "."){
  if(automate_dir()){
    dockerfile_base <- getOption("repro.dockerfile.base")
    dockerfile_apt <- getOption("repro.dockerfile.apt")
    dockerfile_manual <- getOption("repro.dockerfile.manual")
    renv_file <- getOption("repro.dockerfile.renv")

    # handle base
    if(!fs::file_exists(dockerfile_base))use_docker(file = dockerfile_base,
                                                    open = FALSE)
    # handle apt
    docker_apt <- use_docker_apt(yamls_apt(path = usethis::proj_path(path)),
                                 file = dockerfile_apt,
                                 write = FALSE,
                                 append = FALSE)
    if(length(docker_apt) != 0L){
      xfun::write_utf8(docker_apt, dockerfile_apt)
      usethis::ui_done("Writing {usethis::ui_path(dockerfile_apt)}")
    }

    # handle renv
    renv_Packages <- use_renv(yamls_packages(path = usethis::proj_path(path)),
                              file = renv_file,
                              open = FALSE)
    note <- glue::glue("# Generated by repro: do not edit by hand
                       Please edit Dockerfiles in {getOption('repro.dockerfile.manual')}/")
    xfun::write_utf8(renv_Packages, renv_file)
    usethis::ui_done("Writing {usethis::ui_path(renv_file)}")
  }
  automate_renv_docker_bundle()
}

automate_renv_docker_bundle <- function(file = "Dockerfile"){
  dockerfiles <- c(
    dockerfile_base = getOption("repro.dockerfile.base"),
    dockerfile_manual = getOption("repro.dockerfile.manual"),
    dockerfile_apt = getOption("repro.dockerfile.apt"),
    renv_file = getOption("repro.dockerfile.renv"))

  note <- glue::glue("# Generated by repro: do not edit by hand
# Please edit Dockerfiles in {getOption('repro.dir')}/")
  to_read <- dockerfiles[unlist(lapply(dockerfiles, fs::file_exists))]
  to_write <- c(note, unlist(lapply(to_read, xfun::read_utf8)))
  xfun::write_utf8(to_write, file)
  usethis::ui_done("Writing {usethis::ui_path(file)}")
}


#' @rdname automate
#' @export
automate_docker <- function(path = "."){
  if(automate_dir()){
    dockerfile_base <- getOption("repro.dockerfile.base")
    dockerfile_packages <- getOption("repro.dockerfile.packages")
    dockerfile_manual <- getOption("repro.dockerfile.manual")
    dockerfile_apt <- getOption("repro.dockerfile.apt")

    # handle base
    if(!fs::file_exists(dockerfile_base))use_docker(file = dockerfile_base,
                                                    open = FALSE)
    # handle apt
    docker_apt <- use_docker_apt(yamls_apt(path = usethis::proj_path(path)),
                                 file = dockerfile_base,
                                 write = FALSE,
                                 append = FALSE)
    if(length(docker_apt) != 0L){
      xfun::write_utf8(docker_apt, dockerfile_apt)
      usethis::ui_done("Writing {usethis::ui_path(dockerfile_apt)}")
    }
    # handle packages
    docker_packages <- use_docker_packages(
      yamls_packages(path = usethis::proj_path(path)),
      file = dockerfile_base,
      github = TRUE,
      write = FALSE,
      append = FALSE
    )
    note <- glue::glue("# Generated by repro: do not edit by hand
                       Please edit Dockerfiles in {getOption('repro.dockerfile.manual')}/")
    xfun::write_utf8(docker_packages, dockerfile_packages)
    usethis::ui_done("Writing {usethis::ui_path(dockerfile_packages)}")

    # handle manual
    if(!fs::file_exists(dockerfile_manual)){
      fs::file_create(dockerfile_manual)
      usethis::ui_done("Writing {usethis::ui_path(getOption('repro.dockerfile.manual'))}")
    }

    # bundle dockerfiles
    automate_docker_bundle()
  }
}

automate_docker_bundle <- function(file = "Dockerfile"){
  dockerfiles <- c(
    dockerfile_base = getOption("repro.dockerfile.base"),
    dockerfile_manual = getOption("repro.dockerfile.manual"),
    dockerfile_apt = getOption("repro.dockerfile.apt"),
    dockerfile_packages = getOption("repro.dockerfile.packages"))
  note <- glue::glue("# Generated by repro: do not edit by hand
# Please edit Dockerfiles in {getOption('repro.dir')}/")
  to_read <- dockerfiles[unlist(lapply(dockerfiles, fs::file_exists))]
  to_write <- c(note, unlist(lapply(to_read, xfun::read_utf8)))
  xfun::write_utf8(to_write, file)
  usethis::ui_done("Writing {usethis::ui_path(file)}")
}

automate_dir <- function(dir, warn = FALSE, create = !warn){
  if(missing(dir))dir <- getOption("repro.dir")
  dir_full <- usethis::proj_path(dir)
  exists <- fs::dir_exists(dir_full)
  if(!exists){
    if(warn){
      usethis::ui_oops("Directory {usethis::ui_code(dir)} does not exist!")
    }
    if(create){
      fs::dir_create(dir_full)
      usethis::ui_done("Directory {usethis::ui_code(dir)} created!")
      exists <- fs::dir_exists(dir_full)
    }
  }
  if(exists){
    op <- options()
    depend_on_dir <- c(
      "repro.dockerfile.base",
      "repro.dockerfile.packages",
      "repro.dockerfile.manual",
      "repro.dockerfile.apt",
      "repro.makefile.docker",
      "repro.makefile.singularity",
      "repro.makefile.torque",
      "repro.makefile.rmds",
      "repro.makefile.publish"
    )
    allready_changed <- function(x){
      stringr::str_detect(op[[x]], stringr::str_c("^", op[["repro.dir"]]))
    }
    to_change <- depend_on_dir[!unlist(lapply(depend_on_dir, allready_changed))]
    op.repro <- lapply(to_change,
                       function(x)stringr::str_c(op[["repro.dir"]], "/", op[[x]]))
    names(op.repro) <- to_change
    options(op.repro)
    }
  return(exists)
}

#' Access repro YAML Metadata from within the document
#'
#' * `automate_load_packages()` loads all packages listed in YAML via `library()`
#' * `automate_load_scripts()` registeres external scripts via `knitr::read_chunk()`
#' * `automate_load_data()` reads in the data from the yaml with abitrary functions
#'
#' @param data How is the entry in the YAML called? It will be the name of the object.
#' @param func Which function should be used to read in the data? Its first argument must be the path to the file.
#' @param ... Further arguments supplied to `func`.
#' @return `automate_load_packages()` & `automate_load_scripts()` do not return anything. `automate_load_data()` returns the data.
#'
#' @name automate_load
NULL

#' @rdname automate_load
#' @export
automate_load_packages <- function(){
  packages <- yaml_repro_current()$packages
  strip_github <- function(x){
    splitted <- stringr::str_split(x, "[/|@]")[[1]]
    if(length(splitted) == 1L)return(splitted)
    else return(splitted[2])
  }
  packages <- lapply(packages, strip_github)
  lapply(packages, library, character.only = TRUE, quietly = TRUE)
  return(invisible(NULL))
}

#' @rdname automate_load
#' @export
automate_load_scripts <- function(){
  paths <- lapply(yaml_repro_current()$scripts, usethis::proj_path)
  scripts <- lapply(paths, xfun::read_utf8)
  lapply(scripts, function(x)knitr::read_chunk(lines = x))
  return(invisible(NULL))
}

#' @rdname automate_load
#' @export
automate_load_data <- function(data, func, ...){
  which <- deparse(substitute(data))
  path <- usethis::proj_path(yaml_repro_current()$data[[which]])
  data <- do.call(func, list(path, ...))
  return(data)
}
