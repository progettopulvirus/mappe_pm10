#22 novembre 2021
#I dati in formato netCDF sono in epsg:4326. Vanno trasformati in tif con epsg: 32632
rm(list=objects())
library("tidyverse")
library("seplyr")
library("raster")
library("sf")
library("sp")
library("guido")
library("furrr")

future::plan(strategy ="multicore",workers=8)


#template per proiezione rasters UTM
raster("griglia.tif")->griglia


parametri<-c("ptotal_precipitation","surface_pressure","pbl12") #scrivere qui i nomi dei parametri che si vuole trasformare in tif con epsg:32632
#altri parametri: temperatura, pbl00, aod550, dust, total_precipitation

furrr::future_walk(parametri,.f=function(nomeParam){
  
  list.files(pattern = glue::glue("^new_{nomeParam}2012_2020.nc$"))->ffile
  if(length(ffile)!=1)  browser()
    
  brick(ffile)->mybrick
  #raster::subset(mybrick,1:10)->mybrick

  if(grepl("^pbl",nomeParam)) mybrick<-log(mybrick)
  
  projectRaster(from=mybrick,to=griglia)->utmGriglia
  raster::crop(utmGriglia,griglia)->utmGriglia2
  
  writeRaster(utmGriglia2,str_replace(ffile,"\\.nc$",".tif"),overwrite=TRUE)
  
})

