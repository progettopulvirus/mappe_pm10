rm(list=objects())
library("DBI")
library("tidyverse")
library("seplyr")
library("INLA")
library("sf")
library("sp")
library("regioniItalia")
source("queries.R")
source("utilities.R")


annoF<-2020
annoI<-annoF-1

parametri<-c("ptotal_precipitation","surface_pressure","temperatura","total_precipitation","pbl00","pbl12")


dbConnect(RSQLite::SQLite(),"pm10_maps.sqlite")->mydb

estrai_anagrafica(.conn=mydb,.query="SELECT * FROM anagrafica;") %>% 
  dplyr::select(station_eu_code,st_x,st_y,altitudedem,d_a1,i_surface)->ana

estrai_pm10(.conn=mydb,.query=glue::glue('SELECT * FROM pm10 WHERE ("yy" = {annoF}) OR ("yy"={annoF-1} AND mm=12 AND dd >=26);'))->pm10

purrr::map(parametri,.f=function(.param,.y){
  
  estrai_meteo(.conn=mydb,.query=glue::glue('SELECT * FROM {.param} WHERE "yy"= {annoF} OR ("yy"={annoF-1} AND mm=12 AND dd >=26)'),.nome_parametro=.param) 
  
})->lista_dati_meteo

purrr::reduce(lista_dati_meteo,.f=left_join,by=c("yy","mm","dd","station_eu_code"))->dati_meteo

#standardizza dati meteo
standarizza_covariate(.x=dati_meteo %>% dplyr::select(-yy,-mm,-dd,-station_eu_code))->listaMeteo

#salviamo nel database medie e sd perche' serviranno per la creazione delle mappe di pm10, per standardizzare i rasters
salva_parametri_per_standardizzazione(.conn=mydb,.medie=listaMeteo[[".medie"]],.sd=listaMeteo[[".sd"]],.anno=annoF,.force=TRUE)

#standardizza dati anagrafica
standarizza_covariate(.x=ana %>% dplyr::select(-station_eu_code,-st_x,-st_y))->listaSpatial

#salviamo nel database medie e sd perche' serviranno per la creazione delle mappe di pm10, per standardizzare i rasters
salva_parametri_per_standardizzazione(.conn=mydb,.medie=listaSpatial[[".medie"]],.sd=listaSpatial[[".sd"]],.anno=annoF,.force=TRUE)


bind_cols(dati_meteo %>% dplyr::select(yy,mm,dd,station_eu_code),listaMeteo[[".x"]])->std_dati_meteo
left_join(pm10,std_dati_meteo,by=c("yy","mm","dd","station_eu_code"))->pm10

bind_cols(ana %>% dplyr::select(station_eu_code,st_x,st_y),listaSpatial[[".x"]])->std_dati_spatial
left_join(pm10,std_dati_spatial,by=c("station_eu_code"))->pm10

dbDisconnect(mydb)


##################
###### INLA ######
##################

pm10 %>%
  mutate(lvalue=log(value+0.1)) %>%
  mutate(Intercept=1) %>%
  rename()->pm10

####Priors:
list(prior="pc.cor1",param=c(0.8,0.318))->theta_hyper #prior per la parte autoregressiva di spde: con probabilita <0.318 il rho sara' > di 0.8
####

######################## FORMULA MODELLO: la parte random (spde, etc) viene aggiunta prima del comando inla()
as.formula(lvalue~Intercept+dust+aod550+logpbl00+logpbl12+sp+t2m+tp+ptp+dem+i_surface+d_a1-1)->myformula
terms(myformula)->termini
attr(termini,which="term.labels")->VARIABILI
########################

st_as_sf(ana,coords=c("st_x","st_y"),crs=4326)->sfAna
st_transform(sfAna,crs=32632)->utm_sfAna
st_coordinates(utm_sfAna)->puntiCoordinate


##################
##### Distinguiamo tra Penisola e Sardegna
##################
st_crs(sardegna)<-32632
st_buffer(sardegna,dist=20000)->sardegna
st_intersection(utm_sfAna,sardegna)->stazioniSardegna

stazioniSardegna$station_eu_code->codiciSardegna
st_coordinates(stazioniSardegna)->puntiSardegna

st_coordinates(utm_sfAna %>% filter(!station_eu_code %in% codiciSardegna))->puntiStivale

#stivale: non-convex-hull for the 410 Italian monitoring sites, excluding Sardegna
inla.nonconvex.hull(points =  puntiStivale)->stivale

#sardegna: non-convex-hull for the Sardegna monitoring sites
inla.nonconvex.hull(points = puntiSardegna)->isola 

#mesh triangulation for the study domain including Sardegna
mesh_modello<-inla.mesh.2d(boundary =list(list(stivale,isola)), max.edge = c(30000,150000),cutoff=5000,offset=c(10000),min.angle = 25)

inla.spde.make.A(mesh=mesh_modello,loc = ,group = )





