#5 novembre 2021...questo programma serve per estrarre i dati per le mappe giornaliere del PM10. Si tratta di un riadattamento del programma utilizzato per il progetto pulvirus.
#Per ogni anno vengono estratti anche ivalori dal 25 dicembre dell'anno precedente visto che il modello ha una componente AR1.
#
rm(list=objects())
library("tidyverse")
library("RPostgreSQL")
library("sf")
library("furrr")
library("visdat")
library("lubridate")
library("seplyr")
library("guido")
options(error=browser)



### parametri
#PARAM_vista<-c("v_pm10","v_pm25","v_no2","v_nox","v_c6h6","v_co","v_o3","v_so2")[3]
PARAM_vista<-c("v_pm10")[1]
PARAM<-str_remove(PARAM_vista,"v_")

#PARAM_O3<-c("o3_max_h_d","o3_max_mm8h_d")[2] 


annoI<-2012
annoF<-2020

creaCalendario(annoI,annoF) %>%
  mutate(yymmdd=as.Date(glue::glue("{yy}-{mm}-{dd}"),format="%Y-%m-%d")) %>%
  filter(yymmdd >= as.Date(glue::glue("{annoI}-12-25"),format="%Y-%m-%d")) %>%
  dplyr::select(-yymmdd)->calendario

#mettere TRUE per invalidare i dati in modo di testare la routine di selezione delle serie valide
INVALIDA<-FALSE
PERCENTUALE_DA_INVALIDARE<-0.25 

#Quanti mesi validi debbono esserci nel 2020? Tutti i mesi debbono essere validi? C'è un margine di tolleranza?
NUMERO_MESI_VALIDI_ULTIMO_ANNO<-12  
###


numeroAnni<-(annoF)-annoI+1
SOGLIA_ANNI_VALIDI<-floor((numeroAnni-1)*0.75)

numeroGiorni<-31
SOGLIA_GIORNI_VALIDI<-floor(numeroGiorni*0.75)

if(file.exists(glue::glue("stazioniNonValide_{PARAM}.csv"))) file.remove(glue::glue("stazioniNonValide_{PARAM}.csv"))
if(file.exists(glue::glue("stazioniValide_{PARAM}.csv"))) file.remove(glue::glue("stazioniValide_{PARAM}.csv"))
if(file.exists(glue::glue("numeroStazioniValidePerRegione_{PARAM}.csv"))) file.remove(glue::glue("numeroStazioniValidePerRegione_{PARAM}.csv"))
system("rm -rf completezzaAnni_*.csv")

if(file.exists(glue::glue("{PARAM}.csv"))){ 
    
  read_delim(glue::glue("{PARAM}.csv"),delim=";",col_names = TRUE,col_types = cols(value=col_double()))->datiTutti
  read_delim(glue::glue("ana.csv"),delim=";",col_names = TRUE)->ana
  
  left_join(datiTutti,ana[,c("station_eu_code","regione")])->datiTutti
  
}else{ 
  
  dbDriver("PostgreSQL")->mydrv
  dbConnect(drv=mydrv,dbname="pulvirus",host="10.158.102.164",port=5432,user="srv-pulvirus",password="pulvirus#20")->myconn
  dbReadTable(conn=myconn,name = c(PARAM_vista),)->datiTutti
  suppressWarnings({dbReadTable(conn=myconn,name = c("stazioni_aria"))->ana})
  dbDisconnect(myconn)
  
  
  
  
  if(PARAM=="o3"){ 

    datiTutti %>%
      seplyr::rename_se(c("value":=PARAM_O3)) %>%
      dplyr::select(reporting_year,pollutant_fk,station_eu_code,date,value)->datiTutti
    
    PARAM<-PARAM_O3
    
  }
    
  #le stringhe NA vengono lette come carattere
  suppressWarnings(mutate(datiTutti,value=as.double(value))->datiTutti)
  
  datiTutti %>%
    mutate(mm=lubridate::month(date)) %>%
    mutate(yy=lubridate::year(date))->datiTutti
  
  write_delim(datiTutti,glue::glue("{PARAM}.csv"),delim=";",col_names = TRUE)
  write_delim(ana,glue::glue("ana.csv"),delim=";",col_names = TRUE)
  
  
}#fine if 

###########################
#
#  Scrittura output
#
###################

nonValida<-function(codice,regione,param,error=""){
  sink(glue::glue("stazioniNonValide_{param}.csv"),append=TRUE)
  cat(paste0(glue::glue("{codice};{error};{regione}"),"\n")) 
  sink()
}#fine nonValida 

valida<-function(codice,regione,param){
  sink(glue::glue("stazioniValide_{param}.csv"),append=TRUE)
  cat(paste0(glue::glue("{codice};{regione}"),"\n"))
  sink()
}#fine nonValida 

