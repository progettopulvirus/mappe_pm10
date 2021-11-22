

#funzione per standardizzare le covariate spazio temporali
# @input: .x
# @output: una lista con: un dataframe con le colonne standardizzate, un dataframe con le medie
standarizza_covariate<-function(.x){
  
  purrr::map_dfc(.x,.f=mean,na.rm=TRUE)->medie
  purrr::map_dfc(.x,.f=sd,na.rm=TRUE)->deviazioni_standard
  purrr::pmap_dfc(.l=list(.dati=.x,.medie=medie,.sd=deviazioni_standard),.f=function(.dati,.medie,.sd){(.dati-.medie)/.sd})->df
  
  
  list(.x=df,.medie=medie,.sd=deviazioni_standard)
  
}



#########################
#salviamo nel database medie e sd perche' serviranno per la creazione delle mappe di pm10, per standardizzare i rasters
#########################

salva_parametri_per_standardizzazione<-function(.conn,.medie,.sd,.anno,.force=FALSE){
  
  check_conn(.conn)
  if(is.null(.medie)) stop("specificare .medie")
  if(is.null(.sd)) stop("specificare .sd")
  if(is.null(.anno)) stop("specificare .anno")
  
  .medie$param<-"media"
  .sd$param<-"sd"
  
  bind_rows(.medie,.sd)->daSalvare
  daSalvare$yy<-.anno
  
  daSalvare %>%
    gather(key="covariata",value="value",-yy,-param)->daSalvare
  
  RSQLite::dbExistsTable(mydb,"parametri_standardizzazione")->esiste
  
  paste0("(",str_c(paste0("'",unique(daSalvare$covariata),"'"),collapse=","),")")->COVARIATE

  if(esiste){
    
    dbGetQuery(.conn,glue::glue('SELECT * FROM parametri_standardizzazione WHERE "yy" = {.anno} AND "covariata" IN {COVARIATE};'))->tabella
    
    if(nrow(tabella) & !.force) stop(glue::glue("La tabella if(nrow(tabella) & !.force) già contiene i valori per l'anno {.anno}! Soluzione: .force=TRUE"))
    if(nrow(tabella) & .force) dbExecute(.conn,glue::glue('DELETE FROM parametri_standardizzazione WHERE "yy" = {.anno};'))
    
    dbAppendTable(.conn,"parametri_standardizzazione",daSalvare)    
    
  }else{
    
    dbWriteTable(.conn,"parametri_standardizzazione",daSalvare)
    
  }
  
}#fine salva_parametri_per_standardizzazione>
