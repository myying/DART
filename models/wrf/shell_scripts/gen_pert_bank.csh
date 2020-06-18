#!/bin/csh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id$

# utility to save a set of perturbations generated from WRFDA CV3 option
#
### Cleaned up by Michael Ying 2019

set datea = ${1} #initial date
set paramfile = ${2}
source $paramfile

module load nco

cd ${TEMPLATE_DIR}
set gdate  = (`echo $datea 0h -g | ${DART_DIR}/models/wrf/work/advance_time`)
set gdatef = (`echo $datea ${ASSIM_INT_HOURS}h -g | ${DART_DIR}/models/wrf/work/advance_time`)
set wdate  =  `echo $datea 0h -w | ${DART_DIR}/models/wrf/work/advance_time`
set yyyy   = `echo $datea | cut -b1-4`
set mm     = `echo $datea | cut -b5-6`
set dd     = `echo $datea | cut -b7-8`
set hh     = `echo $datea | cut -b9-10`

mkdir -p ${PERT_BANK_DIR}
cd ${PERT_BANK_DIR}

set n = 1
while ( $n <= $NUM_PERT )

  mkdir -p ${PERT_BANK_DIR}/mem_${n}
  cd ${PERT_BANK_DIR}/mem_${n}

  $LINK ${VAR_SRC_DIR}/var/build/da_wrfvar.exe .
  $LINK ${WRF_SRC_DIR}/run/* .

  ##background error covariance: use CV3 option
  $LINK ${VAR_SRC_DIR}/var/run/be.dat.cv3 be.dat

  ${LINK} ${OUTPUT_DIR}/${datea}/wrfinput_d01_${gdate[1]}_${gdate[2]}_mean fg

  ## prep the namelist to run wrfvar
  $REMOVE namelist.*
  @ seed_array2 = $n * 10
  cat >! script.sed << EOF
   /run_hours/c\
   run_hours                  = 0,
   /run_minutes/c\
   run_minutes                = 0,
   /run_seconds/c\
   run_seconds                = 0,
   /start_year/c\
   start_year                 = 1*${yyyy},
   /start_month/c\
   start_month                = 1*${mm},
   /start_day/c\
   start_day                  = 1*${dd},
   /start_hour/c\
   start_hour                 = 1*${hh},
   /start_minute/c\
   start_minute               = 1*00,
   /start_second/c\
   start_second               = 1*00,
   /end_year/c\
   end_year                   = 1*${yyyy},
   /end_month/c\
   end_month                  = 1*${mm},
   /end_day/c\
   end_day                    = 1*${dd},
   /end_hour/c\
   end_hour                   = 1*${hh},
   /end_minute/c\
   end_minute                 = 1*00,
   /end_second/c\
   end_second                 = 1*00,
   /analysis_date/c\
   analysis_date = \'${wdate}.0000\',
   /seed_array1/c\
   seed_array1 = ${datea},
   /seed_array2/c\
   seed_array2 = $seed_array2 /
EOF
  sed -f script.sed ${TEMPLATE_DIR}/namelist.input.3dvar >! namelist.input

  ### make a run file for wrfvar
  $REMOVE gen_pert_${n}.csh

  ##job_submit script header
  if ( $SUPER_PLATFORM == 'cheyenne' ) then
    cat >> gen_pert_${n}.csh << EOF
#!/bin/csh
#PBS -N gen_pert_${n}
#PBS -j oe
#PBS -A ${CNCAR_GAU_ACCOUNT}
#PBS -q ${CFILTER_QUEUE}
#PBS -l select=${CFILTER_NODES}:ncpus=${CFILTER_PROCS}:mpiprocs=${CFILTER_MPI}
#PBS -l walltime=${CFILTER_TIME}
EOF
  endif

  ##job_submit script execution commands
  cat >> gen_pert_${n}.csh << EOF
cd ${PERT_BANK_DIR}/mem_${n}
${MPIRUN} ./da_wrfvar.exe >& output.wrfvar
mv wrfvar_output wrfinput_d01
# extract only the fields that are updated by wrfvar, then diff to generate the pert file for this member
ncks -h -F -A -a -v U,V,T,QVAPOR,MU fg orig_data.nc
ncks -h -F -A -a -v U,V,T,QVAPOR,MU wrfinput_d01 pert_data.nc
ncdiff pert_data.nc orig_data.nc pert_bank_mem_${n}.nc
mv pert_bank_mem_${n}.nc ${PERT_BANK_DIR}/pert_bank_mem_${n}.nc
rm orig_data.nc pert_data.nc wrfinput_d01
EOF

  echo "running 3DVar to perturb wrfinput for member ${n}"
  ${JOB_SUBMIT} gen_pert_${n}.csh

  @ n++
end

# currently the script exits, but it could sleep and do cleanup once all the forecasts are complete.
exit(0)

# <next few lines under version control, do not edit>
# $URL$
# $Revision$
# $Date$
