#!/bin/bash

#5 novembre 2021

#questo script utilizza i netCDF 2012-2018 ritagliati sul box 5,20,36,48 scaricati mediante script python da copernicus (ERA5-single-level per PBL, ERA5-Land per gli altri parametri). In ogni caso a cdo viene passato il comando sellonlatbox per ritagliare il netCDF sul box suddetto.

#I grigliati sono già regolari secondo la documentazione di copernicus, quindi non vanno riproiettati.

#mergetime: vengono uniti i netCDF di input rispetto al tempo. Attenzione: i netCDF devono contenere una sola variabile!

#seldate: viene selezionato il periodo che va dal 25 dicembre di "primoAnno". E' fondamentale partire da qualche giorno antecedente il 1 gennaio di "ultimoAnno"  perche' 
#il modello INLA include una componente autoregressiva AR1 (per fare le mappe basterebbe prendere il 31 dicembre di primoAnno).

#operazione: se il parametro di interesse e' la precipitazione bisogna calcolare il totale giornaliero, altrimenti la media. Per il pbl viene applicata la media, ma poiche'
#il pbl00 e' il pbl alle 00.00 e il pbl12 e' il pbl alle 12.00 e' indifferente l'operazione applicata (daysum o daymean).

#ptotal_precipitation la calcoliamo dalla precipitazione totale già aggregata usando il comando cdo "shifttime"



#parametri=( "temperatura" "total_precipitation" "surface_pressure" "pbl00" "pbl12" )
parametri=( "total_precipitation" )

primoAnno="2012"
ultimoAnno="2020"

#costante viene sommata ai parametri. Sommiamo 0 a tutti i parametri, sommiamo -273.15 per la temperatura per passare da gradi Kelvin a gradi Centigradi


for par in ${parametri[@]};do

	#le costanti da sommare e moltiplicare devono andare all'interno del ciclo for!!!

	#questa variabile serve per la temperatura
	add_costante=0

	#questa variabile serve per la surface pressure..vogliamo passare dai pascal agli hPa
	mul_costante=1

	echo "############################"	
	echo "### elaboro parametro ${par}"
	echo "############################"

	if [[ ${par} == *total_precipitation ]]; then 

	operazione="daysum"

	else

	operazione="daymean"

	fi


	#per la temperatura dobbiamo passare dai gradi Kelvin ai gradi centigradi (anche se non sarebbe necessario)

	if [[ ${par} == "temperatura" ]];then

		add_costante="-273.15"
	
	fi

	#la surface_pressure e' in pascal
	if [[ ${par} == "surface_pressure" ]];then

		mul_costante=0.01

	fi

	echo "############################"
	echo "costante da sommare: ${add_costante}"
	echo "costante da moltiplicare: ${mul_costante}"
	echo "############################"

	cdo -O -b F32 -mulc,${mul_costante} -addc,${add_costante} -${operazione} -seldate,${primoAnno}-12-25,${ultimoAnno}-12-31 -sellonlatbox,5,20,36,48 ${par}${primoAnno}_${ultimoAnno}.nc new_${par}${primoAnno}_${ultimoAnno}.nc


	#qui creo ptotal_precipitation
	if [[ ${par} == "total_precipitation" ]];then

		#con cdo sposto di un giorno l'asse temporale e creo un file di output che si chiama ptotal_precipitation
		cdo shifttime,1day new_${par}${primoAnno}_${ultimoAnno}.nc new_p${par}${primoAnno}_${ultimoAnno}.nc

	fi

	

done
