#!/bin/csh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id$


#   driver.csh - script that is the driver for the
#                            CONUS analysis system
#                            MODIFIED for new DART direct
#                            file access
#
#      provide an input argument of the first
#      analysis time in yyyymmddhh format.
#
#   Created May 2009, Ryan Torn, U. Albany
#   Modified by G. Romine to run realtime cases 2011-18
#
########################################################################
#   run as: nohup csh driver.csh 2017042706 >& run.log &
########################################################################
#### Cleaned up and modified by Michael Ying 2019
set datea = $1
set datefnl = $2
set paramfile = $3
source $paramfile
module load nco

setenv restore 1   # set the restore variable
echo 'starting a restore'

while ( 1 == 1 ) ##outermost loop

  ${REMOVE} ${RUN_DIR}/ABORT_RETRO
  if ( ! -d ${OUTPUT_DIR}/${datea} && $restore == 1 ) then
     echo 'exiting because output directory does not exist and this is a restore'
     exit
  endif

  cd ${TEMPLATE_DIR}
  set datep  = `echo $datea -${ASSIM_INT_HOURS}   | ${DART_DIR}/models/wrf/work/advance_time`
  set gdate  = `echo $datea 0 -g                  | ${DART_DIR}/models/wrf/work/advance_time`
  set gdatef = `echo $datea ${ASSIM_INT_HOURS} -g | ${DART_DIR}/models/wrf/work/advance_time`
  set wdate  = `echo $datea 0 -w                  | ${DART_DIR}/models/wrf/work/advance_time`
  set hh     = `echo $datea | cut -b9-10`

  mkdir -p $RUN_DIR
  cd $RUN_DIR

  echo 'ready to check inputs'
  set domains = ${NUM_DOMAINS}   # from the param file
  ###  Check to make sure all input data exists
  if  ( $domains == 1 ) then
    foreach infile ( wrfinput_d01_${gdate[1]}_${gdate[2]}_mean wrfinput_d01_${gdatef[1]}_${gdatef[2]}_mean \
                     wrfbdy_d01_${gdatef[1]}_${gdatef[2]}_mean obs_seq.out )
      if ( ! -e ${OUTPUT_DIR}/${datea}/${infile} ) then
        echo "${OUTPUT_DIR}/${datea}/${infile} is missing!  Stopping the system"
        touch ABORT_RETRO
        exit
      endif
    end
  endif

  #  Clear the advance_temp directory, write in new template file, and overwrite variables with the
  #  compact prior netcdf files
  #  NOTE that multiple domains might be present, but only looking for domain 1
  set dn = 1
  while ( $dn <= $domains )   ### loop through domains
    set dchar = `echo $dn + 100 | bc | cut -b2-3`
    set n = 1
    while ( $n <= $NUM_ENS )  ### loop through ensemble members
      set ensstring = `echo $n + 10000 | bc | cut -b2-5`
      if ( -e ${OUTPUT_DIR}/${datep}/PRIORS/prior_d${dchar}.${ensstring} ) then
        if ( $dn == 1 &&  -d ${RUN_DIR}/advance_temp${n} )  ${REMOVE} ${RUN_DIR}/advance_temp${n}
        mkdir -p ${RUN_DIR}/advance_temp${n}
        ${LINK} ${OUTPUT_DIR}/${datea}/wrfinput_d${dchar}_${gdate[1]}_${gdate[2]}_mean ${RUN_DIR}/advance_temp${n}/wrfinput_d${dchar}
      else
        echo "${OUTPUT_DIR}/${datep}/PRIORS/prior_d${dchar}.${ensstring} is missing! Stopping the system"
        touch ABORT_RETRO
        exit
      endif
      @ n++
    end  ### loop through ensemble members
    @ dn++
  end   ### loop through domains

  #if ( $SUPER_PLATFORM == 'cheyenne' ) then
  #  set ic_queue = "regular"
  #  set sub_command = "${JOB_SUBMIT} -l select=1:ncpus=2:mpiprocs=36:mem=5GB -l walltime=00:03:00 -q ${ic_queue} -A ${CNCAR_GAU_ACCOUNT} -j oe -N icgen "
  #endif
  #echo "this platform is $SUPER_PLATFORM and the job submission command is $sub_command"
  set n = 1
  set dn = 1
  while ( $n <= $NUM_ENS )  ### loop through ensemble members
    #if ( $SUPER_PLATFORM == 'cheyenne' ) then   # can't pass along arguments in the same way
      #$sub_command -v mem_num=${n},date=${datep},domain=${domains} ${SHELL_SCRIPTS_DIR}/prep_ic.csh
    ###Michael Ying: nothing in prep_ic.csh is parallel, just run directly
    #echo "prep_ic for member $n"
    ${SHELL_SCRIPTS_DIR}/prep_ic.csh ${n} ${datep} ${dn} ${SHELL_SCRIPTS_DIR}/$paramfile
    @ n++
  end  ### loop through ensemble members

  ### cleanup any failed stuffs
  set dn = 1
  while ( $dn <= $domains )  ###loop through domains
    set dchar = `echo $dn + 100 | bc | cut -b2-3`
    set n = 1
    set loop = 1
    while ( $n <= $NUM_ENS )
      if ( -e ${RUN_DIR}/ic_d${dchar}_${n}_ready) then
        ${REMOVE} ${RUN_DIR}/ic_d${dchar}_${n}_ready
        @ n++
        set loop = 1
      else
        echo "waiting for ic member $n in domain $dn"
        sleep 5
        @ loop++
        if ( $loop > 60 ) then    # wait 5 minutes for the ic file to be ready, else run manually
          echo "gave up on ic member $n - redo"
          ${SHELL_SCRIPTS_DIR}/prep_ic.csh ${n} ${datep} ${dn} ${SHELL_SCRIPTS_DIR}/$paramfile
        endif
      endif
    end
    @ dn++
  end   ### loop through domains

  #mkdir ${OUTPUT_DIR}/${datea}/logs
  #${MOVE}  icgen.o* ${OUTPUT_DIR}/${datea}/logs/

  ###  Get wrfinput source information
  ${COPY} ${OUTPUT_DIR}/${datea}/wrfinput_d01_${gdate[1]}_${gdate[2]}_mean wrfinput_d01
  set dn = 1
  while ( $dn <= $domains )
    set dchar = `echo $dn + 100 | bc | cut -b2-3`
    ${COPY} ${OUTPUT_DIR}/${datea}/wrfinput_d${dchar}_${gdate[1]}_${gdate[2]}_mean wrfinput_d${dchar}
    @ dn++
  end

  ### some support files for filter
  ${LINK} ${DART_DIR}/assimilation_code/programs/gen_sampling_err_table/work/sampling_error_correction_table.nc ${RUN_DIR}/.

  set input_file_name  = "input_list_d01.txt"
  set input_file_path  = "./advance_temp"
  set output_file_name = "output_list_d01.txt"
  set n = 1
  if ( -e $input_file_name )  rm $input_file_name
  if ( -e $output_file_name ) rm $output_file_name
  while ($n <= $NUM_ENS)
    set ensstring = `printf %04d $n`
    set in_file_name = ${input_file_path}${n}"/wrfinput_d01"
    set out_file_name = "filter_restart_d01."$ensstring
    echo $in_file_name  >> $input_file_name
    echo $out_file_name >> $output_file_name
    @ n++
  end

  ###  Copy the inflation files from the previous time, update for domains
  if ( $ADAPTIVE_INFLATION == 1 ) then
     mkdir -p ${RUN_DIR}/{Inflation_input,Output}  # home for inflation and future state space diag files
     ### Should try to check each file here, but shortcutting for prior (most common) and link them all
     if ( $domains == 1) then
       if ( -e ${OUTPUT_DIR}/${datep}/Inflation_input/input_priorinf_mean.nc ) then
         ${LINK} ${OUTPUT_DIR}/${datep}/Inflation_input/input_priorinf*.nc ${RUN_DIR}/.
         ${LINK} ${OUTPUT_DIR}/${datep}/Inflation_input/input_postinf*.nc ${RUN_DIR}/.
       else
         echo "${OUTPUT_DIR}/${datep}/Inflation_input/input_priorinf_mean.nc files do not exist.  Stopping"
         touch ABORT_RETRO
         exit
       endif
     else    # multiple domains so multiple inflation files for each domain
       echo "This script doesn't support multiple domains.  Stopping"
       touch ABORT_RETRO
       exit
     endif # number of domains check
  endif   # ADAPTIVE_INFLATION file check

  ${LINK} ${OUTPUT_DIR}/${datea}/obs_seq.out .
  ${REMOVE} ${RUN_DIR}/WRF
  ${REMOVE} ${RUN_DIR}/prev_cycle_done
  ${LINK} ${OUTPUT_DIR}/${datea} ${RUN_DIR}/WRF

  #####  run filter to generate the analysis
  ### generate run script for filter
  if ( -e assimilate.csh )  ${REMOVE} assimilate.csh
  touch assimilate.csh

  ##job_submit script header
  if ( $SUPER_PLATFORM == 'cheyenne' ) then
    cat >> assimilate.csh << EOF
