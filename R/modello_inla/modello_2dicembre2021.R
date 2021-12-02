#2 dicembre
rm(list=objects())
library("DBI")
library("tidyverse")
library("seplyr")
library("INLA")
library("sf")
library("sp")
library("lubridate")
library("regioniItalia")
library("config")
source("queries.R")
source("utilities.R")

inla.setOption(pardiso.license = "~/pardiso/licenza.txt")

Sys.setenv("R_CONFIG_ACTIVE"=basename(getwd()))
myget<-purrr::partial(.f=config::get,file="../inla.yml")


#anno da elaborare
annoF<-myget("annoF")
annoI<-annoF-1

#mesi
mesi<-myget("mesi")

parametri_spazio_temporali<-myget("parametri_spazio_temporali")
parametri_spaziali<-myget("parametri_spaziali")

dbConnect(RSQLite::SQLite(),myget("database"))->mydb

estrai_anagrafica(.conn=mydb,.query="SELECT * FROM anagrafica;") %>% 
  dplyr::select(station_eu_code,st_x,st_y)->ana

estrai_pm10(.conn=mydb,.query=glue::glue('SELECT * FROM pm10 WHERE ("yy" = {annoF}) OR ("yy"={annoF-1} AND mm=12 AND dd >=28);'))->pm10

purrr::map(parametri_spazio_temporali,.f=function(.param,.y){
  
  estrai_meteo(.conn=mydb,.query=glue::glue('SELECT * FROM {.param} WHERE "yy"= {annoF} OR ("yy"={annoF-1} AND mm=12 AND dd >=28)'),.nome_parametro=.param)
  
})->lista_dati_meteo

#PBL e AOD derivano da grigliati con una differente risoluzione spaziale rispetto ai grigliati dei dati meteo. Per questo motivo alcuni punti stazione che hanno NA
#per il meteo possono avere dati validi per PBL e AOD
names(lista_dati_meteo)<-parametri_spazio_temporali
purrr::reduce(lista_dati_meteo,.f=left_join,by=c("yy","mm","dd","station_eu_code"))->dati_meteo

left_join(pm10,dati_meteo,by=c("yy","mm","dd","station_eu_code"))->pm10

purrr::map(parametri_spaziali,.f=function(.param,.y){
  
  dbGetQuery(mydb,glue::glue("SELECT * FROM {.param};"))
  
})->lista_dati_spaziali

names(lista_dati_spaziali)<-parametri_spaziali
purrr::reduce(lista_dati_spaziali,.f=left_join,by=c("station_eu_code"))->dati_spaziali

left_join(pm10,dati_spaziali,by=c("station_eu_code"))->pm10

dbDisconnect(mydb)

##################
###### INLA ######
##################

#Creo il logaritmo della variabile target (lpm10) e rinomino le covariate. Si noti che il pbl diventa il logaritmo del pbl.
#Infatti il pbl e' già stato trasformato nel logaritmo a livello di file netCDF.
pm10 %>%
  mutate(yymmdd=as.Date(glue::glue("{yy}-{mm}-{dd}",format="%Y-%m-%d"))) %>%
  mutate(lpm10=log(value+1)) %>%
  mutate(Intercept=1) %>%
  rename(ptp=ptotal_precipitation,tp=total_precipitation,t2m=temperatura,sp=surface_pressure,dem=altitudedem,logpbl00=pbl00,logpbl12=pbl12)->pm10

####Priors:
list(prior="pc.cor1",param=c(0.8,0.318))->theta_hyper #prior per la parte autoregressiva di spde: con probabilita <0.318 il rho sara' > di 0.8
####

######################## FORMULA MODELLO: la parte random (spde, etc) viene aggiunta prima del comando inla()
as.formula(lpm10~Intercept+dust+aod550+logpbl00+logpbl12+sp+t2m+tp+ptp+dem+i_surface+d_a1-1)->myformula
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
suppressWarnings({st_intersection(utm_sfAna,sardegna)->stazioniSardegna})

stazioniSardegna$station_eu_code->codiciSardegna
st_coordinates(stazioniSardegna)->puntiSardegna

st_coordinates(utm_sfAna %>% filter(!station_eu_code %in% codiciSardegna))->puntiStivale

#stivale: non-convex-hull for the 410 Italian monitoring sites, excluding Sardegna
inla.nonconvex.hull(points =  puntiStivale)->stivale

#sardegna: non-convex-hull for the Sardegna monitoring sites
inla.nonconvex.hull(points = puntiSardegna)->isola 

#mesh triangulation for the study domain including Sardegna
mesh_modello<-inla.mesh.2d(boundary =list(list(stivale,isola)), max.edge = c(30000,150000),cutoff=5000,offset=c(10000),min.angle = 25)
saveRDS(mesh_modello,glue::glue("mesh_{annoF}.RDS"))

#plot(mesh_modello)
#plot(st_geometry(utm_sfAna),add=TRUE,col="red")

