@echo off
rem
rem   Build the EMAIL library.
rem
setlocal
set libname=email
set srclib=email

call src_get "%srclib%" %libname%.ins.pas
call src_get "%srclib%" %libname%2.ins.pas
call src_getfrom sys sys.ins.pas
call src_getfrom util util.ins.pas
call src_getfrom string string.ins.pas
call src_getfrom file file.ins.pas

call src_get %srclib% %libname%.insall.pas
sst %libname%.insall.pas -show_unused 0 -local_ins -ins %libname%.ins.pas
copya %libname%.insall.c (cog)lib/%libname%.h
del %libname%.insall.c

call src_pas %srclib% email_adr %1
call src_pas %srclib% email_adr_extract %1
call src_pas %srclib% email_adr_translate %1
call src_pas %srclib% smtp_client %1

rem call src_pas %srclib% smtp_client_thread %1
rem call src_pas %srclib% smtp_queue %1
rem call src_pas %srclib% smtp_queue_read %1
rem call src_pas %srclib% smtp_queue_write %1
rem call src_pas %srclib% smtp_recv %1
rem call src_pas %srclib% smtp_rinfo %1
rem call src_pas %srclib% smtp_rqmeth %1
rem call src_pas %srclib% smtp_send %1
rem call src_pas %srclib% smtp_send_queue %1
rem call src_pas %srclib% smtp_subs %1
rem call src_pas %srclib% %libname%_comblock %1

call src_lib %srclib% %libname%
call src_msg %srclib% %libname%
