{   Module of routines for manipulating the SMTP_RINFO data structure.
}
module smtp_rinfo;
define smtp_rinfo_init;
define smtp_rinfo_read_env;
define smtp_receive_wait;
%include 'email2.ins.pas';

const
  n_cmds_k = 17;                       {num of env file commands we recognize}
  max_cmdlen_k = 9;                    {number of chars in longest env command name}
  cmd_dim_k = max_cmdlen_k + 1;        {dimension of each command string}

type
  command_t =                          {string to hold one command name}
    array[1..cmd_dim_k] of char;

  commands_t = record                  {var string to hold all the command names}
    max: string_index_t;
    len: string_index_t;
    str: array[1..n_cmds_k] of command_t;
    end;

var
  commands: commands_t := [
    len := cmd_dim_k * n_cmds_k - 1, max := cmd_dim_k * n_cmds_k, str := [
      'NAME     ',                     {1}
      'ISP      ',                     {2}
      'PHBOOK   ',                     {3}
      'USER     ',                     {4}
      'PASSWORD ',                     {5}
      'PORT     ',                     {6}
      'WAIT     ',                     {7}
      'MAXDIALS ',                     {8}
      'DOMAIN   ',                     {9}
      'METHOD   ',                     {10}
      'CONNECT  ',                     {11}
      'BEGIN    ',                     {12}
      'END      ',                     {13}
      'PHNUMBER ',                     {14}
      'REMOTESYS',                     {15}
      'OUTQUEUE ',                     {16}
      'ISPDOMAIN',                     {17}
      ]
    ];
  not_str: string_var4_t := [
    str := 'NOT', len := 3, max := sizeof(not_str.str)];
{
********************************************************************
*
*   Subroutine SMTP_RINFO_INIT (RINFO)
*
*   Initialize RINFO to benign or default values.  This routine should always
*   be called to initialize a SMTP_RINFO_T structure.  An application should
*   never assume it is aware of all of the fields in the structure.  As new
*   fields are added, the code to initialize them will always be added here
*   also.
}
procedure smtp_rinfo_init (            {init SMTP_RINFO_T to benign default values}
  out     rinfo: smtp_rinfo_t);        {data structure to fill in}
  val_param;

var
  i: sys_int_machine_t;                {loop counter}
  p: ^char;

begin
  p := univ_ptr(addr(rinfo));          {init pointer to start of RINFO}
  for i := 1 to sizeof(rinfo) do begin {clear whole structure to zero}
    p^ := chr(0);
    p := univ_ptr(sys_int_machine_t(p) + 1);
    end;

  rinfo.name.max := sizeof(rinfo.name.str);
  rinfo.name.len := 0;
  rinfo.machine.max := sizeof(rinfo.machine.str);
  rinfo.machine.len := 0;
  rinfo.qname.max := sizeof(rinfo.qname.str);
  rinfo.qname.len := 0;
  rinfo.isp.max := sizeof(rinfo.isp.str);
  rinfo.isp.len := 0;
  rinfo.domain_isp.max := sizeof(rinfo.domain_isp.str);
  rinfo.domain_isp.len := 0;
  rinfo.phbook_ent.max := sizeof(rinfo.phbook_ent.str);
  rinfo.phbook_ent.len := 0;
  rinfo.phnum.max := sizeof(rinfo.phnum.str);
  rinfo.phnum.len := 0;
  rinfo.user.max := sizeof(rinfo.user.str);
  rinfo.user.len := 0;
  rinfo.password.max := sizeof(rinfo.password.str);
  rinfo.password.len := 0;
  rinfo.port_smtp := 25;
  rinfo.sec_inact_done := 2.0 * 60.0;;
  rinfo.sec_active_done := rinfo.sec_inact_done;
  rinfo.sec_redial_wait := 10.0;
  rinfo.n_max_dial := 10;
  rinfo.domains.max := sizeof(rinfo.domains.str);
  rinfo.domains.len := 0;
  rinfo.rqmeth := smtp_rqmeth_turn_k;
  rinfo.connect := true;
  rinfo.userset := [];
  end;
{
********************************************************************
*
*   Local function SMTP_RINFO_SAME (R1, R2)
*
*   Compares to SMTP_RINFO_T descriptors and returns TRUE if and only if
*   they contain identical information.  NOTE: The system-dependent field
*   CONN is not compared.  CONN can not be altered thru the environment
*   file set.
}
function smtp_rinfo_same (             {compare to remote mail feed info descriptors}
  in      r1, r2: smtp_rinfo_t)        {the descriptors to compare}
  :boolean;                            {TRUE on both descriptors contain same info}
  val_param;

