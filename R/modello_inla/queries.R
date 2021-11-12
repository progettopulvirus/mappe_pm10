library("purrr")
library("RSQLite")

check_conn<-function(.conn){
  
  stopifnot(class(.conn)=="SQLiteConnection")
  
}


estrai_anagrafica<-function(.conn=NULL,.query=NULL){
  
  check_conn(.conn)
  if(is.null(.query)) stop("specificare .query") 
  
  dbGetQuery(.conn,.query)
  
}



estrai_meteo<-function(.conn=NULL,.query=NULL,.nome_parametro=NULL){
  
  check_conn(.conn)
  if(is.null(.query)) stop("specificare .query") 
  if(is.null(.nome_parametro)) stop("specificare .nome_parametro")
  

  dbGetQuery(mydb,.query) %>%
    gather(key="station_eu_code",value="value",-yy,-mm,-dd) %>%
    seplyr::rename_se(c(.nome_parametro := "value")) 

}#fine estrai_meteo



estrai_pm10<-function(.conn=NULL,.query=NULL){

  check_conn(.conn)
  if(is.null(.query)) stop("specificare .query") 
  
  dbGetQuery(.conn,.query)  
  
}




