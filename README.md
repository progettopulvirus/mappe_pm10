# Mappe PM10

Codici per la realizzazione delle mappe del PM10 per il periodo 2023-2020,

## Python

Script python per scaricare i netCDF da Copernicus.

## CDO

Scipt per elaborare i file netCDF scaricati da Copernicus.

---

## Dati meteo

I dati meteo 2021-2020 sono stati acquisiti da Copernicus mediante script in python.

## AOD550

Per l'AOD la fonte sono le rianalisi di [Copernicus](https://www.copernicus.eu/en/copernicus-services/atmosphere). Il dataset è il "Total Aerosolo Optical Depth" 550.

I dati di AOD sono stati reinterpolati su grigliato latlon regolare mediante `CDO` (usando `remapbil`) dopo aver predisposto un file di testo `grid.txt` contenente la descrizione della griglia target contenente le seguenti informazioni:

```
gridtype=lonlat
gridsize=18271
xsize=121
ysize=151
xfirst=5.00
xinc=0.25
yfirst=36
yinc=0.25
```
Per una reinterpolazione bilineare usare:

```
cdo sellonlatbox,5,20,36,48 -remapbil,grid.txt file_input.nc  file_output.nc
```

La descrizione del grigliato di output puo' essere acquisito dai file netCDF estratti da Copernicus Land (che sono già in formato latlon regolare) utilizzando (ad esempio) il pacchetto `raster` di `R`.
 
 
 **Attenzione: il file .cdsapirc necessario per scaricare i dati AOD va modificato rispetto a quello utilizzato per Copernicus Land, ovvero va cambiato l'url e l'API key.**
 
 **Per l'AOD lo script python si blocca a causa di un qualche errore che non si e' riusciti a risolvere. I dati sono quindi stati scaricati direttamente tramite interfaccia web.**

