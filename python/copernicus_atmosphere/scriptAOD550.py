#!/usr/bin/python3
import cdsapi

c = cdsapi.Client()

c.retrieve(
    'cams-global-reanalysis-eac4',
    {
        'format': 'netcdf',
        'variable': 'total_aerosol_optical_depth_550nm',
        'date': '2012-01-01/2020-12-31',
        'time': [
            '00:00', '03:00', '06:00',
            '09:00', '12:00', '15:00',
            '18:00', '21:00',
        ],
        'area': [
            48, 5, 36,
            20,
        ],
    },
    'aod550.nc')
