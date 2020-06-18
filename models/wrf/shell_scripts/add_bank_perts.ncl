; Simple utility to add perturbation fields from the
; perturbation bank files to a provided wrfinput file.
; consistent with use in the advance_model.csh script 
; where we are substituting this call for running 
; da_wrfvar.exe, so the wrfinput file to perturb
; should be called 'wrfinput_next', and is the mean
; state for the target lateral boundaries.

begin
 pert_bank_path = PERT_BANK
 bank_size = NUM_PERT

; perturbation scaling:
 scale_T = 0.2
 scale_U = 0.2
 scale_V = 0.2
 scale_Q = 0.2
 scale_M = 0.2

; for random pert, pick from larger bank
 con  = bank_size / 32766.0      ; 32766.0 forces a 0.0 to 1.0 range
; get a seed
 wallClock = stringtoint(systemfunc("date -u +%N"))
 srand(wallClock)
 ens_mem_num =  floattoint(con * rand())
 tmpvar = (/1,toint(ens_mem_num)/)
 ens_mem_num = max(tmpvar)
 delete(tmpvar)
 tmpvar = (/bank_size,toint(ens_mem_num)/)
 ens_mem_num = min(tmpvar)
 delete(tmpvar)
; open selected file
 pert_bank_file = "pert_bank_mem_"+ens_mem_num+".nc"
 wrf_file = "wrfvar_output"+".nc"

 print ("bank member number "+ens_mem_num)

 pert_fields = (/"U", "V", "T", "QVAPOR","MU"/)
 pert_scale  = (/scale_U,scale_V,scale_T,scale_Q,scale_M/)
 nperts = dimsizes(pert_fields)
 pert_in = addfile(pert_bank_path+"/"+pert_bank_file,"r")
 wrf_in  = addfile(wrf_file,"w")
 do n=0,nperts-1
  temp_w = wrf_in->$pert_fields(n)$
  temp_p = pert_in->$pert_fields(n)$
  temp_c = temp_w+(temp_p * pert_scale(n))
  wrf_in->$pert_fields(n)$ = temp_c
  delete(temp_w)
  delete(temp_p)
  delete(temp_c)
 end do
 delete(pert_in)
 delete(wrf_in)
 print("perts added")
end