purrr::partial(nonValida,param=PARAM)->nonValida
purrr::partial(valida,param=PARAM)->valida

###########################

### Inizio programma

left_join(datiTutti,ana[,c("station_eu_code","regione")]) %>%
  filter(reporting_year %in% annoI:annoF)->datiTutti

purrr::map(unique(ana$regione),.f=function(nomeRegione){ 
  
    datiTutti %>%
      filter(regione==nomeRegione)->dati
  
    #La regione ha dati? 
    if(!nrow(dati)) return()
  
    #Ciclo su codici delle stazioni della regione 
    purrr::map(unique(dati$station_eu_code),.f=function(codice){ 
      
      dati %>%
        filter(station_eu_code==codice)->subDati
      
      if(!nrow(subDati)){ 
        nonValida(codice,regione =nomeRegione)
        return()
      }
      
      
      subDati %>%
        filter(!is.na(value)) %>%
        group_by(yy,mm) %>%
        summarise(numeroDati=n()) %>%
        ungroup()->ndati
      
     

      #elimino mesi con meno del 75% di dati disponibili  
      ndati %>%
        mutate(meseValido=case_when(numeroDati>=SOGLIA_GIORNI_VALIDI~1,
                                    TRUE~0))->ndati
      
      #aggiungo stagione  
      ndati %>%
        mutate(seas=case_when(mm %in% c(1,2,12)~1,
                              mm %in% c(3,4,5)~2,
                              mm %in% c(6,7,8)~3,
                              TRUE~4)) %>%
        group_by(yy,seas) %>%
        summarise(stagioneValida=sum(meseValido)) %>%
        ungroup()->ndati2

      #elimino le stagioni con meno di due mesi validi
      ndati2 %>%
        filter(stagioneValida>=1)->ndati2
      
      
      #nessuna stagione valida: serie sfigata (esiste?)  
      if(!nrow(ndati2)){ 
        nonValida(codice,regione=nomeRegione,error="NessunaStagioneValida")
        return()
      }
      
      
      #cerchiamo gli anni validi
      ndati2 %>%
        group_by(yy) %>%
        summarise(annoValido=n()) %>%
        ungroup()->ndati3
    
      #un anno e' valido se ha le 4 stagioni valide  
      ndati3 %>%
        filter((annoValido==4))->ndati3

      nrow(ndati3)->numeroAnniValidi
      
      if(!numeroAnniValidi){ 
        nonValida(codice,regione=nomeRegione,error=glue::glue("Nessun_Anno_Valida_{annoI}_{annoF}"))
        return()  
      } 
      
      names(ndati3)<-c("yy",codice)
    
      valida(codice,regione=nomeRegione)
      
      ndati3
      
    })->listaOut

    purrr::compact(listaOut)->listaOut
    length(listaOut)->numeroStazioniValide
    
    sink(glue::glue("numeroStazioniValidePerRegione_{PARAM}.csv"),append=TRUE)
    cat(paste0(nomeRegione,";",numeroStazioniValide,"\n"))
    sink()
    
    if(!numeroStazioniValide) return()
      
    ##### Fine mappa stazioni
    purrr::reduce(listaOut,full_join)->dfFinale
    
    names(dfFinale)[!grepl("^yy",names(dfFinale))]->codiciStazioniSelezionate

    dati %>%
      mutate(dd=lubridate::day(date)) %>%
      dplyr::select(pollutant_fk,regione,station_eu_code,date,yy,mm,dd,value) %>%
      filter(station_eu_code %in% codiciStazioniSelezionate)->daScrivere
    
    if(nrow(daScrivere)){
      
      duplicated(x = daScrivere[,c("station_eu_code","date")])->osservazioniDuplicate

      if(nrow(daScrivere[osservazioniDuplicate,])){ 
        message("Trovate osservazioni duplicate, mi fermo!")
        browser()
        return()
      }      

    }  
    
    #i nomi del detaframe sono le stazioni valide
    write_delim(dfFinale,glue::glue("completezzaAnni_{PARAM}_{nomeRegione}.csv"),delim=";",col_names = TRUE)

    
    daScrivere %>%
      dplyr::select(yy,mm,dd,station_eu_code,value) %>%
      spread(key=station_eu_code,value=value)
    

})->listaDatiRegionali #fine map su regione 


purrr::compact(listaDatiRegionali)->listaDatiRegionali
if(!length(listaDatiRegionali)) stop("Nessuna regione ha dati validi!")

purrr::reduce(listaDatiRegionali,.f=left_join,.init=calendario,by=c("yy","mm","dd"))->finale
              
gather(finale,key="station_eu_code",value="value",-yy,-mm,-dd)->gfinale

write_delim(gfinale,glue::glue("dati_{PARAM}_{annoI}_{annoF}.csv"),delim=";",col_names=TRUE)

