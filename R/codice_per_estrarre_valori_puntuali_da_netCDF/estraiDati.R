#Questo programma estrae i dati copernicus dalle stazioni di PM10 e li salva sia come file .csv sia come tabelle nel dabatse SQLite
rm(list=objects())
library("tidyverse")
library("raster")
library("sf")
library("guido")
library("vroom")
library("DBI")

options(warn = 2)

dbConnect(RSQLite::SQLite(),"pm10_maps.sqlite")->mydb

creaCalendario(2012,2020) %>%
  mutate(yymmdd=as.Date(glue::glue("{yy}-{mm}-{dd}"))) %>%
  filter(yymmdd >= as.Date("2012-12-25"))->calendario

nrow(calendario)->numeroGiorni

#dati di pm10
read_delim("dati_pm10_2012_2020.csv",delim=";",col_names = TRUE)->dati_pm10

#anagrafica
read_delim("ana.csv",delim=";",col_names = TRUE)->ana

unique(dati_pm10$station_eu_code)->codiciStazioni


ana %>%
  filter(station_eu_code %in% codiciStazioni)->subAna

st_as_sf(subAna,coords=c("st_x","st_y"),crs=4326)->punti



list.files(pattern="^.+nc$")->file_nc


estrai<-function(.nomeFile,.x){
  
  brick(.nomeFile)->mygrid
  
  parametro<-str_remove(str_remove(.nomeFile,"^new_"),"2012_2020.nc")

  if(numeroGiorni!=nlayers(mygrid)) browser()
  raster::extract(mygrid,punti,df=FALSE)->valoriPuntuali
  bind_cols(subAna[,c("station_eu_code")],as_tibble(valoriPuntuali))->mydf
  
  
  mydf %>%
    gather(key="yymmdd",value="value",-station_eu_code) %>%
    spread(key=station_eu_code,value=value) %>%
    mutate(yymmdd=str_remove(yymmdd,"^X")) %>%
    separate(yymmdd,into=c("yy","mm","dd"),sep="\\.",extra = "drop") %>% #importaaante drop perche' in alcuni casi i layers del brick riportano anche l'ora
    mutate(yy=as.integer(yy),mm=as.integer(mm),dd=as.integer(dd))->finale
  
    dbWriteTable(mydb,parametro,finale)
  
    vroom::vroom_write(finale,file = glue::glue("{parametro}_2012_2020.csv"),delim=";",col_names = TRUE)
  
}



purrr::walk(file_nc,.f=~(estrai(.,.x=subAna)))

dbDisconnect(mydb)