#!/bin/csh
#PBS -N assimilate_${datea}
#PBS -j oe
#PBS -A ${CNCAR_GAU_ACCOUNT}
#PBS -l walltime=${CFILTER_TIME}
#PBS -q ${CFILTER_QUEUE}
#PBS -l select=${CFILTER_NODES}:ncpus=${CFILTER_PROCS}:mpiprocs=${CFILTER_MPI}
EOF
  endif

  ##job_submit script execution commands
  cat >> assimilate.csh << EOF
cd ${RUN_DIR}
${MPIRUN} ${DART_DIR}/models/wrf/work/filter
if ( -e ${RUN_DIR}/obs_seq.final ) touch ${RUN_DIR}/filter_done
EOF

  echo "running filter"
  ${JOB_SUBMIT} assimilate.csh

  cd $RUN_DIR   # make sure we are still in the right place

  while ( ! -e filter_done )
    # Check the timing.  If it took longer than the time allocated, abort.
    if ( -e filter_started ) then
      set start_time = `head -1 filter_started`
      set end_time = `date +%s`
      @ total_time = $end_time - $start_time
      if ( $total_time > ${TIMEOUT} ) then
        echo "Time exceeded the maximum allowable time.  Exiting."
        touch ABORT_RETRO
        ${REMOVE} filter_started
        exit
      endif
    endif
    sleep 10
  end

  ### filter is done, so clean up
  echo "cleanup"
  #${MOVE}  icgen.o* ${OUTPUT_DIR}/${datea}/logs/
  ${REMOVE} ${RUN_DIR}/filter_started ${RUN_DIR}/filter_done 
  #${REMOVE} ${RUN_DIR}/obs_seq.out ${RUN_DIR}/postassim_priorinf* ${RUN_DIR}/preassim_priorinf*
  #if ( -e assimilate.csh )  ${REMOVE} ${RUN_DIR}/assimilate.csh

  #echo "Listing contents of rundir before archiving at "`date`
  #ls -l *.nc blown* dart_log* filter_* input.nml obs_seq* Output/inf_ic* 
  mkdir -p ${OUTPUT_DIR}/${datea}/{Inflation_input,WRFIN,PRIORS,logs}

  set num_vars = $#increment_vars_a
  set extract_str = ''
  set i = 1
  while ( $i <= $num_vars )
    set extract_str = `echo ${extract_str}$increment_vars_a[$i],`
    @ i++
  end
  set extract_str = `echo ${extract_str}$increment_vars_a[$num_vars]`

  ### analysis increment
  ncdiff -F -O -v $extract_str postassim_mean.nc preassim_mean.nc analysis_increment.nc
  ncks -F -O -x -v ${extract_str} postassim_mean.nc static_data.nc
  ncks -A static_data.nc analysis_increment.nc

  ###  Move diagnostic and obs_seq.final data to storage directories
  foreach FILE ( postassim_mean.nc preassim_mean.nc postassim_sd.nc preassim_sd.nc obs_seq.final analysis_increment.nc output_mean.nc output_sd.nc )
    if ( -e $FILE && ! -z $FILE ) then
      ${MOVE} $FILE ${OUTPUT_DIR}/${datea}/.
      if ( ! $status == 0 ) then
        echo "failed moving ${RUN_DIR}/${FILE}"
        touch BOMBED
      endif
    else
      echo "${OUTPUT_DIR}/${FILE} does not exist and should."
      #ls -l
      touch BOMBED
    endif
  end

  echo "past the analysis file moves"

  #  Move inflation files to storage directories
  cd ${RUN_DIR}
  # Different file names with multiple domains
  if ( $ADAPTIVE_INFLATION == 1 ) then
    set old_file = ( input_postinf_mean.nc  input_postinf_sd.nc  input_priorinf_mean.nc  input_priorinf_sd.nc )
    set new_file = ( output_postinf_mean.nc output_postinf_sd.nc output_priorinf_mean.nc output_priorinf_sd.nc )
    set i = 1
    set nfiles = $#new_file
    while ($i <= $nfiles)
      if ( -e ${new_file[$i]} && ! -z ${new_file[$i]} ) then
        ${MOVE} ${new_file[$i]} ${OUTPUT_DIR}/${datea}/Inflation_input/${old_file[$i]}
        if ( ! $status == 0 ) then
           echo "failed moving ${RUN_DIR}/Output/${FILE}"
           touch BOMBED
        endif
      endif
      @ i++
    end
    echo "past the inflation file moves"
  endif   # adaptive_inflation file moves

  ###  Compute Diagnostic Quantities
  if ( -e obs_diag.log ) ${REMOVE} obs_diag.log
  ${SHELL_SCRIPTS_DIR}/diagnostics_obs.csh $datea ${SHELL_SCRIPTS_DIR}/$paramfile >& ${RUN_DIR}/obs_diag.log &

  echo "ready to integrate ensemble members"
  #  Integrate ensemble members to next analysis time
  set n = 1
  while ( $n <= $NUM_ENS )
    ### generate run script for each member
    if ( -e assim_advance_${n}.csh )  ${REMOVE} assim_advance_${n}.csh
    touch assim_advance_${n}.csh

    ##job_submit script header
    if ( $SUPER_PLATFORM == 'cheyenne' ) then
      cat >> assim_advance_${n}.csh << EOF
