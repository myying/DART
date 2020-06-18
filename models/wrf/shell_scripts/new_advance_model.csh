#!/bin/csh
#
# Data Assimilation Research Testbed -- DART
# Copyright 2004-2007, Data Assimilation Research Section
# University Corporation for Atmospheric Research
# Licensed under the GPL -- www.gpl.org/licenses/gpl.html
#
# <next few lines under version control, do not edit>
# $URL: https://proxy.subversion.ucar.edu/DAReS/DART/trunk/models/wrf/shell_scripts/advance_model.csh $
# $Id: advance_model.csh 4170 2009-11-30 20:56:39Z nancy $
# $Revision: 4170 $
# $Date: 2009-11-30 20:56:39 +0000 (Mon, 30 Nov 2009) $

# Shell script to run the WRF model from DART input.
# where the model advance is executed as a separate process.

# This script performs the following:
# 1.  Creates a temporary directory to run a WRF realization (see options)
# 2.  Copies or links the necessary files into the temporary directory
# 3.  Converts DART state vectors to wrf input
# 4.  Updates LBCs (optionally draws perturbations from WRF-Var random covariances)
# 5.  Writes a WRF namelist from a template
# 6.  Runs WRF
# 7.  Checks for incomplete runs
# 8.  Converts wrf output to DART state vectors

# NOTES:
# If the ensemble mean assim_model_state_ic_mean is present in the
# $RUN_DIR, it is converted to a WRF netCDF format.
# It is then used in update_wrf_bc to calculate the deviation from the mean.
# This deviation from the mean is then added at the end of the interval to
# calculate new boundary tendencies. The magnitude of the perturbation added
# at the end of the interval is controlled by infl. The purpose is to increase
# time correlation at the lateral boundaries.

# POSSIBLE TODO
# 1.  modularization?
# 2.  error checking all over

# this next section could be somewhere else in some docs.  If so
# reference is needed ("for more information about how to run this, see ...")

# File naming conventions:
#  mean wrfinput - wrfinput_d0X_${gday}_${gsec}_mean
#  mean wrfbdy - wrfbdy_d01_${gday}_${gsec}_mean
#  wrfbdy members - wrfbdy_d01_${gday}_${gsec}_${member}

###Cleaned up and moved to model/wrf/shell_scripts/ by Michael Ying 2019.
###calls param.csh instead and automate better
###finds exe files based on param.csh, user doesn't need to link to WRF_RUN again

set process = $1
set num_domains = $2
set control_file = $3
set paramfile = $4

# MULTIPLE DOMAINS - pass along the # of domains here?  We just default a value of 1 for the second variable, process is the ensemble member #
source $paramfile
module load nco
if ( $SUPER_PLATFORM == 'cheyenne' )  module load ncl/6.6.2

# Setting to vals > 0 saves wrfout files,
# will save all member output files <= to this value
set save_ensemble_member = 10 #DT
set delete_temp_dir = False

# set this to true if you want to maintain complete individual wrfinput/output
# for each member (to carry through non-updated fields)
set individual_members = true

# next line ensures that the last cycle leaves everything in the temp dirs
if ( $individual_members == true ) set delete_temp_dir = false

set  myname = $0
echo $RUN_DIR
mkdir -p ${RUN_DIR}/WRFIN ${RUN_DIR}/WRFOUT
unalias cd
unalias ls

#setenv TARGET_CPU_LIST -1

# if process 0 go ahead and check for dependencies here
###no need- Michael Ying
#if ( $process == 0 ) then

   #if ( ! -x ${RUN_DIR}/advance_time ) then
   #  echo ABORT\: advance_model.csh could not find required executable dependency ${RUN_DIR}/advance_time
   #  exit 1
   #endif

   #if ( ! -d WRF_RUN ) then
   #   echo ABORT\: advance_model.csh could not find required data directory ${RUN_DIR}/WRF_RUN, which contains all the WRF run-time input files
   #   exit 1
   #endif

#endif # process 0 dependency checking

# set this flag here if the radar additive noise script is found
if ( -e ${RUN_DIR}/add_noise.csh ) then
   set USE_NOISE = 1
else
   set USE_NOISE = 0
endif
if ( -e ${RUN_DIR}/replace_wrf_fields ) then
   set USE_REPLACE = 1
