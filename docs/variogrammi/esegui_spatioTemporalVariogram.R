rm(list=objects())
library("tidyverse")
library("furrr")
library("config")
config::get(file="../inla.yml",value="annoF")->ANNO

future::plan(strategy = multicore,workers=12)

furrr::future_walk(c(7),.f=~(rmarkdown::render(input="spatioTemporalVariogram.Rmd",output_file=glue::glue("spatioTemporalVariogram_{ANNO}_{.}"),params = list(mese=.,anno=ANNO))))