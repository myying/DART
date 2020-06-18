#!/bin/csh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id$

########################################################################
#
#   generate_wrfinput_bdy_files.csh - shell script that generates the
#                                     necessary wrfinput_d01 and
#                                     wrfbdy_d01 files for running
#                                     a real-time analysis system.
#
#     created May 2009, Ryan Torn, U. Albany
#
#####Cleaned up by Michael Ying 2019
########################################################################

########################################################################
set datea     = $1  ##start and end dates
set datefnl   = $2
set paramfile = $3
source $paramfile

mkdir -p $ICBC_DIR
cd $ICBC_DIR

ln -fs ${TEMPLATE_DIR}/input.nml .  ###must have this for advance_time to work

##run geogrid.exe
echo "generating geo_em files"
cp ${TEMPLATE_DIR}/namelist.wps .
mkdir -p $ICBC_DIR/geogrid
${LINK} ${WPS_SRC_DIR}/geogrid/GEOGRID.TBL.ARW $ICBC_DIR/geogrid/GEOGRID.TBL
${REMOVE} output.geogrid
#${WPS_SRC_DIR}/geogrid.exe >& output.geogrid

while ( 1 == 1 )
  echo "generating wrfinput bdy files for $datea"

  if ( ! -d ${OUTPUT_DIR}/${datea} )  mkdir -p ${OUTPUT_DIR}/${datea}

  set start_date = `echo $datea 0 -w | ${DART_DIR}/models/wrf/work/advance_time`
  set end_date   = `echo $datea 6 -w | ${DART_DIR}/models/wrf/work/advance_time`
  echo $start_date

  ## generate namelist.wps
  ${REMOVE} script.sed
  ${REMOVE} namelist.wps
  cat >! script.sed << EOF
 /start_date/c\
 start_date = ${NUM_DOMAINS}*'${start_date}',
 /end_date/c\
 end_date   = ${NUM_DOMAINS}*'${end_date}',
EOF
  sed -f script.sed ${TEMPLATE_DIR}/namelist.wps >! namelist.wps

  ## build grib file names - may need to change for other data sources. These are from RDA
  set gribfile_a = ${GRIB_DATA_DIR}/gdas1.fnl0p25.${datea}.f00.grib2
  set gribfile_b = ${GRIB_DATA_DIR}/gdas1.fnl0p25.${datea}.f06.grib2
  ${LINK} $gribfile_a GRIBFILE.AAA
  ${LINK} $gribfile_b GRIBFILE.AAB
  ${LINK} ${WPS_SRC_DIR}/ungrib/Variable_Tables/Vtable.${GRIB_SRC} Vtable
  ## run ungrib.exe
  ${REMOVE} output.ungrib
  ${WPS_SRC_DIR}/ungrib.exe >& output.ungrib

  ## run metgrid.exe
  mkdir -p $ICBC_DIR/metgrid
  ${LINK} ${WPS_SRC_DIR}/metgrid/METGRID.TBL $ICBC_DIR/metgrid/METGRID.TBL
  ${REMOVE} output.metgrid
  ${WPS_SRC_DIR}/metgrid.exe >& output.metgrid

  set datef  =  `echo $datea $ASSIM_INT_HOURS | ${DART_DIR}/models/wrf/work/advance_time`
  set gdatef = (`echo $datef 0 -g             | ${DART_DIR}/models/wrf/work/advance_time`)
  set hh     =  `echo $datea | cut -b9-10`

  #  Run real.exe twice, once to get first time wrfinput_d0? and wrfbdy_d01,
  #  then again to get second time wrfinput_d0? file
  set n = 1
  while ( $n <= 2 )
    echo "RUNNING REAL, STEP $n"

    if ( $n == 1 ) then
      set date1      = $datea
      set date2      = $datef
      set fcst_hours = $ASSIM_INT_HOURS
    else
      set date1      = $datef
      set date2      = $datef
      set fcst_hours = 0
    endif

    set yyyy1 = `echo $date1 | cut -c 1-4`
    set mm1   = `echo $date1 | cut -c 5-6`
    set dd1   = `echo $date1 | cut -c 7-8`
    set hh1   = `echo $date1 | cut -c 9-10`
    set yyyy2 = `echo $date2 | cut -c 1-4`
    set mm2   = `echo $date2 | cut -c 5-6`
    set dd2   = `echo $date2 | cut -c 7-8`
    set hh2   = `echo $date2 | cut -c 9-10`

    ${REMOVE} namelist.input script.sed
    cat >! script.sed << EOF
    /run_hours/c\
    run_hours                  = ${fcst_hours},
    /run_minutes/c\
    run_minutes                = 0,
    /run_seconds/c\
    run_seconds                = 0,
    /start_year/c\
    start_year                 = ${yyyy1}, ${yyyy1}, ${yyyy1}, ${yyyy1},
    /start_month/c\
    start_month                = ${mm1}, ${mm1}, ${mm1}, ${mm1},
    /start_day/c\
    start_day                  = ${dd1}, ${dd1}, ${dd1}, ${dd1},
    /start_hour/c\
    start_hour                 = ${hh1}, ${hh1}, ${hh1}, ${hh1},
    /start_minute/c\
    start_minute               = 00, 00, 00, 00,
    /start_second/c\
    start_second               = 00, 00, 00, 00,
    /end_year/c\
    end_year                   = ${yyyy2}, ${yyyy2}, ${yyyy2}, ${yyyy2},
    /end_month/c\
    end_month                  = ${mm2}, ${mm2}, ${mm2}, ${mm2},
    /end_day/c\
    end_day                    = ${dd2}, ${dd2}, ${dd2}, ${dd2},
    /end_hour/c\
    end_hour                   = ${hh2}, ${hh2}, ${hh2}, ${hh2},
    /end_minute/c\
    end_minute                 = 00, 00, 00, 00,
    /end_second/c\
    end_second                 = 00, 00, 00, 00,
EOF

    sed -f script.sed ${TEMPLATE_DIR}/namelist.input >! namelist.input
    ${REMOVE} output.real
    ${WRF_SERIAL_SRC_DIR}/run/real.exe >& output.real
    if ( -e rsl.out.0000 )  cat rsl.out.0000 >> output.real

    #  move output files to storage
    set gdate = (`echo $date1 0 -g | ${DART_DIR}/models/wrf/work/advance_time`)
    set dn = 1
    while ( $dn <= ${NUM_DOMAINS} )
      set dchar = `echo $dn + 100 | bc | cut -b2-3`
      ${MOVE} wrfinput_d${dchar} ${OUTPUT_DIR}/${datea}/wrfinput_d${dchar}_${gdate[1]}_${gdate[2]}_mean
      @ dn++
    end
    if ( $n == 1 ) ${MOVE} wrfbdy_d01 ${OUTPUT_DIR}/${datea}/wrfbdy_d01_${gdatef[1]}_${gdatef[2]}_mean

    @ n++

  end

  # move to next time, or exit if final time is reached
  if ( $datea == $datefnl) then
    echo "Reached the final date "
    echo "Script exiting normally"
    exit
  endif
  set datea  = `echo $datea $ASSIM_INT_HOURS | ${DART_DIR}/models/wrf/work/advance_time`
  echo "starting next time: $datea"
end

exit 0

# <next few lines under version control, do not edit>
# $URL$
# $Revision$
# $Date$
