#20 dicembre
rm(list=objects())
library("DBI")
library("tidyverse")
library("seplyr")
library("INLA")
library("terra")
library("sf")
library("sp")
library("guido")
library("lubridate")
library("regioniItalia")
library("config")
library("furrr")


future::plan(strategy=multicore,workers=20)

Sys.setenv("R_CONFIG_ACTIVE"=basename(getwd()))
myget<-purrr::partial(.f=config::get,file="../inla.yml")

annoF<-myget(value="annoF")
annoI<-annoF-1

#mesi
mesi<-myget("mesi")
primo_mese<-min(mesi)
ultimo_mese<-max(mesi)

parametri_spazio_temporali<-myget(value="parametri_spazio_temporali")
parametri_spaziali<-myget("parametri_spaziali")

#template per proiezione rasters UTM
rast("griglia.tif")->griglia
terra::ext(griglia)->estensione

#rasters spaziali
terra::rast("../d_a1_std.tif")->d_a1
terra::rast("../altitudedem_std.tif")->dem
terra::rast("../i_surface_std.tif")->i_surface

#la mesh non varia con i mesi
readRDS(glue::glue("mesh_{annoF}.RDS"))->mesh
inla.mesh.projector(mesh,xlim=c(estensione[1],estensione[2]),ylim=c(estensione[3],estensione[4]),dims = c(1287,999))->myproj

#calendario completo a partire dal 2012 (dal 25). I netCDF vanno dal 25 dicembre 2012 al 31 dicembre 2020. 
#calendarioCompleto ci serve per sapere la posizione dei layers che vogliamo estrarre, quindi importante che vi sia corrispondenza tra
#le date dei netCDF/tif e di calendarioCompleto.
creaCalendario(2012,2020) %>%
  mutate(yymmdd=as.Date(glue::glue("{yy}-{mm}-{dd}"),format="%Y-%m-%d")) %>%
  filter(yymmdd>=as.Date("2012-12-25"))->calendarioCompleto



