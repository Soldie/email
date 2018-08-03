{   Subroutine SMTP_CLIENT_THREAD (D)
*
*   Handle all the interaction with one SMTP client.  This subroutine is
*   intended to be run in a separate thread.  The call argument D is assumed the
*   client descriptor passed by reference.  It will be closed before this
*   routine returns or exits.
}
module smtp_client_thread;
define smtp_client_thread;
%include 'email2.ins.pas';

procedure smtp_client_thread (         {thread routine for one SMTP client}
  in out  d: smtp_client_t);           {unique data for this client}

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

var
  cl_p: smtp_client_p_t;               {temp pointer to client descriptor}
  adr_inet: sys_inet_adr_node_t;       {scratch machine internet address}
  code: smtp_code_resp_t;              {SMTP command response code}
  conn_dir: file_conn_t;               {connection for reading top mail queue dir}
  qconn: smtp_qconn_read_t;            {connection to mail queue open for read}
  finfo: file_info_t;                  {info about a file}
  node: string_var256_t;               {internet node name}
  str: string_var8192_t;               {long scartch string}
  token: string_var32_t;               {short scratch string}
  outq: string_leafname_t;             {specific output queue name}
  qdir: string_treename_t;             {true name of Cognivision SMTPQ directory}
  ok: boolean;                         {TRUE on positive command response}
  turn: boolean;                       {TRUE if reversing send/recv roles}
  received: boolean;                   {at least one message was received and queued}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {Cognivision completion status code}

label
  loop_turn, next_turn, done_turn, turn_quit, done_client;

begin
  node.max := sizeof(node.str);        {init local var strings}
  str.max := sizeof(str.str);
  token.max := sizeof(token.str);
  qdir.max := sizeof(qdir.str);
  outq.max := sizeof(outq.str);

  sys_cognivis_dir ('smtpq'(0), qdir); {get full name of mail queues directory}
{
*   Process requests from the client.
}
  turn := false;                       {dis-allow role reversal}
  received := smtp_recv (d, turn, stat); {receive mail from this client}
  if sys_error(stat) then begin
    smtp_client_log_stat_str (d, stat, 'Error receiving mail from client.');
    goto done_client;
    end;

  if not turn then goto done_client;   {not switching roles so that we transmit now ?}
{
*   The client wants to reverse roles and receive mail.  We will send mail from
*   all queues where the remote system name translates into the client's IP
*   address.
}
  smtp_resp_get (d.conn, code, str, ok, stat); {get initial response code}
  if sys_error(stat) then goto done_client;
  if not ok then goto turn_quit;

  file_open_read_dir (qdir, conn_dir, stat); {open top queue directory for read}
  if sys_error(stat) then begin
    smtp_client_log_stat_str (d, stat, 'Error opening top queue directory.');
    goto turn_quit;
    end;

loop_turn:                             {back here each new queue directory}
  file_read_dir (                      {read next directory entry}
    conn_dir,                          {connection handle to directory}
    [file_iflag_type_k],               {we want to know file type}
    outq,                              {returned directory entry name}
    finfo,                             {returned info about this file}
    stat);
  if file_eof(stat) then goto done_turn; {hit end of queues directory ?}
  discard(                             {didn't get requested info isn't hard error}
    sys_stat_match (file_subsys_k, file_stat_info_partial_k, stat) );
  if sys_error(stat) then begin
    smtp_client_log_stat_str (d, stat, 'Error trying read next top queue directory entry.');
    goto done_turn;
    end;
  if                                   {this top dir entry not definately a dir ?}
      (not (file_iflag_type_k in finfo.flags)) or
      (finfo.ftype <> file_type_dir_k)
    then goto loop_turn;

  smtp_queue_read_open (               {open output mail queue for read}
    outq,                              {generic name of mail queue}
    d.mem_p^,                          {parent memory context to use}
    qconn,                             {returned connection to mail queue}
    stat);
  if sys_error(stat) then begin
    sys_msg_parm_vstr (msg_parm[1], outq);
    smtp_client_log_err (d, stat, 'email', 'smtp_queue_read_open', msg_parm, 1);
    goto loop_turn;
    end;

  if qconn.opts.remotesys.len <= 0 then goto next_turn; {no remote sys for this q ?}
  if qconn.opts.sendmail then goto next_turn; {don't use SMTP from this queue ?}
  file_inet_name_adr (                 {get IP address of remote system for this q}
    qconn.opts.remotesys,              {remote system name}
    adr_inet,                          {returned IP address}
    stat);
  if sys_error(stat) then begin
    sys_msg_parm_vstr (msg_parm[1], qconn.opts.remotesys);
    smtp_client_log_err (d, stat, 'email', 'smtp_get_remote_adr', msg_parm, 1);
    goto next_turn;
    end;
  if adr_inet <> d.adr then goto next_turn; {this queue not for this client ?}

  turn := false;                       {don't allow role reversal a second time}
  smtp_send (                          {send contents of mail queue via SMTP}
    d.conn,                            {connection handle to network stream}
    qconn,                             {handle to SMTP queue open for read}
    turn,                              {disallow role reversal}
    stat);
  if sys_error(stat) then begin
    sys_msg_parm_vstr (msg_parm[1], outq);
    smtp_client_log_err (d, stat, 'email', 'smtp_send_queue', msg_parm, 1);
    end;

next_turn:                             {jump here to send from next output queue}
  smtp_queue_read_close (qconn, stat); {close connection to mail queue}
  if sys_error(stat) then begin
    sys_msg_parm_vstr (msg_parm[1], outq);
    smtp_client_log_err (d, stat, 'email', 'smtp_queue_read_close', msg_parm, 1);
    end;
  goto loop_turn;                      {back to try next output queue}

done_turn:                             {done looking thru all the mail queues}
  file_close (conn_dir);               {close top queue directory}

turn_quit:                             {jump here to end TURNed SMTP session}
  inet_cstr_crlf_put ('QUIT'(0), d.conn, stat); {tell receiver we are done}
  if sys_error_check (stat, '', '', nil, 0)
    then goto done_client;             {terminate this client on error}

  sys_wait (1.0);                      {wait a short time for QUIT to arrive}
{
*   Done with this client.  Deallocate all state associated with this client
*   and return.  Returning will terminate the thread if this routine was run
*   in a separate thread.
}
done_client:                           {common code when done serving client}
  string_copy (d.inq, outq);           {save name of queue we dumped incoming mail into}
  cl_p := addr(d);                     {make pointer to client descriptor}
  smtp_client_close (cl_p);            {close client connection, dealloc resources}

  if received then begin               {at least one message received into queue ?}
    smtp_autosend (                    {process queue entries, if enabled}
      qdir,                            {name of top level queue directory}
      outq,                            {name of queue to deliver mail from}
      true,                            {wait for subordinate processes to complete}
      stat);
    if sys_error(stat) then begin
      sys_msg_parm_vstr (msg_parm[1], outq);
      smtp_client_wrlock;
      sys_error_print (stat, 'email', 'smtp_autosend', msg_parm, 1);
      smtp_client_wrunlock;
      end;
    end;
  end;