#spde
inla.spde2.pcmatern(mesh=mesh_modello,alpha=2,constr=FALSE,prior.range = c(150,0.8),prior.sigma = c(0.8,0.2))->spde
saveRDS(spde,glue::glue("spde_{annoF}.RDS"))


purrr::walk(myget("mesi"),.f=function(MESE){
  
  as.Date(glue::glue("{annoF}-{MESE}-{01}"),format="%Y-%m-%d")->primo_giorno_mese
  primo_giorno_mese-1->ultimo_giorno_mese_precedente
  
  #Se l'anno e' bisestile significa che il 1 marzo lo stimeremo usando il 29 febbraio, altrimenti il 28 febbraio
  #Il primo maggio sarà stimato usando il 30 aprile
  #Il primo giugno sarà stimato usando il 31 maggio
  #etc etc
  as.Date(glue::glue("{year(ultimo_giorno_mese_precedente)}-{month(ultimo_giorno_mese_precedente)}-28"),format="%Y-%m-%d")->primo_giorno
  
  #questo valore cambia in base al mese e all'anno (per febbraio)
  as.integer(days_in_month(primo_giorno_mese))->numero_di_giorni_del_mese
  as.Date(glue::glue("{annoF}-{MESE}-{numero_di_giorni_del_mese}"),format="%Y-%m-%d")->ultimo_giorno_mese
  
  #per la mesh: devo considerare che il numero di giorni è numero_di_giorni_del_mese piu' la settimana antecedente
  seq.Date(primo_giorno,ultimo_giorno_mese,by="day")->periodo_di_studio
  length(periodo_di_studio)->numero_di_giorni
  
  
  pm10 %>%
    filter(yymmdd %in% periodo_di_studio) %>%
    mutate(banda=as.integer(yymmdd-(primo_giorno-1))) %>%
    dplyr::select(banda,yymmdd,everything()) %>%
    arrange(banda,station_eu_code)->subpm10
  
  left_join(subpm10,ana %>% dplyr::select(station_eu_code,st_x,st_y))->subpm10
  
  saveRDS(subpm10,glue::glue("subpm10_{annoF}_{MESE}.RDS"))
  
  
  st_as_sf(subpm10 %>% dplyr::select(st_x,st_y),coords=c("st_x","st_y"),crs=4326)->coordinatePuntiTraining
  as.matrix(st_coordinates(st_transform(coordinatePuntiTraining,crs=32632)))->coordinatePuntiTraining
  
  #i e' il nome che identifica l'spde 
  inla.spde.make.index(name="i",n.spde=spde$n.spde,n.group = numero_di_giorni)->iset
  saveRDS(iset,glue::glue("iset_{annoF}_{MESE}.RDS"))
  
  
  inla.spde.make.A(mesh=mesh_modello,loc=coordinatePuntiTraining,group = subpm10$banda,n.spde=spde$n.spde,n.group =numero_di_giorni )->A.training
  inla.stack(data=list(lpm10=subpm10$lpm10),A=list(A.training,1),effects=list(iset,subpm10[c("station_eu_code",attr(termini,"term.labels"))]),tag="training")->mystack
  saveRDS(mystack,glue::glue("stack_{annoF}_{MESE}.RDS"))
  
  ########################
  #aggiungo i random effects alla formula
  #iid su id_centralina e una componente autorgressiva su spde (variabile i)
  update(myformula,.~.+f(station_eu_code,model="iid")+f(i,model=spde,group = i.group,control.group = list(model="ar1",hyper=list(theta=theta_hyper))))->myformula
  

  inla(myformula,
       data=inla.stack.data(mystack,spde=spde),
       family ="gaussian",
       verbose=TRUE,
       control.compute = list(cpo=TRUE,waic=TRUE,dic=TRUE,config=TRUE), #openmp.strategy="pardiso",
       control.fixed = list(prec.intercept = 1, prec=0.01,mean.intercept=0),
       control.predictor =list(A=inla.stack.A(mystack),compute=TRUE) )->inla.out
  
  
  # envelope() %>%
  #   from('guido.fioravanti@isprambiente.it') %>%
  #   to('guido.fioravanti@isprambiente.it')  %>%
  #   subject(glue::glue('Modello INLA pm10 anno {annoF} mese {MESE} ')) %>%
  #   emayili::text(glue::glue("Ho finito! {Sys.time()}"))->emailFinale
  # 
  # smtp(emailFinale,verbose=FALSE)
  
  #A scopo esplorativo conviene non salvare l'output (operazione molto lenta, in lettura e scrittura, quando si hanno tanti dati)
  #ma piuttosto salvare subito i dati in file csv o far girare qui gli script Rmarkdown utilizzando l'oggetto inla.out
  
  saveRDS(inla.out,glue::glue("result_{annoF}_{MESE}.RDS"))
  
  rmarkdown::render(input="analisi-covariate.Rmd",output_file = glue::glue("analisi-covariate_{annoF}_{MESE}.html"),params = list(result=inla.out,anno=annoF,mese=MESE))
  
})







