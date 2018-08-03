{   Module of routines that deal with the various methods used to trigger
*   remote systems to send us email.
}
module smtp_rqmeth;
define smtp_request_mail;
%include 'email2.ins.pas';

procedure smtp_request_mail_mqrun (    {request mail using MAILQRUN method}
  in      rinfo: smtp_rinfo_t;         {info about remote system}
  out     stat: sys_err_t);
  val_param; forward;

procedure smtp_request_mail_qsnd (     {request mail using QSND method}
  in      rinfo: smtp_rinfo_t;         {info about remote system}
  out     stat: sys_err_t);
  val_param; forward;

procedure smtp_request_mail_etrn (     {request mail using ETRN method}
  in      rinfo: smtp_rinfo_t;         {info about remote system}
  out     stat: sys_err_t);
  val_param; forward;
{
********************************************************************
*
*   Subroutine SMTP_REQUEST_MAIL (RINFO, STAT)
*
*   Perform whatever action is required to request all mail queued for us
*   by a remote system.  RINFO is the information about the remote system.
*   We must already be connected to the remote system, but have not yet
*   initiated contact with its mailer.  Some methods also require that we
*   have an active SMTP server that the remote system can contact with
*   our mail.
*
*   No action is taken if the method of requesting mail from the remote
*   system doesn't require anything to be done at this time.
*
*   This routine figures out if anything needs to be done, then calls the
*   routine for the specific method.
}
procedure smtp_request_mail (          {request remote system to send us mail}
  in      rinfo: smtp_rinfo_t;         {remote sys info, must already be connected}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;

begin
  sys_error_none (stat);               {init to no error occurred}
  case rinfo.rqmeth of                 {what is the remote mail request method ?}

smtp_rqmeth_none_k,                    {nothing needs to be down at this time}
smtp_rqmeth_turn_k: ;

smtp_rqmeth_mqrun_k: begin             {MAILQRUN method, like Ultranet}
      smtp_request_mail_mqrun (rinfo, stat);
      end;

smtp_rqmeth_qsnd_k: begin              {SMTP QSND command, like Net1Plus}
      smtp_request_mail_qsnd (rinfo, stat);
      end;

smtp_rqmeth_etrn2_k: begin             {full SMTP ETRN command, see RFC 1985}
      smtp_request_mail_etrn (rinfo, stat);
      end;

otherwise
    sys_msg_parm_str (msg_parm[1], 'SMTP_REQUEST_MAIL');
    sys_msg_parm_int (msg_parm[2], ord(rinfo.rqmeth));
    sys_message_bomb ('email', 'email_rqmeth_unimp', msg_parm, 2);
    end;
  end;
{
********************************************************************
*
*   Subroutine SMTP_REQUEST_MAIL_QSND (RINFO, STAT)
*
*   Request mail from the remote system using the QSND method.  The steps
*   of this method are:
*
*   1 - Connect to remote SMTP server.
*
*   2 - Send the command "QSND <domain name>", to trigger the remote system
*       to try to send all mail to the indicated domain.  Note that the
*       QSND command doesn't show up in the HELP list.
*
*   3 - Disconnect from the SMTP server in the usual way.
*
*   This method is know to be used by the following ISPs:
*     Net1Plus
}
procedure smtp_request_mail_qsnd (     {request mail using QSND method}
  in      rinfo: smtp_rinfo_t;         {info about remote system}
  out     stat: sys_err_t);
  val_param;

var
  conn: file_conn_t;                   {handle to remote SMTP server connection}
  node: sys_inet_adr_node_t;           {internet address of remote machine}
  buf: string_var8192_t;               {one line in/out buffer}
  p: string_index_t;                   {domain names parse index}
  dname: string_var256_t;              {one domain name parsed from the list}

label
  loop_dname, done_dnames, abort;

begin
  buf.max := sizeof(buf.str);          {init local var strings}
  dname.max := sizeof(dname.str);
{
*   Open a connection to the remote SMTP server.
}
  file_inet_name_adr (                 {convert remote machine name to IP address}
    rinfo.machine,                     {machine name}
    node,                              {returned IP address of machine}
    stat);
  if sys_error(stat) then return;

  file_open_inetstr (                  {try to open connection to SMTP server}
    node,                              {address of machine to connect to}
    rinfo.port_smtp,                   {port to talk to on remote machine}
    conn,                              {returned handle to inet stream connection}
    stat);
  if sys_error(stat) then return;

  smtp_resp_check (conn, stat);        {read and check initial greeting response}
  if sys_error(stat) then goto abort;
{
*   Send the QSND commands.  There will be one command for each domain name
*   we are supposed to receive mail for.
}
  p := 1;                              {init domain names parse index}

loop_dname:                            {back here for each new domain name from list}
  string_token (rinfo.domains, p, dname, stat);
  if string_eos(stat) then goto done_dnames;
  if sys_error(stat) then goto abort;
  string_vstring (buf, 'QSND '(0), -1); {init command string with keyword}
  string_append (buf, dname);          {append domain name}
  inet_vstr_crlf_put (buf, conn, stat); {send command string to server}
  if sys_error(stat) then goto abort;

  smtp_resp_check (conn, stat);        {read and check server response}
  if sys_error(stat) then goto abort;
  goto loop_dname;                     {back to handle next receiving domain name}

done_dnames:                           {done handling each domain name}
{
*   Disconnect from the remote server.
}
  inet_cstr_crlf_put ('QUIT'(0), conn, stat); {send QUIT command}
  if sys_error(stat) then goto abort;
  smtp_resp_check (conn, stat);        {read and check server response}
  sys_error_none (stat);               {we don't care if QUIT command didn't work}

  file_close (conn);                   {close connection to remote server}
  return;                              {normal return}
{
*   Error returns.
}
abort:                                 {connection to remote server open, STAT set}
  file_close (conn);                   {try to close remote server connection}
  end;
{
********************************************************************
*
*   Subroutine SMTP_REQUEST_MAIL_MQRUN (RINFO, STAT)
*
*   Request mail from the remote system using the QSND method.  The steps
*   of this method are:
*
*   1 - Send an email message to "mailqrun@ultranet.com".  The message
*       needs to contain only the single line "from: <anybody>@<domain>".
*       The <anybody> part of the FROM address is ignored.  We use "postmaster".
*       The <domain> part is the name of the domain to send queued mail
*       for.
*
*   This method is know to be used by the following ISPs:
*     Ultranet
}
procedure smtp_request_mail_mqrun (    {request mail using MAILQRUN method}
  in      rinfo: smtp_rinfo_t;         {info about remote system}
  out     stat: sys_err_t);
  val_param;

var
  conn: file_conn_t;                   {handle to remote SMTP server connection}
  node: sys_inet_adr_node_t;           {internet address of remote machine}
  buf: string_var8192_t;               {one line in/out buffer}
  s: string_var80_t;                   {scratch string}
  p: string_index_t;                   {domain names parse index}
  dname: string_var256_t;              {one domain name parsed from the list}

label
  loop_dname, done_dnames, abort;

begin
  buf.max := sizeof(buf.str);          {init local var string}
  s.max := sizeof(s.str);
{
*   Open a connection to the remote SMTP server.
}
  file_inet_name_adr (                 {convert remote machine name to IP address}
    rinfo.machine,                     {machine name}
    node,                              {returned IP address of machine}
    stat);
  if sys_error(stat) then return;

  file_open_inetstr (                  {try to open connection to SMTP server}
    node,                              {address of machine to connect to}
    rinfo.port_smtp,                   {port to talk to on remote machine}
    conn,                              {returned handle to inet stream connection}
    stat);
  if sys_error(stat) then return;

  smtp_resp_check (conn, stat);        {read and check initial greeting response}
  if sys_error(stat) then goto abort;
{
*   Send the message "from: postmaster@<domain>" to "mailqrun@<domain_isp>"
*   for each domain we receive mail for.
}
  p := 1;                              {init domain names parse index}

loop_dname:                            {once for each domain name in the list}
  string_token (rinfo.domains, p, dname, stat); {get this domain name in DNAME}
  if string_eos(stat) then goto done_dnames;
  if sys_error(stat) then goto abort;

  string_vstring (buf, 'HELO '(0), -1);
  sys_node_name (s);
  string_append (buf, s);
  string_append1 (buf, '.');
  string_append (buf, dname);
  inet_vstr_crlf_put (buf, conn, stat); {send HELO command}
  if sys_error(stat) then goto abort;
  smtp_resp_check (conn, stat);
  if sys_error(stat) then goto abort;

  string_vstring (buf, 'MAIL FROM:<postmaster@'(0), -1);
  string_append (buf, dname);
  string_append1 (buf, '>');
  inet_vstr_crlf_put (buf, conn, stat); {send MAIL FROM command}
  if sys_error(stat) then goto abort;
  smtp_resp_check (conn, stat);
  if sys_error(stat) then goto abort;

  string_vstring (buf, 'RCPT TO:<mailqrun@'(0), -1);
  string_append (buf, rinfo.domain_isp);
  string_append1 (buf, '>');
  inet_vstr_crlf_put (buf, conn, stat); {send RCPT TO command}
  if sys_error(stat) then goto abort;
  smtp_resp_check (conn, stat);
  if sys_error(stat) then goto abort;

  inet_cstr_crlf_put ('DATA'(0), conn, stat); {send DATA command to start msg body}
  smtp_resp_check (conn, stat);
  if sys_error(stat) then goto abort;

  string_vstring (buf, 'from: postmaster@'(0), -1);
  string_append (buf, dname);
  inet_vstr_crlf_put (buf, conn, stat); {send mail message body line}
  if sys_error(stat) then goto abort;

  inet_cstr_crlf_put ('.'(0), conn, stat); {send line to indicate message body end}
  smtp_resp_check (conn, stat);
  if sys_error(stat) then goto abort;
  goto loop_dname;                     {back for next domain name in list}

done_dnames:                           {done handling all domain names in the list}
{
*   Disconnect from the remote server.
}
  inet_cstr_crlf_put ('QUIT'(0), conn, stat); {send QUIT command}
  if sys_error(stat) then goto abort;
  smtp_resp_check (conn, stat);        {read and check server response}
  sys_error_none (stat);               {we don't care if QUIT command didn't work}

  file_close (conn);                   {close connection to remote server}
  return;                              {normal return}
{
*   Error returns.
}
abort:                                 {connection to remote server open, STAT set}
  file_close (conn);                   {try to close remote server connection}
  end;
{
********************************************************************
*
*   Subroutine SMTP_REQUEST_MAIL_ETRN (RINFO, STAT)
*
*   Request mail from the remote system using the ETRN command as specified
*   in RFC 1985.  The details of this method are:
*
*   1 - Connect to remote SMTP server.
*
*   2 - Send the command "ETRN @<domain name>", to trigger the remote system
*       to try to send all mail to the indicated domain.
*
*   3 - Disconnect from the SMTP server in the usual way.
}
procedure smtp_request_mail_etrn (     {request mail using ETRN method}
  in      rinfo: smtp_rinfo_t;         {info about remote system}
  out     stat: sys_err_t);
  val_param;

var
  conn: file_conn_t;                   {handle to remote SMTP server connection}
  node: sys_inet_adr_node_t;           {internet address of remote machine}
  buf: string_var8192_t;               {one line in/out buffer}
  s: string_var80_t;                   {scratch string}
  p: string_index_t;                   {domain names parse index}
  dname: string_var256_t;              {one domain name parsed from the list}

label
  loop_dname, done_dnames, abort;

begin
  buf.max := sizeof(buf.str);          {init local var strings}
  s.max := sizeof(s.str);
  dname.max := sizeof(dname.str);
{
*   Open a connection to the remote SMTP server.
}
  file_inet_name_adr (                 {convert remote machine name to IP address}
    rinfo.machine,                     {machine name}
    node,                              {returned IP address of machine}
    stat);
  if sys_error(stat) then return;

  file_open_inetstr (                  {try to open connection to SMTP server}
    node,                              {address of machine to connect to}
    rinfo.port_smtp,                   {port to talk to on remote machine}
    conn,                              {returned handle to inet stream connection}
    stat);
  if sys_error(stat) then return;

  smtp_resp_check (conn, stat);        {read and check initial greeting response}
  if sys_error(stat) then goto abort;

  string_vstring (buf, 'HELO '(0), -1); {send HELO command}
  sys_node_name (s);
  string_append (buf, s);
  string_append1 (buf, '.');
  string_append (buf, dname);
  inet_vstr_crlf_put (buf, conn, stat); {send HELO command}
  if sys_error(stat) then goto abort;
  smtp_resp_check (conn, stat);
  if sys_error(stat) then goto abort;
{
*   Send the ETRN commands.  There will be one command for each domain name
*   we are supposed to receive mail for.
}
  p := 1;                              {init domain names parse index}

loop_dname:                            {back here for each new domain name from list}
  string_token (rinfo.domains, p, dname, stat); {get this domain name in DNAME}
  if string_eos(stat) then goto done_dnames;
  if sys_error(stat) then goto abort;

  string_vstring (buf, 'ETRN @'(0), -1); {init command string with keyword}
  string_append (buf, dname);          {append domain name}
  inet_vstr_crlf_put (buf, conn, stat); {send command string to server}
  if sys_error(stat) then goto abort;

  smtp_resp_check (conn, stat);        {read and check server response}
  if sys_error(stat) then goto abort;
  goto loop_dname;                     {back to handle next receiving domain name}

done_dnames:                           {done handling each domain name}
{
*   Disconnect from the remote server.
}
  inet_cstr_crlf_put ('QUIT'(0), conn, stat); {send QUIT command}
  if sys_error(stat) then goto abort;
  smtp_resp_check (conn, stat);        {read and check server response}
  sys_error_none (stat);               {we don't care if QUIT command didn't work}

  file_close (conn);                   {close connection to remote server}
  return;                              {normal return}
{
*   Error returns.
}
abort:                                 {connection to remote server open, STAT set}
  file_close (conn);                   {try to close remote server connection}
  end;
