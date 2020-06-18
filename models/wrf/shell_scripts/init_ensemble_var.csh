#!/bin/csh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id$

# init_ensemble_var.csh - script that creates perturbed initial
#                         conditions from the WRF-VAR system.
#                         (perts are drawn from the perturbation bank)
#
# created Nov. 2007, Ryan Torn NCAR/MMM
# modified by G. Romine 2011-2018
### Cleaned up by Michael Ying 2019

set initial_date = ${1}
set paramfile    = ${2}
source $paramfile

## get dates
cd ${TEMPLATE_DIR}
set gdate  = (`echo $initial_date 0h -g | ${DART_DIR}/models/wrf/work/advance_time`)
set gdatef = (`echo $initial_date ${ASSIM_INT_HOURS}h -g | ${DART_DIR}/models/wrf/work/advance_time`)
set wdate  =  `echo $initial_date 0h -w | ${DART_DIR}/models/wrf/work/advance_time`
set yyyy   = `echo $initial_date | cut -b1-4`
set mm     = `echo $initial_date | cut -b5-6`
set dd     = `echo $initial_date | cut -b7-8`
set hh     = `echo $initial_date | cut -b9-10`

mkdir -p $RUN_DIR
cd $RUN_DIR

${REMOVE} ${RUN_DIR}/WRF
${LINK} ${OUTPUT_DIR}/${initial_date} WRF

set n = 1
while ( $n <= $NUM_ENS )

  echo "  STARTING ENSEMBLE MEMBER $n"

  set ensstring = `echo $n + 10000 | bc | cut -c2-5`
  mkdir -p ${RUN_DIR}/advance_temp${n}
  cd ${RUN_DIR}/advance_temp${n}

  ${LINK} ${WRF_SRC_DIR}/run/* .
  ${LINK} ${TEMPLATE_DIR}/input.nml input.nml

  ${COPY} ${OUTPUT_DIR}/${initial_date}/wrfinput_d01_${gdate[1]}_${gdate[2]}_mean wrfvar_output.nc

  ### perturb initial conditions using pert_bank
  sleep 3
  ${REMOVE} nclrun3.out
  cat >! nclrun3.out << EOF
ncl 'NUM_PERT=${NUM_PERT}' 'PERT_BANK="${PERT_BANK_DIR}"' ${SHELL_SCRIPTS_DIR}/add_bank_perts.ncl
EOF

  ### generate run script for each member
  if ( -e first_adv_${n}.csh )  ${REMOVE} first_adv_${n}.csh
  touch first_adv_${n}.csh

  ##job_submit script header
  if ( $SUPER_PLATFORM == 'cheyenne' ) then
    cat >> first_adv_${n}.csh << EOF
#!/bin/csh
#PBS -N first_adv_${n}
#PBS -j oe
#PBS -A ${CNCAR_GAU_ACCOUNT}
#PBS -l walltime=${CADVANCE_TIME}
#PBS -q ${CADVANCE_QUEUE}
#PBS -l select=${CADVANCE_NODES}:ncpus=${CADVANCE_PROCS}:mpiprocs=${CADVANCE_MPI}
module load ncl/6.6.2
EOF
  endif

  ###job_submit script execute commands
  cat >> first_adv_${n}.csh << EOF
cd ${RUN_DIR}/advance_temp${n}
chmod +x nclrun3.out
./nclrun3.out >& add_perts.out
${MOVE} wrfvar_output.nc wrfinput_d01
cd $RUN_DIR
${SHELL_SCRIPTS_DIR}/first_advance.csh $initial_date $n ${SHELL_SCRIPTS_DIR}/$paramfile
EOF

  ${JOB_SUBMIT} first_adv_${n}.csh

  @ n++

end

exit 0

# <next few lines under version control, do not edit>
# $URL$
# $Revision$
# $Date$
