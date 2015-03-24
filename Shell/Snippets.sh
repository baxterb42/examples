# Select shell code snippets
# vim:ts=4

### run some "here doc" SQL code against Oracle, using the command line sqlplus utility
###    (there are some environmental prerequisites)
###    param_crit_ge_warn, chk_ora_err, and chk_ora_err are all subroutine calls, supported by a sourced library file

blocklocks )

    param_crit_ge_warn

    WAITTIME=$1

result=`sqlplus -S / <<EOT
set pagesize 0 head off echo off space 0 newpage 0
SELECT ltrim(to_char(count(*) ))
FROM sys.v_\\$lock
WHERE request not in (0,2)
AND ctime > ${WAITTIME};
exit
EOT`

    chk_ora_err

    rtn_trigger_if_high_1x1 $result "Blocking lock count" "" "" ""
    ;;