begin
  smtp_rinfo_same := false;            {init to the descriptors differ}

  if not string_equal(r1.name, r2.name) then return;
  if not string_equal(r1.machine, r2.machine) then return;
  if not string_equal(r1.qname, r2.qname) then return;
  if not string_equal(r1.isp, r2.isp) then return;
  if not string_equal(r1.domain_isp, r2.domain_isp) then return;
  if not string_equal(r1.phbook_ent, r2.phbook_ent) then return;
  if not string_equal(r1.phnum, r2.phnum) then return;
  if not string_equal(r1.user, r2.user) then return;
  if not string_equal(r1.password, r2.password) then return;
  if r1.port_smtp <> r2.port_smtp then return;
  if r1.sec_inact_done <> r2.sec_inact_done then return;
  if r1.sec_active_done <> r2.sec_active_done then return;
  if r1.sec_redial_wait <> r2.sec_redial_wait then return;
  if r1.n_max_dial <> r2.n_max_dial then return;
  if not string_equal(r1.domains, r2.domains) then return;
  if r1.rqmeth <> r2.rqmeth then return;
  if r1.connect <> r2.connect then return;

  smtp_rinfo_same := true;             {yes, they really are the same}
  end;
{
********************************************************************
*
*   Subroutine SMTP_RINFO_READ_ENV (RINFO, STAT)
*
*   Update information in the remote mail feed descriptor RINFO by reading
*   the MAILFEED.ENV environment file set.
*
*   RINFO must have previously been initialized by SMTP_RINFO_INIT, and may
*   have been modified by the application before being passed here.  Some of the
*   information read from the environment file set depends on existing RINFO
*   entries.
*
*   Settings in more local environment files override settings in more global
*   files.  The environment file set is re-read until no net changes to RINFO
*   are made in one pass.  It is an error if this doesn't happen after a
*   sufficiently large number of re-read attempts.
}
procedure smtp_rinfo_read_env (        {update RINFO from data in environment files}
  in out  rinfo: smtp_rinfo_t;         {data structure to update, previously init}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

const
  name_env_k = 'mailfeed.env';         {environment file set name}
  max_passes_k = 16;                   {max passes to wait for no change}

var
  fnam_env: string_leafname_t;         {environment file set name}
  conn: file_conn_t;                   {connection handle to environment file set}
  ibuf: string_var8192_t;              {one line input buffer}
  p: string_index_t;                   {IBUF parse index}
  cmd: string_var32_t;                 {current command name}
  parm: string_var80_t;                {command parameter}
  s: string_var80_t;                   {scratch string}
  pick: sys_int_machine_t;             {number of keyword picked from list}
  pass: sys_int_machine_t;             {1-N number of this read pass}
  i: sys_int_machine_t;                {scratch integer}
  rinfo_old: smtp_rinfo_t;             {saved copy of RINFO before current pass}
  inhibit: sys_int_machine_t;          {commands inhibited when > 0}
  inhibit_old: sys_int_machine_t;      {inhibit value at start of command}
  ignored: boolean;                    {TRUE if command ignored for some reason}
  tf: boolean;                         {BEGIN block TRUE/FALSE flag}
  notif: boolean;                      {NOT present on TRUE}
  c: char;                             {scratch character}

label
  loop_pass, loop_line, loop_dom, done_dom, next_phchar,
  done_cmd, extra_email, err_parm, eof, abort1;
{
**********************************************************
*
*   Local function PARM_TIME(STAT)
*   This routine is local to SMTP_RINFO_READ_ENV.
*
*   The function value is the time value in seconds at the current command
*   line position.
*
*   A time value is a string of keywords separated by one or more spaces.
*   Some keywords may have optional parameters.  The valid keywords are:
*
*     <seconds> SEC
*     <minutes> MIN
*
*       Add the indicated amount of time to the current time value.
*       If the last token is a value without a units keyword following,
*       then it is interpreted as being seconds.
*
*   The current time value is initialized to 0 before keyword processing
*   begins.
}
function parm_time (                   {get value of time argument}
  out     stat: sys_err_t)
  :real;                               {time argument value in seconds}

var
  val: real;                           {value of last value token}
  total: real;                         {total seconds so far}
  pick: sys_int_machine_t;             {number of keyword picked from list}

label
  loop_val, done_units;

begin
  total := 0.0;                        {init total time specified so far}
  parm_time := 0.0;                    {init return value to keep compiler happy}

loop_val:                              {back here to read next value keyword}
{
*   Handle next time value token.
}
  string_token (ibuf, p, parm, stat);  {try to get next command parameter}
  if string_eos(stat) then begin       {hit end of command string ?}
    parm_time := total;                {pass back total seconds found}
    return;                            {normal return}
    end;
  if sys_error(stat) then return;
  string_t_fpm (parm, val, stat);      {get token numeric value in VAL}
  if sys_error(stat) then return;
{
*   Handle units keyword.
}
  string_token (ibuf, p, parm, stat);  {try to get next command parameter}
  if string_eos(stat) then goto done_units; {no units implies seconds}
  if sys_error(stat) then return;
  string_upcase (parm);                {make upper case for keyword matching}
  string_tkpick80 (parm, 'SEC MIN', pick); {pick keyword from list}
  case pick of                         {which keyword is it ?}
1:  ;                                  {SEC, VAL already in seconds}
2:  val := val * 60.0;                 {MIN, convert from minutes to seconds}
otherwise
    sys_stat_set (sys_subsys_k, sys_stat_failed_k, stat);
    return;                            {return with error}
    end;
done_units:                            {done converting to seconds}

  total := total + val;                {add in contribution from this value}
  goto loop_val;                       {back to read next value}
  end;
{
**********************************************************
*
*   Function PARM_YESNO(STAT)
*   This routine is local to SMTP_RINFO_READ_ENV.
*
*   Returns TRUE if the next token is YES, Y, TRUE, or ON.
*   Returns FALSE if tne next token is NO, N, FALSE, or OFF.
*   Any other token values result in an error condition.
}
function parm_yesno (                  {get yes/no value}
  out     stat: sys_err_t)
  :boolean;

var
  pick: sys_int_machine_t;             {number of keyword picked from list}

begin
  parm_yesno := false;                 {init return value to keep compiler happy}
  string_token (ibuf, p, parm, stat);  {try to get next command parameter}
  if sys_error(stat) then return;
  string_upcase (parm);                {make upper case for keyword matching}
  string_tkpick80 (parm,               {pick keyword from list}
    'YES Y TRUE ON NO N FALSE OFF',
    pick);                             {number of keyword picked from list}
  case pick of                         {which keyword is it ?}
1, 2, 3, 4: parm_yesno := true;
5, 6, 7, 8: parm_yesno := false;
otherwise
    sys_stat_set (sys_subsys_k, sys_stat_failed_k, stat);
    end;
  end;
{
**********************************************************
*
*   Start of main routine.
}
begin
  fnam_env.max := sizeof(fnam_env.str); {init local var strings}
  ibuf.max := sizeof(ibuf.str);
  cmd.max := sizeof(cmd.str);
  parm.max := sizeof(parm.str);
  s.max := sizeof(s.str);
  sys_error_none (stat);               {init to no errors occurred}

  string_vstring (                     {make var name environment file set name}
    fnam_env, name_env_k, sizeof(name_env_k));
  pass := 0;                           {init number of current pass thru file set}
{
*   Back here to re-read the environment file set.  We keep reading the whole
*   file set until nothing ends up changing.  The information read from the
*   env file set can change depending on the current state.
}
loop_pass:                             {back here for another read pass}
  pass := pass + 1;                    {make number of this pass thru env file set}
  if pass > max_passes_k then begin    {too many passes, assume circular dependency}
    sys_stat_set (email_subsys_k, email_stat_mailfeed_loop_k, stat);
    sys_stat_parm_int (max_passes_k, stat);
    sys_stat_parm_vstr (fnam_env, stat);
    return;
    end;

  file_open_read_env (                 {open environment file set for read}
    fnam_env,                          {environment file set name}
    '',                                {name suffix}
    true,                              {read in globl to local order}
    conn,                              {returned connection handle}
    stat);
  if sys_error(stat) then return;

  rinfo_old := rinfo;                  {save copy of current state before this pass}
  inhibit := 0;                        {init to commands are not inhibited}
{
*   Back here to read each new line from the environment file set.
}
loop_line:
  file_read_env (conn, ibuf, stat);    {read next line from file set}
  if file_eof(stat) then goto eof;     {hit end of environment file set ?}
  if sys_error(stat) then goto abort1; {hard error reading files ?}
  string_unpad (ibuf);                 {truncate trailing spaces from input line}
  if ibuf.len <= 0 then goto loop_line; {ignore blank lines}
  p := 1;                              {init IBUF parse index to start of line}
  string_token (ibuf, p, cmd, stat);   {parse command name from input line}
  if string_eos(stat) then goto loop_line; {ignore line if no command keyword found}
  if sys_error(stat) then goto abort1; {hard error parsing input line ?}
  inhibit_old := inhibit;              {save inhibit value before this command}
  ignored := true;                     {init to command was ignored}
  string_upcase (cmd);                 {make upper case for keyword matching}
  string_tkpick (cmd, commands, pick); {pick command name from list}
  case pick of                         {which command is it ?}
{
**********************
*
*   NAME name
}
1: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_name_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  string_upcase (parm);
  string_copy (parm, rinfo.name);
  end;
{
**********************
*
*   ISP name
}
2: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_isp_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  string_upcase (parm);
  string_copy (parm, rinfo.isp);
  end;
{
**********************
*
*   PHBOOK name
}
3: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_phbook_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  string_copy (parm, rinfo.phbook_ent);
  end;
{
**********************
*
*   USER name
}
4: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_user_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  string_copy (parm, rinfo.user);
  end;
{
**********************
*
*   PASSWORD string
}
5: begin
{
*   Extract password into S, then truncate input line to before password.
*   This prevents the password from being echoed in debug mode.
}
  i := p;                              {save parse index before password}
  string_token (ibuf, p, parm, stat);  {extract password from input line}
  if sys_error(stat) then goto err_parm;
  string_copy (parm, s);               {save password in S}
  string_token (ibuf, p, parm, stat);  {try to get another token from this line}
  if not string_eos(stat) then goto extra_email; {actually found a token ?}
  if sys_error(stat) then goto err_parm;
  ibuf.len := i - 1;                   {truncate input line to before password}
  string_unpad (ibuf);                 {truncate right after command keyword}
{
*   The input line has been checked and does not contain any errors.  The
*   password is in S, and the input line has been truncated to immediately
*   after the command keyword.
}
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_psw_k in rinfo.userset then goto done_cmd;
  string_copy (s, rinfo.password);
  end;
{
**********************
*
*   PORT n
}
6: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_port_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  if sys_error(stat) then goto err_parm;
  string_t_int (parm, rinfo.port_smtp, stat);
  end;
{
**********************
*
*   WAIT <INACTIVE or AFTER_ACTIVE or REDIAL> <time value>
}
7: begin
  if inhibit > 0 then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  if sys_error(stat) then goto err_parm;
  string_upcase (parm);
  string_tkpick80 (parm, 'INACTIVE AFTER_ACTIVE REDIAL', pick);
  case pick of

1:  begin                              {WAIT INACTIVE}
      if smtp_rfld_sinact_k in rinfo.userset then goto done_cmd;
      rinfo.sec_inact_done := parm_time(stat);
      end;

2:  begin                              {WAIT AFTER_ACTIVE}
      if smtp_rfld_sact_k in rinfo.userset then goto done_cmd;
      rinfo.sec_active_done := parm_time(stat);
      end;

3:  begin                              {WAIT REDIAL}
      if smtp_rfld_sredial_k in rinfo.userset then goto done_cmd;
      rinfo.sec_redial_wait := parm_time(stat);
      end;

otherwise                              {bad parameter to WAIT command}
    goto err_parm;
    end;
  end;
{
**********************
*
*   MAXDIALS n
}
8: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_mdial_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  if sys_error(stat) then goto err_parm;
  string_t_int (parm, rinfo.n_max_dial, stat);
  end;
{
**********************
*
*   DOMAIN name1 ... nameN
}
9: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_dom_k in rinfo.userset then goto done_cmd;
  rinfo.domains.len := 0;              {delete any previous domain information}

loop_dom:                              {back here to get each new domain name}
  string_token (ibuf, p, parm, stat);
  if string_eos(stat) then goto done_dom; {hit end of domain names list ?}
  if sys_error(stat) then goto err_parm;
  string_downcase (parm);
  string_append_token (rinfo.domains, parm); {add this domain name to end of list}
  goto loop_dom;                       {back to get next domain name}

done_dom:
  end;
{
**********************
*
*   METHOD
*     NONE, TURN, MAILQRUN, QSND, ETRNB, ETRN
}
10: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_meth_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  if sys_error(stat) then goto err_parm;
  string_upcase (parm);
  string_tkpick80 (parm, 'NONE TURN MAILQRUN QSND ETRNB ETRN', pick);
  case pick of
1:  rinfo.rqmeth := smtp_rqmeth_none_k; {METHOD NONE}
2:  rinfo.rqmeth := smtp_rqmeth_turn_k; {METHOD TURN}
3:  rinfo.rqmeth := smtp_rqmeth_mqrun_k; {METHOD MAILQRUN}
4:  rinfo.rqmeth := smtp_rqmeth_qsnd_k; {METHOD QSND}
5:  rinfo.rqmeth := smtp_rqmeth_etrn1_k; {basic ETRN}
6:  rinfo.rqmeth := smtp_rqmeth_etrn2_k; {full ETRN}
otherwise
    goto err_parm;
    end;
  end;
{
**********************
*
*   CONNECT yes/no
}
11: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_cnct_k in rinfo.userset then goto done_cmd;
  rinfo.connect := parm_yesno(stat);
  end;
{
**********************
*
*   BEGIN [NOT]
*     NAME <name>
*     ISP <name>
*     PHBOOK <name>
*     USER <name>
}
12: begin
  if inhibit > 0 then begin            {already within another inhibit BEGIN/END ?}
    inhibit := inhibit + 1;            {indicate one nested inhibit level deeper}
    goto done_cmd;                     {back to process next command}
    end;
  string_token (ibuf, p, parm, stat);
  if sys_error(stat) then goto err_parm;
  string_upcase (parm);
  notif := false;                      {init to NOT keyword not present}
  if string_equal (parm, not_str) then begin {found the NOT keyword ?}
    notif := true;                     {remember NOT keyword was here}
    string_token (ibuf, p, parm, stat); {advance to next token}
    if sys_error(stat) then goto err_parm;
    string_upcase (parm);
    end;
  string_tkpick80 (parm, 'NAME ISP PHBOOK USER', pick);
  case pick of

1:  begin                              {BEGIN NAME}
      string_token (ibuf, p, parm, stat);
      string_upcase (parm);
      tf := string_equal(parm, rinfo.name);
      end;

2:  begin                              {BEGIN ISP}
      string_token (ibuf, p, parm, stat);
      string_upcase (parm);
      tf := string_equal(parm, rinfo.isp);
      end;

3:  begin                              {BEGIN PHBOOK}
      string_token (ibuf, p, parm, stat);
      tf := string_equal(parm, rinfo.phbook_ent);
      end;

4:  begin                              {BEGIN USER}
      string_token (ibuf, p, parm, stat);
      tf := string_equal(parm, rinfo.user);
      end;

otherwise                              {bad parameter to WAIT command}
    goto err_parm;
    end;
  if sys_error(stat) then goto err_parm;
  if notif then begin                  {NOT keyword present, flip sense of compare ?}
    tf := not tf;
    end;
  if not tf then begin                 {test failed, block will be inhibited ?}
    inhibit := inhibit + 1;
    end;
  end;
{
**********************
*
*   END
}
13: begin
  inhibit := max(0, inhibit - 1);      {decrease inhibited block nesting level}
  end;
{
**********************
*
*   PHNUMBER <phone number>
}
14: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_phnum_k in rinfo.userset then goto done_cmd;
  rinfo.phnum.len := 0;                {init phone number string to empty}
  while p <= ibuf.len do begin         {scan remainder of line}
    c := ibuf.str[p];                  {fetch this character from line}
    if c = ' ' then goto next_phchar;  {ignore blanks}
    string_append1 (rinfo.phnum, c);   {add this char to end of phone number string}
next_phchar:                           {jump here to advance to next input char}
    p := p + 1;                        {advance to next character in input line}
    end;                               {back to process this new input character}
  end;
{
**********************
*
*   REMOTESYS <machine name>
}
15: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_mach_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  string_downcase (parm);
  string_copy (parm, rinfo.machine);
  end;
{
**********************
*
*   OUTQUEUE <queue name>
}
16: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_qname_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  string_downcase (parm);
  string_copy (parm, rinfo.qname);
  end;
{
**********************
*
*   ISPDOMAIN <name>
}
17: begin
  if inhibit > 0 then goto done_cmd;
  if smtp_rfld_domisp_k in rinfo.userset then goto done_cmd;
  string_token (ibuf, p, parm, stat);
  string_downcase (parm);
  string_copy (parm, rinfo.domain_isp);
  end;
{
**********************
*
*   Unrecognized command name.
}
otherwise
    sys_stat_set (email_subsys_k, email_stat_envcmd_bad_k, stat);
    sys_stat_parm_vstr (cmd, stat);
    sys_stat_parm_int (conn.lnum, stat);
    sys_stat_parm_vstr (conn.tnam, stat);
    goto abort1;
    end;

  ignored := false;                    {assume command was performed on fall thru}

done_cmd:                              {all done with current env file command}
  if sys_error(stat) then goto err_parm; {any error occurred in processing command ?}
  if                                   {this command was processed ?}
      ((inhibit_old = 0) or (inhibit = 0)) and
      (not ignored)
      then begin
    string_token (ibuf, p, parm, stat); {try to read one more token from input line}
    if not string_eos(stat) then goto extra_email; {found more email after command ?}
    end;
  if debug_smtp >= 9 then begin        {show this last command ?}
    if (inhibit = 0) and (inhibit_old = 0) and (not ignored)
      then write ('ENV>')
      else write ('   >');
    writeln (' ', ibuf.str:ibuf.len);
    end;
  goto loop_line;

extra_email:                           {jump here if found extra email on line}
  sys_stat_set (email_subsys_k, email_stat_envline_extra_k, stat);
  sys_stat_parm_int (conn.lnum, stat);
  sys_stat_parm_vstr (conn.tnam, stat);
  sys_stat_parm_vstr (parm, stat);
  goto abort1;
{
*   Some kind of error ocurred either in getting or processing a parameter
*   to the current command.  The parameter (if we got it) is in PARM.  STAT
*   may be set.
}
err_parm:
  if string_eos(stat) then begin       {error getting PARM from command line ?}
    sys_stat_set (email_subsys_k, email_stat_envparm_missing_k, stat);
    sys_stat_parm_vstr (cmd, stat);
    sys_stat_parm_int (conn.lnum, stat);
    sys_stat_parm_vstr (conn.tnam, stat);
    goto abort1;
    end;
  sys_stat_set (email_subsys_k, email_stat_envparm_err_k, stat);
  sys_stat_parm_vstr (parm, stat);
  sys_stat_parm_vstr (conn.tnam, stat);
  sys_stat_parm_int (conn.lnum, stat);
  goto abort1;
{
*   End of environment file set encountered.  STAT is indicating no error.
}
eof:
  file_close (conn);                   {close the environment file set}
  if smtp_rinfo_same (rinfo, rinfo_old) {no changes this pass ?}
    then return;                       {normal return with no error}
  goto loop_pass;                      {try another pass for things to stop changing}
{
*   Common error exits.  These are not the only possible error exits.
}
abort1:                                {env file set open, STAT already set}
  file_close(conn);                    {try to close file set}
  return;                              {return with the error}
  end;
{
********************************************************************
*
*   Function SMTP_RECEIVE_WAIT (RINFO)
*
*   Return TRUE if the incoming mail request method requires us to wait on
*   timeouts for the remote system to contact our SMTP server.
}
function smtp_receive_wait (           {check for must wait for incoming mail}
  in      rinfo: smtp_rinfo_t)         {info about remote system}
  :boolean;
  val_param;

begin
  case rinfo.rqmeth of                 {what is remote request method ?}

smtp_rqmeth_mqrun_k,                   {these methods require waiting on timeout}
smtp_rqmeth_etrn1_k,
smtp_rqmeth_etrn2_k,
smtp_rqmeth_qsnd_k: begin
      smtp_receive_wait := true;
      end;

otherwise                              {all other methods don't require timeout wait}
    smtp_receive_wait := false;
    end;

  end;
