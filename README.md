# Mappe PM10

Questo repository contiene:

- i codici per la realizzazione delle mappe del PM10 per il periodo 2013-2020
- i dati di PM10 2013-2020

## Database

I dati di input puntuali (corrispondenti alle centraline di monitoraggio) di PM10 e dei regressori spazio-temporali sono stati organizzati in un database sqlite utilizzando il pacchetto R `RSQLite`.

## Python

Script python per scaricare i netCDF da Copernicus.

## CDO

Scipt per elaborare i file netCDF scaricati da Copernicus.

---

## DATI PM10

Dati delle centraline di monitoraggio dal 2013 al 2020.

## Dati meteo

I dati meteo 2012-2020 sono stati acquisiti da Copernicus mediante script in python. I dati sono stati estratti dal 2012 in quanto per ogni anno target X (ad esempio il 2020) abbiamo bisogno del 31 dicembre dell'anno antecedente a X in modo di poter generare la mappa del primo gennaio dell'anno X (il modello contiene una componente AR1).

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