purrr::walk(mesi,.f=function(MESE){
  
  #La mesh mi serve per proiettare il latent field
  readRDS(glue::glue("iset_{annoF}_{MESE}.RDS"))->iset
  
  
  #riporto le coordinate in km
  # mesh$loc[,1]<-mesh$loc[,1]*1000
  # mesh$loc[,2]<-mesh$loc[,2]*1000 
  
  
  primo_giorno_mese<-as.Date(glue::glue("{annoF}-{MESE}-1"),format="%Y-%m-%d")
  
  #il modello e' stato fatto girare dal 28 del mese precedente (per via dell'AR1) ma per le mappe ci serve solo il giorno precedente di ciascun mese
  ultimo_giorno_mese_precedente<-(primo_giorno_mese-1)
  
  #mese precedente
  lubridate::month(ultimo_giorno_mese_precedente)->mese_precedente
  lubridate::year(ultimo_giorno_mese_precedente)->anno_precedente #coincide con annoF, coincide con annoI solo a gennaio
  
  #28
  as.Date(glue::glue("{anno_precedente}-{mese_precedente}-28"))->giorno28
  as.integer(primo_giorno_mese-giorno28)->gap_primo_giorno_mese_e_giorno_28
  
  as.integer(lubridate::days_in_month(primo_giorno_mese))->numero_giorni_ultimo_mese
  ultimo_giorno_mese<-as.Date(glue::glue("{annoF}-{MESE}-{numero_giorni_ultimo_mese}"),format="%Y-%m-%d")
  
  seq.Date(ultimo_giorno_mese_precedente,ultimo_giorno_mese,by="day")->calendarioMappe
  which(calendarioCompleto$yymmdd %in% calendarioMappe)->righeCalendarioMappe
  stopifnot(length(righeCalendarioMappe) %in% 29:32)
  
  
  
  #estraggo dal brick i layers corrispondenti al periodo che va dal 25 dicembre di annoF-1 al 31 dicembre di annoF.
  purrr::map(parametri_spazio_temporali,.f=function(nomeParam){
    
    list.files(pattern = glue::glue("^std_new_{nomeParam}2012_2020.nc$"))->ffile
    if(length(ffile)!=1)  browser()
    
    terra::rast(ffile)->mybrick
    terra::subset(mybrick,righeCalendarioMappe)
    
  })->lista_rasters_spazio_temporali
  
  names(lista_rasters_spazio_temporali)<-parametri_spazio_temporali
  names(lista_rasters_spazio_temporali)[grep("^ptotal.+",names(lista_rasters_spazio_temporali))]<-"ptp"
  names(lista_rasters_spazio_temporali)[grep("^total.+",names(lista_rasters_spazio_temporali))]<-"tp"
  names(lista_rasters_spazio_temporali)[grep("^surface_.+",names(lista_rasters_spazio_temporali))]<-"sp"
  names(lista_rasters_spazio_temporali)[grep("^temperatura",names(lista_rasters_spazio_temporali))]<-"t2m"
  names(lista_rasters_spazio_temporali)[grep("^pbl00",names(lista_rasters_spazio_temporali))]<-"logpbl00"
  names(lista_rasters_spazio_temporali)[grep("^pbl12",names(lista_rasters_spazio_temporali))]<-"logpbl12"
  
  
  #leggi inla
  
  readRDS(glue::glue("result_{annoF}_{MESE}.RDS"))->inla.out
  terra::setValues(griglia,inla.out$summary.fixed["Intercept",]$mean)->intercetta
  
  #iid su station_eu_code
  inla.emarginal(fun=function(x){(1/exp(x))},inla.out$internal.marginals.hyperpar$`Log precision for station_eu_code`)->iid
  rnorm(terra::ncell(griglia),mean=0,sd=sqrt(iid))->vettore_normali
  terra::rast(matrix(vettore_normali,nrow = terra::nrow(griglia),ncol = terra::ncol(griglia)))->griglia_iid
  terra::crs(griglia_iid)<-"epsg:32632"
  terra::ext(griglia_iid)<-terra::ext(griglia)
  terra::crop(griglia_iid,griglia)->griglia_iid
  #
  furrr::future_map(2:length(calendarioMappe),.f=function(giorno){
    
    print(giorno)
    
    purrr::map(names(lista_rasters_spazio_temporali),.f=function(regressore){
      
      ifelse(regressore=="ptp",giorno-1,giorno)->indice
      
      inla.out$summary.fixed[regressore,]$mean*lista_rasters_spazio_temporali[[regressore]][[indice]]->griglia_regressore
      
      terra::project(griglia_regressore,intercetta)->utm_griglia
      terra::crop(utm_griglia,intercetta)->cropped_griglia
      terra::extend(cropped_griglia,intercetta)
      
      
    })->listaSomme
    
    
    purrr::reduce(listaSomme,.f=`+`,.init = intercetta)->sommaRastersSpazioTemporali
    
    sommaRastersSpazioTemporali+
      (d_a1*inla.out$summary.fixed["d_a1",]$mean)+
      (i_surface*inla.out$summary.fixed["i_surface",]$mean)+
      (dem*inla.out$summary.fixed["dem",]$mean)->sommaRasters
    
    
    #spde (media)
    inla.out$summary.random$i[iset$i.group==(gap_primo_giorno_mese_e_giorno_28+giorno-1),"mean"]->campo
    inla.mesh.project(myproj,campo)->campoProj
    raster::raster(list(x=myproj$x,y=myproj$y,z=campoProj))->myraster
    terra::rast(myraster)->myraster
    crs(myraster)<-"epsg:32632"
    
    terra::project(myraster,sommaRasters)->SPDE #spde medio per giorno yymmdd
    
    #sommaRasters+SPDE+griglia_iid->sommaRastersSPDE
    sommaRasters+SPDE->sommaRastersSPDE
    
    
    
    #Variance of the Gaussian observations 
    inla.emarginal(fun=function(x){(1/exp(x))},inla.out$internal.marginals.hyperpar$`Log precision for the Gaussian observations`)->mean_var_GO
    
    
    #campo medio di PM10
    exp(sommaRastersSPDE+0.5*mean_var_GO)-1->pm10
    #pm10[pm10>massimo]<-massimo
    #terra::mask(pm10,italia)->pm10 
    
    terra::wrap(trim(pm10))
    
    
  })->listaRasters
  
  purrr::map(listaRasters,.f=terra::rast)->unpacked_listaRasters
  names(unpacked_listaRasters)<-calendarioMappe[2:length(calendarioMappe)]
  #terra::rast(raster::brick(listaRasters))->mybrick
  terra::rast(unpacked_listaRasters)->mybrick

  suppressWarnings(terra::writeCDF(mybrick,glue::glue("mappe_{annoF}_{MESE}.nc"),varname="pm10",longname="particulate matter",compression=9,unit="",overwrite=TRUE))
  
}) #fine walk