#!/bin/csh
#PBS -N assim_advance_${n}
#PBS -j oe
#PBS -A ${CNCAR_GAU_ACCOUNT}
#PBS -l walltime=${CADVANCE_TIME}
#PBS -q ${CADVANCE_QUEUE}
#PBS -l select=${CADVANCE_NODES}:ncpus=${CADVANCE_PROCS}:mpiprocs=${CADVANCE_MPI}
EOF
    endif

    ##job_submit script execution commands
    cat >> assim_advance_${n}.csh << EOF
cd $RUN_DIR
${SHELL_SCRIPTS_DIR}/assim_advance.csh ${datea} ${n} ${SHELL_SCRIPTS_DIR}/$paramfile
EOF

    echo "running forecast step for member ${n}"
    ${JOB_SUBMIT} assim_advance_${n}.csh
    @ n++
  end

  ###  check to see if all of the ensemble members have advanced
  cd $RUN_DIR
  set n = 1
  while ( $n <= $NUM_ENS )  ###ensemble loop
    set ensstring = `echo $n + 10000 | bc | cut -b2-5`

    set keep_trying = true
    while ( $keep_trying == 'true' )
      ###  Wait for the script to start
      while ( ! -e ${RUN_DIR}/start_member_${n} )
        ###MichaelYing: if the job failed, try resubmitting it
        if ( `${LIST_MPI_JOB} |grep assim_advance_${n} |wc -l` == 0 ) then
          echo "assim_advance_${n} is missing from the queue"
          ${JOB_SUBMIT} assim_advance_${n}.csh
        endif
        sleep 15
      end
      set start_time = `head -1 start_member_${n}`
      echo "Member $n has started.  Start time $start_time"

      ###  Wait for the output file
      while ( 1 == 1 )
        set current_time = `date +%s`
        @ length_time = $current_time - $start_time

        if ( -e ${RUN_DIR}/done_member_${n} ) then
          ###  If the output file already exists, move on
          set keep_trying = false
          break
        else if ( $length_time > ${TIMEOUT} ) then
          ###MichaelYing: if member couldn't finish for too long, throw error and exit
          ${REMOVE} start_member_${n}
          echo "member ${n} failed, stopping..."
          exit 0
        endif
        sleep 10    # this might need to be longer, though I moved the done flag lower in the
                    # advance_model.csh to hopefully avoid the file moves below failing
      end
    end

    ###  Move output data to correct location
    echo "moving ${n} ${ensstring}"
    ${MOVE} assim_advance_${n}.o*              ${OUTPUT_DIR}/${datea}/logs/.
    ${MOVE} WRFOUT/wrf.out_${gdatef[1]}_${gdatef[2]}_${n} ${OUTPUT_DIR}/${datea}/logs/.
    ${MOVE} WRFIN/wrfinput_d01_${n}.gz         ${OUTPUT_DIR}/${datea}/WRFIN/.
    ${MOVE} prior_d01.${ensstring}             ${OUTPUT_DIR}/${datea}/PRIORS/.
    ${REMOVE} start_member_${n} done_member_${n} filter_restart_d01.${ensstring}
    if ( -e assim_advance_mem${n}.csh )  ${REMOVE} assim_advance_mem${n}.csh

    @ n++

  end  ###ensemble loop

  if ( -e obs_prep.log ) ${REMOVE} obs_prep.log

  #  Clean everything up and finish
  #  Move DART-specific data to storage directory
  ${COPY} input.nml ${OUTPUT_DIR}/${datea}/.
  ${MOVE} dart_log.out dart_log.nml *.log ${OUTPUT_DIR}/${datea}/logs/.

  #  Remove temporary files from both the run directory and old storage directories
  ${REMOVE} ${OUTPUT_DIR}/${datep}/wrfinput_d*_mean ${RUN_DIR}/wrfinput_d* ${RUN_DIR}/WRF

  #  Prep data for archive
  cd ${OUTPUT_DIR}/${datea}
  gzip -f wrfinput_d*_${gdate[1]}_${gdate[2]}_mean wrfinput_d*_${gdatef[1]}_${gdatef[2]}_mean wrfbdy_d*_mean
  tar -cvf retro.tar obs_seq.out wrfin*.gz wrfbdy_d*.gz
  tar -rvf dart_data.tar obs_seq.out obs_seq.final wrfinput_d*.gz wrfbdy_d*.gz \
                            Inflation_input/* logs/* *.dat input.nml
  ${REMOVE} wrfinput_d*_${gdate[1]}_${gdate[2]}_mean.gz wrfbdy_d*.gz
  gunzip -f wrfinput_d*_${gdatef[1]}_${gdatef[2]}_mean.gz

  cd $RUN_DIR
  ${MOVE} assim*.o*            ${OUTPUT_DIR}/${datea}/logs/.
  ${MOVE} *log                 ${OUTPUT_DIR}/${datea}/logs/.
  ${REMOVE} input_priorinf_*
  ${REMOVE} static_data*
  touch prev_cycle_done
  touch cycle_finished_${datea}
  ${REMOVE} cycle_started_${datea}

  # If doing a reanalysis, increment the time if not done.  Otherwise, let the script exit
  if ( $restore == 1 ) then
    if ( $datea == $datefnl) then
      echo "Reached the final date "
      echo "Script exiting normally"
      exit
    endif
    set datea  = `echo $datea $ASSIM_INT_HOURS | ${DART_DIR}/models/wrf/work/advance_time`
  else
    echo "Script exiting normally cycle ${datea}"
    exit
  endif

end ##outermost loop

exit 0

# <next few lines under version control, do not edit>
# $URL$
# $Revision$
# $Date$