else
   set USE_REPLACE = 0
endif

# give the filesystem time to collect itself
sleep 5

# Each parallel task may need to advance more than one ensemble member.
# This control file has the actual ensemble number, the input filename,
# and the output filename for each advance.  Be prepared to loop and
# do the rest of the script more than once.
set num_states = 1      # forcing option of only one model advance per execution

set USE_WRFVAR = 1
set state_copy = 1
set ensemble_member_line = 1

# MULTIPLE DOMAINS - need a way to tell this shell script if there are multiple wrf domains in the analysis
while($state_copy <= $num_states)     # MULTIPLE DOMAINS - we don't expect advance model to run more than one member anymore. Reuse num_states for # domains?

  set ensemble_member = `head -$ensemble_member_line ${RUN_DIR}/${control_file} | tail -1`

  set infl = 0.0

  #  create a new temp directory for each member unless requested to keep and it exists already
  set temp_dir = "advance_temp${ensemble_member}"
  cd $temp_dir

  #   if ( ( -d $temp_dir ) & ( $individual_members == "true" ) ) then
  #      cd $temp_dir
  ##      set rmlist = ( `ls | grep -v wrfinput_d0.` )
  #      set rmlist = ( `ls | egrep -v 'wrfinput_d0.|wrf.info'` )
  #      echo $rmlist
  #      ${REMOVE} $rmlist
  #   else
  #      ${REMOVE} $temp_dir >& /dev/null
  #      mkdir -p $temp_dir
  #      cd $temp_dir
  #      ${COPY} ${RUN_DIR}/wrfinput_d0? .
  #   endif

  # link WRF-runtime files (required) and be.dat (if using WRF-Var)
  ${LINK} ${WRF_SRC_DIR}/run/* .

  # link DART namelist
  ${COPY} ${TEMPLATE_DIR}/input.nml input.nml

  ### append LSM data from previous cycle
  #if ( -e ${RUN_DIR}/append_lsm_data ) then
  #  ${LINK} ${RUN_DIR}/LSM/lsm_data_${ensemble_member}.nc lsm_data.nc
  #  ${RUN_DIR}/append_lsm_data
  #  ${REMOVE} lsm_data.nc
  #endif

  # nfile is required when using MPICH to run wrf.exe
  # nfile is machine specific.  Not needed on all platforms
  #hostname >! nfile
  #hostname >>! nfile

  #  Add number of domains information

  # MULTIPLE_DOMAINS - need a more general instrument here
  if ( -e ${RUN_DIR}/moving_domain_info ) then
    set MY_NUM_DOMAINS = `head -1 ${RUN_DIR}/moving_domain_info | tail -1`
    ${MOVE} input.nml input.nml--
    #sed /num_domains/c\ "   num_domains = ${MY_NUM_DOMAINS}," input.nml-- >! input.nml
    cat >! script.sed << EOF
/num_domains/c\
num_domains = ${MY_NUM_DOMAINS},
EOF
    sed -f script.sed input.nml-- >! input.nml
    ${REMOVE} input.nml--
  endif

  # DMODS - we don't have this option right now, and don't need to convert a file
  #   # if a mean state ic file exists convert it to a wrfinput_mean netcdf file
  #   if ( -e ${RUN_DIR}/assim_model_state_ic_mean ) then
  #      ${LINK} ${RUN_DIR}/assim_model_state_ic_mean dart_wrf_vector
  #      ${RUN_DIR}/dart_to_wrf >&! out.dart_to_wrf_mean
  #      ${COPY} wrfinput_d01 wrfinput_mean
  #      ${REMOVE} wrf.info dart_wrf_vector
  #   endif
  #
  #   # ICs for this wrf run; Convert DART file to wrfinput netcdf file
  #   ${MOVE} ${RUN_DIR}/${input_file} dart_wrf_vector 
  #   ${RUN_DIR}/dart_to_wrf >&! out.dart_to_wrf
  #   ${REMOVE} dart_wrf_vector
  ###Michael Ying: get stuff_var as increment_vars_a from param.csh
  #set stuff_vars =   ( U V PH T MU QVAPOR QCLOUD QRAIN QICE QSNOW QGRAUP QNICE QNRAIN \
                     #U10 V10 T2 Q2 PSFC )
  set stuff_vars = $increment_vars_a

  set num_vars = $#stuff_vars
  set stuff_str = ''   # these are variables we want to cycle
  set i = 1
  while ( $i < $num_vars )
     set stuff_str = `echo ${stuff_str}$stuff_vars[$i],`
     @ i ++
  end
  set stuff_str = `echo ${stuff_str}$stuff_vars[$num_vars]`
  #echo "stuff var " ${stuff_str}

  set dn = 1
  while ( $dn <= $num_domains )
    set dchar = `echo $dn + 100 | bc | cut -b2-3`
    set icnum = `echo $ensemble_member + 10000 | bc | cut -b2-5`
    set this_file = filter_restart_d${dchar}.${icnum}
    ncks -A -v ${stuff_str} ../${this_file} wrfinput_d${dchar}
    @ dn ++
  end
  #  Move and remove unnecessary domains    MULTIPLE DOMAINS - this problably needs to be removed to avoid confusion
  #if ( -e ${RUN_DIR}/moving_domain_info ) then
  #   set REMOVE_STRING = `cat ${RUN_DIR}/remove_domain_info`
  #   if ( ${#REMOVE_STRING} > 0 )  ${REMOVE} ${REMOVE_STRING}
  #   set n = 1
  #   set NUMBER_FILE_MOVE = `cat ${RUN_DIR}/rename_domain_info | wc -l`
  #   while ( $n <= $NUMBER_FILE_MOVE )
  #      ${MOVE} `head -${n} ${RUN_DIR}/rename_domain_info | tail -1`
  #      @ n ++
  #   end
  #endif

  # The program dart_to_wrf has created the file wrf.info.
  # Time information is extracted from wrf.info.
  # (bc in the following few lines is the calculator program,
  # not boundary conditions.)

  ### DMODS - note the wrf.info file was pre-generated, not from dart_to_wrf
  set secday = `head -1 wrf.info`
  set targsecs = $secday[1]
  set targdays = $secday[2]
  set targkey = `echo "$targdays * 86400 + $targsecs" | bc`

  set secday = `head -2 wrf.info | tail -1`
  set wrfsecs = $secday[1]
  set wrfdays = $secday[2]
  set wrfkey = `echo "$wrfdays * 86400 + $wrfsecs" | bc`

  #echo "wrf.info is read"
  #echo $USE_WRFVAR
  # Find all BC's file available and sort them with "keys".
  # NOTE: this needs a fix for the idealized wrf case in which there are no
  # boundary files (also same for global wrf).  right now some of the
  # commands below give errors, which are ok to ignore in the idealized case
  # but it is not good form to generate spurious error messages.

  # check if LBCs are "specified" (in which case wrfbdy files are req'd)
  # and we need to set up a key list to manage target times
  set SPEC_BC = `grep specified ${TEMPLATE_DIR}/namelist.input | grep true | wc -l`
  if ( $SPEC_BC > 0 ) then
    if ( $USE_WRFVAR ) then
        set bdyfiles = `ls ${RUN_DIR}/WRF/wrfbdy_d01_*_mean`
    else
        set bdyfiles = `ls ${RUN_DIR}/WRF/wrfbdy_d01_*_${ensemble_member} | grep -v mean`
    endif
    echo $bdyfiles
    set keylist = ()
    foreach f ( $bdyfiles )
        set day = `echo $f | awk -F_ '{print $(NF-2)}'`
        set sec = `echo $f | awk -F_ '{print $(NF-1)}'`
        set key = `echo "$day * 86400 + $sec" | bc`
        set keylist = ( $keylist $key )
    end
    set keys = `echo $keylist | sort`
  else  #  idealized WRF with non-specified BCs
    set keys = ( $targkey )
  endif

  set cal_date    = `head -3 wrf.info | tail -1`
  set START_YEAR  = $cal_date[1]
  set START_MONTH = $cal_date[2]
  set START_DAY   = $cal_date[3]
  set START_HOUR  = $cal_date[4]
  set START_MIN   = $cal_date[5]
  set START_SEC   = $cal_date[6]

  set START_STRING = ${START_YEAR}-${START_MONTH}-${START_DAY}_${START_HOUR}:${START_MIN}:${START_SEC}
  set datea = ${cal_date[1]}${cal_date[2]}${cal_date[3]}${cal_date[4]}

  set MY_NUM_DOMAINS    = `head -4 wrf.info | tail -1`
  set ADV_MOD_COMMAND   = `head -5 wrf.info | tail -1`

  #  Code for dealing with TC nests
  if ( -e ${RUN_DIR}/fixed_domain_info ) then
    set MY_NUM_DOMAINS = `head -1 ${RUN_DIR}/fixed_domain_info | tail -1`

  else if ( -e ${RUN_DIR}/moving_domain_info ) then
    set MY_NUM_DOMAINS = `head -2 ${RUN_DIR}/moving_domain_info | tail -1`
    ${MOVE} input.nml input.nml--
    cat >! script.sed << EOF
    /num_domains/c\
    num_domains = ${MY_NUM_DOMAINS},
EOF
#      sed /num_domains/c\ "   num_domains = ${MY_NUM_DOMAINS}," input.nml-- >! input.nml
    sed -f script.sed input.nml-- >! input.nml
    ${REMOVE} input.nml--
  endif

  # Find the next BC's file available.

  @ ifile = 1
  while ( $keys[${ifile}] <= $wrfkey )
    if ( $ifile < $#bdyfiles ) then
        @ ifile ++
    else
        echo "No boundary file available to move beyond"
        echo $START_STRING
        exit 1
    endif
  end

  # radar additive noise option.  if shell script is available
  # in the centraldir, it will be called here.
  if ( $USE_NOISE ) then
    ${RUN_DIR}/add_noise.csh $wrfsecs $wrfdays $state_copy $ensemble_member $temp_dir $RUN_DIR
  endif

  ## run the replace_wrf_fields utility to update the static fields
  if ( $USE_REPLACE ) then
    echo ../wrfinput_d01 wrfinput_d01 | ${RUN_DIR}/replace_wrf_fields
  endif


  ###############################################################
  # Advance the model with new BC until target time is reached. #
  ###############################################################
  while ( $wrfkey < $targkey )  ### wrfkey loop

    set iday = `echo "$keys[$ifile] / 86400" | bc`
    set isec = `echo "$keys[$ifile] % 86400" | bc`

    # Copy the boundary condition file to the temp directory if needed.
    if ( $SPEC_BC > 0 ) then
        if ( $USE_WRFVAR ) then
          ${COPY} ${RUN_DIR}/WRF/wrfbdy_d01_${iday}_${isec}_mean               wrfbdy_d01
        else
          ${COPY} ${RUN_DIR}/WRF/wrfbdy_d01_${iday}_${isec}_${ensemble_member} wrfbdy_d01
        endif
    endif

    if ( $targkey > $keys[$ifile] ) then
        set INTERVAL_SS = `echo "$keys[$ifile] - $wrfkey" | bc`
    else
        set INTERVAL_SS = `echo "$targkey - $wrfkey" | bc`
    endif

    #set INTERVAL_MIN = `expr $INTERVAL_SS \/ 60`
    set INTERVAL_MIN = 60

    set END_STRING = `echo ${START_STRING} ${INTERVAL_SS}s -w | ${DART_DIR}/models/wrf/work/advance_time`
    set END_YEAR  = `echo $END_STRING | cut -c1-4`
    set END_MONTH = `echo $END_STRING | cut -c6-7`
    set END_DAY   = `echo $END_STRING | cut -c9-10`
    set END_HOUR  = `echo $END_STRING | cut -c12-13`
    set END_MIN   = `echo $END_STRING | cut -c15-16`
    set END_SEC   = `echo $END_STRING | cut -c18-19`
    #set datef = ${END_STRING[1]}${END_STRING[2]}${END_STRING[3]}${END_STRING[4]}

    # Update boundary conditions. perturb bc
    # If it is found in the central dir, use it to regnerate perturbed boundary files
    # Otherwise, do the original call to update_wrf_bc
    if ( $USE_WRFVAR ) then
      #  Set the covariance perturbation scales using file or default values
      if ( -e ${RUN_DIR}/bc_pert_scale ) then
        set pscale = `head -1 ${RUN_DIR}/bc_pert_scale | tail -1`
        set hscale = `head -2 ${RUN_DIR}/bc_pert_scale | tail -1`
        set vscale = `head -3 ${RUN_DIR}/bc_pert_scale | tail -1`
      else
        set pscale = 0.25
        set hscale = 1.0
        set vscale = 1.5
      endif
      @ iseed2 = $ensemble_member * 10

      ###prepare namelist.input
      $REMOVE namelist.input
      ${REMOVE} script.sed
      cat >! script.sed << EOF
/analysis_date/c\
analysis_date = \'${END_STRING}.0000\',
/as1/c\
as1 = ${pscale}, ${hscale}, ${vscale},
/as2/c\
as2 = ${pscale}, ${hscale}, ${vscale},
/as3/c\
as3 = ${pscale}, ${hscale}, ${vscale},
/as4/c\
as4 = ${pscale}, ${hscale}, ${vscale},
/as5/c\
as5 = ${pscale}, ${hscale}, ${vscale},
/put_rand_seed/c\
put_rand_seed = .true.,
/seed_array1/c\
seed_array1 = 1${END_MONTH}${END_DAY}${END_HOUR},
/seed_array2/c\
seed_array2 = $iseed2,
/start_year/c\
start_year = ${END_YEAR},
/start_month/c\
start_month = ${END_MONTH},
/start_day/c\
start_day = ${END_DAY},
/start_hour/c\
start_hour = ${END_HOUR},
/start_minute/c\
start_minute = ${END_MIN},
/start_second/c\
start_second = ${END_SEC},
/end_year/c\
end_year = ${END_YEAR},
/end_month/c\
end_month = ${END_MONTH},
/end_day/c\
end_day = ${END_DAY},
/end_hour/c\
end_hour = ${END_HOUR},
/end_minute/c\
end_minute = ${END_MIN},
/end_second/c\
end_second = ${END_SEC},
/max_dom/c\
max_dom = 1,
EOF

      sed -f script.sed ${TEMPLATE_DIR}/namelist.input >! namelist.input

      ${LINK} ${RUN_DIR}/WRF/wrfinput_d01_${targdays}_${targsecs}_mean ./fg
      ################################
      ## instead of running wrfda, just add static pertubations from the pert bank
      #  note the static perturbation path is defined in the ncl script
      #        setenv TARGET_CPU_RANGE        "-1
      #        mpiexec_mpt dplace -s 1  ${RUN_DIR}/WRF_RUN/da_wrfvar.exe >>&! out.wrfvar
      cp fg wrfvar_output
      ${REMOVE} nclrun3.out
      cat >! nclrun3.out << EOF
ncl 'NUM_PERT=${NUM_PERT}' 'PERT_BANK="${PERT_BANK_DIR}"' ${SHELL_SCRIPTS_DIR}/add_bank_perts.ncl
EOF
      chmod +x nclrun3.out
      ./nclrun3.out >& add_perts.out

      cp namelist.input namelist.input.3dvar
      if ( -e rsl.out.0000 ) cat rsl.out.0000 >> out.wrfvar

      ${MOVE} wrfvar_output wrfinput_next
      ${LINK} wrfinput_d01 wrfinput_this
      ${LINK} wrfbdy_d01 wrfbdy_this

      # if wrfinput_mean file found, rename it
      if ( -e wrfinput_mean ) then
        ${MOVE} wrfinput_mean   wrfinput_this_mean
        ${MOVE} fg              wrfinput_next_mean
      endif

      ${DART_DIR}/models/wrf/work/pert_wrf_bc >&! out.pert_wrf_bc
      ${REMOVE} wrfinput_this wrfinput_next wrfbdy_this
      if ( -e wrfinput_this_mean ) ${REMOVE} wrfinput_this_mean wrfinput_next_mean

    else  # Update boundary conditions from existing wrfbdy files

      echo $infl | ${DART_DIR}/models/wrf/work/update_wrf_bc >&! out.update_wrf_bc

    endif

    ${REMOVE} script.sed namelist.input
    cat >! script.sed << EOF
/run_hours/c\
run_hours                  = 0,
/run_minutes/c\
run_minutes                = 0,
/run_seconds/c\
run_seconds                = ${INTERVAL_SS},
/start_year/c\
start_year                 = ${MY_NUM_DOMAINS}*${START_YEAR},
/start_month/c\
start_month                = ${MY_NUM_DOMAINS}*${START_MONTH},
/start_day/c\
start_day                  = ${MY_NUM_DOMAINS}*${START_DAY},
/start_hour/c\
start_hour                 = ${MY_NUM_DOMAINS}*${START_HOUR},
/start_minute/c\
start_minute               = ${MY_NUM_DOMAINS}*${START_MIN},
/start_second/c\
start_second               = ${MY_NUM_DOMAINS}*${START_SEC},
/end_year/c\
end_year                   = ${MY_NUM_DOMAINS}*${END_YEAR},
/end_month/c\
end_month                  = ${MY_NUM_DOMAINS}*${END_MONTH},
/end_day/c\
end_day                    = ${MY_NUM_DOMAINS}*${END_DAY},
/end_hour/c\
end_hour                   = ${MY_NUM_DOMAINS}*${END_HOUR},
/end_minute/c\
end_minute                 = ${MY_NUM_DOMAINS}*${END_MIN},
/end_second/c\
end_second                 = ${MY_NUM_DOMAINS}*${END_SEC},
/history_interval/c\
history_interval           = ${MY_NUM_DOMAINS}*${INTERVAL_MIN},
/frames_per_outfile/c\
frames_per_outfile         = ${MY_NUM_DOMAINS}*1,
/max_dom/c\
max_dom                    = ${MY_NUM_DOMAINS},
EOF

    if ( -e ${RUN_DIR}/fixed_domain_info ) then
      set nx_string      = `head -2 ${RUN_DIR}/fixed_domain_info | tail -1`
      set ny_string      = `head -3 ${RUN_DIR}/fixed_domain_info | tail -1`
      set i_start_str    = `head -4 ${RUN_DIR}/fixed_domain_info | tail -1`
      set j_start_str    = `head -5 ${RUN_DIR}/fixed_domain_info | tail -1`

      cat >> script.sed << EOF
/e_we/c\
e_we                                = ${nx_string},
/e_sn/c\
e_sn                                = ${ny_string},
/i_parent_start/c\
i_parent_start                      = ${i_start_str},
/j_parent_start/c\
j_parent_start                      = ${j_start_str},
EOF

    else if ( -e ${RUN_DIR}/moving_domain_info ) then
      set nx_string      = `head -3  ${RUN_DIR}/moving_domain_info | tail -1`
      set ny_string      = `head -4  ${RUN_DIR}/moving_domain_info | tail -1`
      set i_start_str    = `head -5  ${RUN_DIR}/moving_domain_info | tail -1`
      set j_start_str    = `head -6  ${RUN_DIR}/moving_domain_info | tail -1`
      set input_file     = `head -7  ${RUN_DIR}/moving_domain_info | tail -1`
      set num_move_str   = `head -8  ${RUN_DIR}/moving_domain_info | tail -1`
      set id_move_str    = `head -9  ${RUN_DIR}/moving_domain_info | tail -1`
      set move_time_str  = `head -10 ${RUN_DIR}/moving_domain_info | tail -1`
      set x_move_string  = `head -11 ${RUN_DIR}/moving_domain_info | tail -1`
      set y_move_string  = `head -12 ${RUN_DIR}/moving_domain_info | tail -1`

      cat >> script.sed << EOF
/e_we/c\
e_we                                = ${nx_string},
/e_sn/c\
e_sn                                = ${ny_string},
/i_parent_start/c\
i_parent_start                      = ${i_start_str},
/j_parent_start/c\
j_parent_start                      = ${j_start_str},
/input_from_file/c\
input_from_file                     = ${input_file},
/num_moves/c\
num_moves                           = ${num_move_str},
/move_id/c\
move_id                             = ${id_move_str}
/move_interval/c\
move_interval                       = ${move_time_str}
/move_cd_x/c\
move_cd_x                           = ${x_move_string}
/move_cd_y/c\
move_cd_y                           = ${y_move_string}
EOF

    endif

    sed -f script.sed ${TEMPLATE_DIR}/namelist.input >! namelist.input

    #-------------------------------------------------------------
    #
    # HERE IS A GOOD PLACE TO GRAB FIELDS FROM OTHER SOURCES
    # AND STUFF THEM INTO YOUR wrfinput_d0? FILES
    #
    #------------------------------------------------------------

    # clean out any old rsl files
    if ( -e rsl.out.integration )  ${REMOVE} rsl.*

    # run WRF here
    #setenv MPI_SHEPHERD true
    ${ADV_MOD_COMMAND} >>&! rsl.out.integration

    if ( -e rsl.out.0000 ) cat rsl.out.0000 >> rsl.out.integration
    ${COPY} rsl.out.integration ${RUN_DIR}/WRFOUT/wrf.out_${targdays}_${targsecs}_${ensemble_member}
    #sleep 1

    set SUCCESS = `grep "wrf: SUCCESS COMPLETE WRF" rsl.out.integration | cat | wc -l`
    if ($SUCCESS == 0) then
      echo $ensemble_member >>! ${RUN_DIR}/blown_${targdays}_${targsecs}.out
      echo "Model failure! Check file " ${RUN_DIR}/blown_${targdays}_${targsecs}.out
      echo "for a list of failed ensemble_members, and check here for the individual output files:"
      echo " ${RUN_DIR}/WRFOUT/wrf.out_${targdays}_${targsecs}_${ensemble_member}  "
      exit -1
    endif

    if ( -e ${RUN_DIR}/append_precip_to_diag ) then
      set dn = 1
      while ( $dn <= $num_domains )
        ncks -h -O -F -v RAINC,RAINNC wrfout_d0${dn}_${END_STRING} wrf_precip.nc
        ${MOVE} wrf_precip.nc ${RUN_DIR}/wrf_precip_d0${dn}_${END_STRING}_${ensemble_member}
        @ dn ++
      end
    endif

    #if ( $ensemble_member <= 1 ) then
    #    set dn = 2
    #    while ( $dn <= $num_domains )
    #      ${COPY} psfc_data_d0${dn}.nc wrfout.nc
    #      ${RUN_DIR}/domain_psfc_tend
    #      ${MOVE} psfc_stats.nc ${RUN_DIR}/psfc_stat_d0${dn}.nc
    #      @ dn ++
    #    end
    #endif

    ### zip up the wrfin file
    set dn = 1
    while ( $dn <= $num_domains )
        ${MOVE} wrfinput_d0${dn} wrfinput_d0${dn}_${ensemble_member}
        gzip wrfinput_d0${dn}_${ensemble_member} &
        @ dn ++
    end

    ### forecast date
    set dn = 1
    while ( $dn <= $num_domains )
      if ( $ensemble_member <= $save_ensemble_member )   ${COPY} wrfout_d0${dn}_${END_STRING} ${RUN_DIR}/WRFOUT/wrfout_d0${dn}_${END_STRING}_${ensemble_member}
      # if the wrfinput file zip operation is finished, wrfinput_d0${dn}_$ensemble_member should no 
      # longer be in the directory
      # test for this, and wait if the zip operation is not yet finished
      while ( -e wrfinput_d0${dn}_${ensemble_member} )
        sleep 3
        #touch ${RUN_DIR}/HAD_TO_WAIT
      end
      ${MOVE} wrfinput_d0${dn}_${ensemble_member}.gz ${RUN_DIR}/WRFIN/wrfinput_d0${dn}_${ensemble_member}.gz
      ${MOVE} wrfout_d0${dn}_${END_STRING} wrfinput_d0${dn}
      @ dn ++
    end

    #${REMOVE} wrfout*  #DT

    set START_YEAR  = $END_YEAR
    set START_MONTH = $END_MONTH
    set START_DAY   = $END_DAY
    set START_HOUR  = $END_HOUR
    set START_MIN   = $END_MIN
    set START_SEC   = $END_SEC
    set wrfkey      = $keys[$ifile]
    @ ifile ++

  end  ###wrfkey loop

  ##############################################
  # At this point, the target time is reached. #
  ##############################################
  # withdraw LSM data to use in next cycle   This is remnant from the Lanai days, we now pull soil state
  # together with everything else
  if ( -e ${RUN_DIR}/fixed_domain_info )  set MY_NUM_DOMAINS = 1
  if ( -e ${RUN_DIR}/append_lsm_data ) then
    set dn = 1
    while ( $dn <= $num_domains )
      ncks -h -F -A -a -v TSLB,SMOIS,SH2O,TSK wrfinput_d0${dn} lsm_data.nc
      ncrename -h -v TSLB,TSLB_d0${dn} -v SMOIS,SMOIS_d0${dn} -v SH2O,SH2O_d0${dn} -v TSK,TSK_d0${dn} \
               -d west_east,west_east_d0${dn} -d south_north,south_north_d0${dn} \
               -d soil_layers_stag,soil_layers_stag_d0${dn} lsm_data.nc\
      @ dn ++
    end
    ${REMOVE} ${RUN_DIR}/LSM/lsm_data_${ensemble_member}.nc
    ${MOVE} lsm_data.nc ${RUN_DIR}/LSM/lsm_data_${ensemble_member}.nc
  endif

  if ( -e ${RUN_DIR}/fixed_domain_info || -e ${RUN_DIR}/moving_domain_info ) then
    ln -sf ${RUN_DIR}/wrfinput_d01 wrfinput_d01_base
    ${RUN_DIR}/recalc_wrf_base >&! out.recalc_wrf_base
  endif
  #   extract the cycle variables
  #   # create new input to DART (taken from "wrfinput")
  #   ${RUN_DIR}/wrf_to_dart >&! out.wrf_to_dart
  #   ${MOVE} dart_wrf_vector ${RUN_DIR}/${output_file}
  #set extract_vars_a = ( U V PH T MU QVAPOR QCLOUD QRAIN QICE QSNOW QGRAUP QNICE QNRAIN \
  #                     U10 V10 T2 Q2 PSFC TH2 TSLB SMOIS TSK RAINC RAINNC GRAUPELNC )
  #set extract_vars_b = ( U V W PH T MU QVAPOR QCLOUD QRAIN QICE QSNOW QGRAUP QNICE QNRAIN H_DIABATIC \
  #                     U10 V10 T2 Q2 PSFC TH2 TSLB SMOIS TSK RAINC RAINNC GRAUPELNC \
  #                     REFL_10CM VT_DBZ_WT )
  ####Michael Ying: get extract_vars_a/b from param.csh instead:
  set num_vars = $#extract_vars_a
  set extract_str_a = ''
  set i = 1
  while ( $i <= $num_vars )
    set extract_str_a = `echo ${extract_str_a}$extract_vars_a[$i],`
    @ i++
  end
  set extract_str_a = `echo ${extract_str_a}$extract_vars_a[$num_vars]`
  echo ${extract_str_a}

  set num_vars = $#extract_vars_b
  set extract_str_b = ''
  set i = 1
  while ( $i <= $num_vars )
    set extract_str_b = `echo ${extract_str_b}$extract_vars_b[$i],`
    @ i++
  end
  set extract_str_b = `echo ${extract_str_b}$extract_vars_b[$num_vars]`
  echo ${extract_str_b}


  ### MULTIPLE DOMAINS - loop through wrf files that are present
  set dn = 1
  while ( $dn <= $num_domains )
    set dchar = `echo $dn + 100 | bc | cut -b2-3`
    set icnum = `echo $ensemble_member + 10000 | bc | cut -b2-5`
    set outfile =  prior_d${dchar}.${icnum}
    if ( $dn == 1) then
      ncks -O -v ${extract_str_a} wrfinput_d${dchar} ../$outfile
    else
      ncks -O -v ${extract_str_b} wrfinput_d${dchar} ../$outfile
    endif
    @ dn ++
    echo "should have made $outfile"
  end
  ### MULTIPLE DOMAINS - may need to remove below to avoid confusion
  if ( -e ${RUN_DIR}/moving_domain_info && $ensemble_member == 1 ) then
    set dn = 2
    while ( $dn <= $num_domains )
      ${COPY} wrfinput_d0${dn} ${RUN_DIR}/wrfinput_d0${dn}_new
      @ dn ++
    end
  endif

  touch ${RUN_DIR}/done_member_$ensemble_member

  cd $RUN_DIR

  #  delete the temp directory for each member if desired
  if ( $delete_temp_dir == true )  ${REMOVE} ${temp_dir}
  echo "Ensemble Member $ensemble_member completed"

  # and now repeat the entire process for any other ensemble member that
  # needs to be advanced by this task.
  # don't expect this to ever be run
  @ state_copy ++
  @ ensemble_member_line += 3

end  ###state_copy loop

# Remove the filter_control file to signal completion
# Is there a need for any sleeps to avoid trouble on completing moves here?
${REMOVE} $control_file
if ($SUCCESS == 1) then
  echo " done_member_$ensemble_member"
endif

exit 0

