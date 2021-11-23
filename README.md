 # Mappe PM10

Questo repository contiene:

- i codici per la realizzazione delle mappe del PM10 per il periodo 2013-2020
- i dati di PM10 2013-2020

#### TO DO

23 novembre: rivedere il metodo di standardizzazione delle covariate. Quello attuale prevede il calcolo di media e sd anno per anno. Questao significa che la standardizzazione dei rasters deve essere ripetuta con parametri differenti quando si creano le mappe finali. Questa soluzione e' troppo onerosa dal puntop di vista computazionale. **Soluzione:** calcolare una sola media e una sola sd su tutto il periodo 2012-2020 con cui standardizzare una sola volta tutti i rasters.



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


## Dati DUST

I dati (file netCDF 2013-2020) sono stati scaricati da Giorgio. I file contengono due variabili. Quella di interesse e' `sconc_dust` che va moltiplicata per 10^9.
Si tratta di forecast, per cui uno stesso dato e' presente in piu' file (ad esempio il file del primo settembre contiene le previsioni del dust fino al 4 settembre, il file del 2 settembre contiene le previsioni fino al 5 etc etc.). Per ovviare al problema dei timestamps ripetuti va utilizzata la variabile SKIP_SAME_TIME. Ovvero:

```
export SKIP_SAME_TIME=1
cdo mergetime input.nc output.nc
```

**ATTENZIONE: i file di settembre 2020 hanno dei problemi con la griglia e con giorni mancanti (dal 26 al 28 settembre). Il problema della griglia viene risolto facendo prima di `mergetime` un `-sellonlatbox -remapbil,grid.txt`. Il problema dei giorni mancanti è stato risolto prendendo il file di un giorno qualsiasi, settando il time axis (`settimeaxis`) e imponendo che il valore della variabile sconc_dust sia ugaule a zero nell'area di interesse `setclonlatbox,0,5,20,36,48`. In altri temini si è assunto che per i giorni mancanti non si verifichino eventi di dust.**

File netCDF dust, dati mancanti:

- settembre 2020 ha problemi con la dimensione della griglia e con i giorni mancanti dal 26 al 28
- febbraio 2014 mancano i giorni dal 24 al 28 febbraio
- 2019 mancano i giorni dal 10 al 17 febbraio, dal 4 al 30 settembre, dal 7 al 18 novembre
- 2017 mancano i giorni dal 14 al 20 settembre

Esempio di creazione di giorni di riempimento:

```
cdo -setclonlatbox,0,5,20,36,48 -settaxis,2017-09-14,00:00:00,1day -seldate,2017-01-01,2017-01-05 input.nc output.nc
```

Nel comando sopra vengo presi i giorni dal 1 al 5 gennaio del file input.nc; i giorni vengono fatti partie dal 14 settembre 2017 e i valori messi a 0 all'interno dell'area del Mediterraneo. Il file output.nc quindi puo' essere unito mediante `mergetime` al file con tutti i giorni per il 2017.

