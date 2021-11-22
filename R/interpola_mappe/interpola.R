#I file .tif sono stati ottenuti dai file netCDF usando il programma proietta.R. 
#Attenzione,il pbl e' già stato trasformato applicando il logaritmo
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



annoF<-2015
annoI<-annoF-1

#template per proiezione rasters UTM
rast("griglia.tif")->griglia


parametri<-c("aod550","dust","surface_pressure","temperatura","total_precipitation","pbl00","pbl12","ptotal_precipitation")


#calendario completo a partire dal 2012 (dal 25). I netCDF vanno dal 25 dicembre 2012 al 31 dicembre 2020. 
#calendarioCompleto ci serve per sapere la posizione dei layers che vogliamo estrarre, quindi importante che vi sia corrispondenza tra
#le date dei netCDF/tif e di calendarioCompleto.
creaCalendario(2012,2020) %>%
  mutate(yymmdd=as.Date(glue::glue("{yy}-{mm}-{dd}"),format="%Y-%m-%d")) %>%
  filter(yymmdd>=as.Date("2012-12-25"))->calendarioCompleto


dbConnect(RSQLite::SQLite(),"pm10_maps.sqlite")->mydb
dbGetQuery(mydb,glue::glue('SELECT * FROM parametri_standardizzazione WHERE "yy"  = {annoF} '))->parametri_per_standardizzare_rasters
dbDisconnect(mydb)


#estraggo dal brick i layers corrispondenti al periodo che va dal 25 dicembre di annoF-1 al 31 dicembre di annoF.
#Per trovare i layers che mi interessano uso
#il calendario completo
purrr::map(parametri,.f=function(nomeParam){
  
  list.files(pattern = glue::glue("^new_{nomeParam}2012_2020.tif$"))->ffile
  if(length(ffile)!=1)  browser()
    
  terra::rast(ffile)->mybrick
  
  #if(grepl("^pbl",nomeParam)) mybrick<-log(mybrick) <----questo non serve, il tif e' già il logaritmo del pbl
  
  #standardizziamo
  if(1==0){
    which(grepl(glue::glue("^{nomeParam}"),parametri_per_standardizzare_rasters$covariata))->righe
    parametri_per_standardizzare_rasters[righe,]->df
    df[df$param=="media",]$value->.media
    df[df$param=="sd",]$value->.sd
    if(length(righe)!=2) browser()
      
    terra::app(mybrick,fun = function(.x){ (.x-.media)/.sd })
  }else{
    mybrick
  }
  
})->lista_rasters_spaziali

names(lista_rasters_spaziali)<-parametri

purrr::walk(2,.f=function(MESE){
  
  primo_giorno_mese<-as.Date(glue::glue("{annoF}-{MESE}-1"),format="%Y-%m-%d")
  primo_giorno_mese-1->ultimo_giorno_mese_precedente
  
  #Il modello e' stato fatto girare partendo dal giorno 28 del mese precedente (questo perche' il modello INLA contiene una componente AR1
  #per cui per la stima del primo giorno del mese X avremo bisogno almeno dell'ultimo giorno del mese X-1). Prendendo dal 28
  #siamo sicuri di avere anche i dati per la stima del 1 marzo in un anno bisestile e non bisestile.
  as.Date(glue::glue("{year(ultimo_giorno_mese_precedente)}-{month(ultimo_giorno_mese_precedente)}-28"),format="%Y-%m-%d")->primo_giorno
  
  as.integer(lubridate::days_in_month(primo_giorno_mese))->numero_giorni_del_mese
  ultimo_giorno_mese<-as.Date(glue::glue("{annoF}-{MESE}-{numero_giorni_del_mese}"),format="%Y-%m-%d")
  
  seq.Date(primo_giorno,ultimo_giorno_mese,by="day")->periodo_di_studio
  
  #righe mi dice dove stanno i rasters che mi interessano all'interno delo brick
  which(calendarioCompleto$yymmdd %in% periodo_di_studio)->righe
  stopifnot(length(righe)!=0)
  
  #readRDS('glue::glue("result_{annoF}_{MESE}.RDS")')->inla.out  
  
  purrr::map(lista_rasters_spaziali,.f = raster::subset,righe)->sub_lista_rasters_spazio_temporali
  
  
  
  purrr::imap(periodo_di_studio,.f=function(.x,.i){
    
    
    purrr::map(sub_lista_rasters_spazio_temporali,.f=terra::subset,.i)->rasters_giorno_i
    browser()
    
  })

  

}) #fine walk







