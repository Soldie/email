{   Subroutine SMTP_SEND (CONN, QCONN, TURN, STAT)
*
*   Perform SMTP protocol in transmitter mode.  We get here immediately after
*   the initial server response from opening the connection or from a TURN
*   command.
*
*   CONN is the connection handle to the open internet stream.
*
*   QCONN is the connection handle to the SMTP queue open for read.  We will
*   try to send all entries in the queue to the remote system.  We will also
*   try to delete all entries that were successfully transmitted.  QCONN will
*   be left open, but should be exhausted.
*
*   TURN is set TRUE by the caller if we are to issue a TURN command when
*   done sending all our mail.  TURN is returned TRUE only if we sent a TURN
*   command and it was successfully acknoledged.
}
module smtp_send;
define smtp_send;
%include 'email2.ins.pas';

const
  nshow_err_k = 200;                   {number original message lines in bounce}

var
  str_from: string_var4_t :=
    [str := 'FROM', len := 4, max := sizeof(str_from.str)];

procedure smtp_send (                  {send all mail in queue to remote system}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  in out  qconn: smtp_qconn_read_t;    {handle to SMTP queue open for read}
  in out  turn: boolean;               {issue TURN at end on TRUE, TRUE if TURNed}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  code: smtp_code_resp_t;              {standard 3 digit SMTP command response code}
  serv_adr: sys_inet_adr_node_t;       {address of remote server node}
  serv_dot: string_var32_t;            {server address as dot notation string}
  serv_port: sys_inet_port_id_t;       {number of server port on remote node}
  cmd: string_var8192_t;               {SMTP command with parameters}
  info: string_var8192_t;              {SMTP command response text}
  errmsg: string_var256_t;             {error message string}
  list_adr_p: string_list_p_t;         {pointer to list of recipient addresses}
  mconn_p: file_conn_p_t;              {handle to open mail message file connection}
  list_retpath: string_list_t;         {mail return path list}
  adr_from: string_var256_t;           {mail originator address, lower case}
  pick: sys_int_machine_t;             {number of token picked from list}
  n_rcpt_ok: sys_int_machine_t;        {number of accepted recipients this msg}
  p: string_index_t;                   {parse index}
  qrclose: smtp_qrclose_t;             {flags for closing queue entry}
  tnam, tnam2: string_treename_t;      {scratch file treename}
  lnam: string_leafname_t;             {scratch file leafname}
  tk: string_var32_t;                  {scratch token}
  conne: file_conn_t;                  {bounce error message file name}
  eopen: boolean;                      {bounce error message file is open}
  ok: boolean;                         {TRUE if command response positive}
  err: boolean;                        {one or more errors in bounce file}
  msg_sent: boolean;                   {TRUE if current message successfully sent}
  stat2: sys_err_t;                    {used to avoid corrupting STAT}

label
  loop_msg, loop_retpath, loop_received, done_retpath,
  loop_send, done_send, next_msg, done_msgs, abort2, abort1;
{
*****************************************************************
*
*   Local subroutine SHOW_RESP
*
*   Print the error message string ERRMSG, followed by the response from the
*   remote system.  The three digit response code is in CODE, and the informational
*   text string is in INFO.  This routine is called on unexpected response
*   to help diagnose the problem.
}
procedure show_resp;

begin
  writeln (errmsg.str:errmsg.len);     {show caller's error message}
  writeln ('  ', code:3, ': ', info.str:info.len); {show code and info string}
  sys_stat_set (email_subsys_k, email_stat_smtp_err_k, stat); {general SMTP error}
  end;
{
*****************************************************************
*
*   Local subroutine WERR (S, STAT)
*
*   Write the string S as a new line to the bounce message error file.
}
procedure werr (                       {write line to bounce message error file}
  in      s: univ string_var_arg_t;    {the line to write}
  out     stat: sys_err_t);            {returned completion status}
  val_param; internal;

begin
  file_write_text (s, conne, stat);
  end;
{
*****************************************************************
*
*   Local subroutine SERROR (STAT)
*
*   Add an error message to the bounce message file.  The error is assumed
*   to be a NACK response from the server.  CMD is the command sent to
*   the server, CODE is the status code returned by the server, and
*   INFO is the error text returned by the server.
*
*   The ERR flag will be set to indicate at least one error message is
*   in the bounce message file.
*
*   The bounce message file must be open, although this is not checked.
}
procedure serror (                     {write whole message to bounce error file}
  out     stat: sys_err_t);            {returned completion status}
  val_param; internal;

var
  buf: string_var132_t;                {one line output buffer}

begin
  buf.max := size_char(buf.str);       {init local var string}

  err := true;                         {indicate at least one message in bounce file}

  buf.len := 0;                        {write blank line}
  werr (buf, stat);
  if sys_error(stat) then return;

  werr (cmd, stat);                    {write the command sent to the server}
  if sys_error(stat) then return;

  string_vstring (buf, code, size_char(code));
  string_appends (buf, ': '(0));
  string_append (buf, info);           {server text response}
  werr (buf, stat);                    {write the line to the bounce file}
  end;
{
*****************************************************************
*
*   Local subroutine SEND_BOUNCE
*
*   Send an error bounce message to the sender.  The bounce message
*   file must be open, and will be closed and deleted on success.
*
*   To avoid an infinite mail loop, the bounce message is not sent if
*   the message that caused the bounce was sent from the same address
*   that the bounce message would be sent from.
}
procedure send_bounce;                 {send error bounce message to sender}

var
  i: sys_int_machine_t;                {scratch integer and loop counter}
  tf: boolean;                         {TRUE/FALSE status from subordinate process}
  exstat: sys_sys_exstat_t;            {exit status of subordinate process}
  buf: string_var8192_t;               {one line output buffer and command line}
  tk: string_var32_t;                  {scratch token}
  stat: sys_err_t;                     {completion status}

begin
  buf.max := size_char(buf.str);       {init local var strings}
  tk.max := size_char(tk.str);

  if qconn.opts.bouncefrom.len <= 0    {bounce messages inhibited ?}
    then return;
  if string_equal (adr_from, qconn.opts.bouncefrom) {don't bounce to robot address}
    then return;
{
*   Complete the bounce message file and close it.
}
  buf.len := 0;                        {blank line after error messages}
  werr (buf, stat);
  if sys_error_check (stat, '', '', nil, 0) then return;

  string_vstring (buf,
    '----------------------------------------------------------------------'(0), -1);
  werr (buf, stat);
  if sys_error_check (stat, '', '', nil, 0) then return;

  buf.len := 0;                        {blank line before undelivered message}
  werr (buf, stat);
  if sys_error_check (stat, '', '', nil, 0) then return;

  file_pos_start (mconn_p^, stat);     {re-position to start of file}
  if sys_error_check (stat, '', '', nil, 0) then return;
  for i := 1 to nshow_err_k do begin   {once for each line to copy to bounce file}
    file_read_text (mconn_p^, buf, stat); {read next message line from file}
    if file_eof(stat) then exit;       {end of file, stop copying ?}
    if sys_error_check (stat, '', '', nil, 0) then return;
    werr (buf, stat);                  {write this line to the bounce message file}
    if sys_error_check (stat, '', '', nil, 0) then return;
    end;                               {back to do next line}
  file_close (conne);                  {close the bounce message file}
  eopen := false;                      {indicate bounce file no longer open}
{
*   Run the SMTP program in a separate process to put the bounce message
*   into the default input queue.  The command line will be:
*
*   SMTP -ENQUEUE -MSG fnam -DEBUG dbglevel -TO from_adr
}
  string_copy (qconn.opts.smtp_cmd, buf); {init command line with command name}
  string_appends (buf, ' -enqueue -msg '(0));
  string_append (buf, conne.tnam);     {bounce message file name}
  string_appends (buf, ' -debug '(0));
  string_f_int (tk, debug_smtp);
  string_append (buf, tk);             {debug level}
  string_appends (buf, ' -to '(0));
  string_append (buf, adr_from);       {address to send the bounce message to}

  if debug_smtp >= 5 then begin
    sys_thread_lock_enter_all;         {single threaded code}
    writeln ('Running: ', buf.str:buf.len);
    sys_thread_lock_leave_all;
    end;

  sys_run_wait_stdsame (buf, tf, exstat, stat); {run command to send bounce message}
  file_delete_name (conne.tnam, stat); {try to delete the bounce message file}
  end;
{
*****************************************************************
*
*   Local subroutine ERR_CLOSE
*
*   Close the bounce error message file and delete it, if it is open.
*   This routine should only be called when the associated queue
*   entry is open.
}
procedure err_close;                   {close and delete bounce message file}

var
  stat: sys_err_t;

begin
  if not eopen then return;            {no bounce message file is open ?}
  eopen := false;                      {the file will be closed}

  file_close (conne);                  {close the file}
  file_delete_name (conne.tnam, stat); {try to delete the file}
  end;
{
*****************************************************************
*
*   Local subroutine AUTHORIZE (STAT)
*
*   The remote server requires authentication of the client before accepting
*   any mail.  We will attempt authorization by using the AUTH command
*   of ESMTP.  Note that EHLO should be used instead of HELO when ESMTP
*   commands are used.  The AUTH command is describe in RFC 2554.
*
*   The global variables CODE, INFO, and ERRMSG are trashed.
}
procedure authorize (                  {authorize ourselves to the remote server}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  cmd: string_var256_t;                {SMTP command buffer}
  prompt: string_var80_t;              {challenge prompt from server, clear text}
  pick: sys_int_machine_t;             {number of keyword picked from list}
  ok: boolean;                         {TRUE if command response positive}

label
  loop_chal, err;

begin
  cmd.max := size_char(cmd.str);       {init local var strings}
  prompt.max := size_char(prompt.str);
{
*   Send the EHLO command.
}
  string_vstring (cmd, 'EHLO '(0), -1); {build command}
  string_append (cmd, qconn.opts.localsys);
  inet_vstr_crlf_put (cmd, conn, stat); {send command}
  if sys_error(stat) then return;

  smtp_resp_get (conn, code, info, ok, stat); {get command response}
  if not ok then begin
    string_vstring (errmsg, 'EHLO error:'(0), -1);
    show_resp;
    goto err;
    end;
{
*   The EHLO command has been sent and a successful response received.
*   The EHLO command response reports the various ESMTP extensions that
*   this server supports.  A full featured SMTP client would examine this
*   list to see which authorization types the server supports.  However,
*   we only know how to use the AUTH LOGIN command, so we send it and if
*   the server doesn't support it, it will fail.  Oh well.
}
  string_vstring (cmd, 'AUTH LOGIN'(0), -1);
  inet_vstr_crlf_put (cmd, conn, stat); {send AUTH LOGIN command}
  if sys_error(stat) then return;

loop_chal:                             {back here for each new challenge}
  smtp_resp_get (conn, code, info, ok, stat); {get command response}
  if not ok then begin
    string_vstring (errmsg, 'AUTH LOGIN error:'(0), -1);
    show_resp;
    goto err;
    end;
  if code[1] = '2' then return;        {AUTH command completed successfully ?}
{
*   Assume the response is a challenge to us.  Such challenges are sent
*   BASE64 encoded.
}
  string_f_base64 (info, prompt);      {make clear text challenge prompt}
  string_unpad (prompt);               {delete any trailing spaces}
  string_upcase (prompt);              {make case-insensitive for keyword matching}
  string_tkpick80 (prompt,             {pick challenge prompt from list}
    'USERNAME: PASSWORD:',
    pick);
  case pick of                         {which challenge is it ?}
{
*   USERNAME:
}
1: begin
  string_t_base64 (qconn.opts.remoteuser, cmd); {make encoded challenge response}
  inet_vstr_crlf_put (cmd, conn, stat); {send it}
  end;
{
*   PASSWORD:
}
2: begin
  string_t_base64 (qconn.opts.remotepswd, cmd); {make encoded challenge response}
  inet_vstr_crlf_put (cmd, conn, stat); {send it}
  end;
{
*   Unexpected challenge prompt received.
}
otherwise
    string_vstring (errmsg, 'Unexpected challenge prompt received:'(0), -1);
    show_resp;
    goto err;
    end;

  goto loop_chal;                      {back to get next challenge prompt}

err:                                   {jump here to return with generic error}
  sys_stat_set (email_subsys_k, email_stat_smtp_err_k, stat); {general SMTP error}
  end;
{
*****************************************************************
*
*   Start of main routine.
}
begin
  cmd.max := sizeof(cmd.str);          {init local var strings}
  info.max := sizeof(info.str);
  errmsg.max := sizeof(errmsg.str);
  adr_from.max := sizeof(adr_from.str);
  tnam.max := sizeof(tnam.str);
  tnam2.max := sizeof(tnam2.str);
  lnam.max := sizeof(lnam.str);
  serv_dot.max := sizeof(serv_dot.str);
  tk.max := sizeof(tk.str);

  string_list_init (list_retpath, util_top_mem_context); {init return path list}

  file_inetstr_info_remote (conn, serv_adr, serv_port, stat); {get server info}
  if sys_error(stat) then goto abort1;
  string_f_inetadr (serv_dot, serv_adr); {make dot-notation server address}
{
*   Send the HELO or EHLO commands.  EHLO is only sent if we will need
*   to authorize ourselves to this server.  This is indicated if the
*   REMOTEUSER or REMOTEPSWD fields of the queue options are not empty.
}
  if
      (qconn.opts.remoteuser.len <= 0) and {no remote user name required}
      (qconn.opts.remotepswd.len <= 0) {no password required}
    then begin                         {no authorization required, use normal HELO}
      string_vstring (cmd, 'HELO '(0), -1); {build command}
      string_append (cmd, qconn.opts.localsys);
      inet_vstr_crlf_put (cmd, conn, stat); {send command}
      if sys_error(stat) then goto abort1;
      smtp_resp_get (conn, code, info, ok, stat); {get command response}
      if not ok then begin
        string_vstring (errmsg, 'HELO error:'(0), -1);
        show_resp;
        goto abort1;
        end;
      end
    else begin                         {explicit authorization is required}
      authorize (stat);                {perform the authorization}
      if sys_error(stat) then goto abort1;
      end
    ;
{
****************************************
*
*   Main loop.  Back here for each new mail message found in the queue.
}
loop_msg:
  msg_sent := false;                   {init to this message not sent}
  eopen := false;                      {init to bounce message error file not open}
  err := false;                        {init to no errors in bounce file}
  smtp_queue_read_ent (qconn, list_adr_p, mconn_p, stat); {read next queue entry}
  if sys_stat_match (email_subsys_k, email_stat_queue_end_k, stat) {end of queue ?}
    then goto done_msgs;
  if sys_error(stat) then goto abort2;
{
*   Read thru the mail message to determine the mail return path.
}
  string_list_pos_start (list_retpath); {init return path to the machine we are on}
  string_list_trunc (list_retpath);
  list_retpath.size := qconn.opts.localsys.len;
  string_list_line_add (list_retpath);
  string_copy (qconn.opts.localsys, list_retpath.str_p^);

  adr_from.len := 0;                   {init to no FROM address found}

loop_retpath:                          {back here to read each new message line}
  file_read_text (mconn_p^, info, stat); {read next mail message line}
  if file_eof(stat) then goto done_retpath; {hit end of mail message file ?}
  if sys_error(stat) then goto next_msg;
  p := 1;                              {init mail line parse index}
  string_token (info, p, cmd, stat);   {extract header keyword, if any}
  if string_eos(stat) then goto done_retpath; {hit end of mail message header ?}
  if sys_error(stat) then goto loop_retpath; {ignore on err, like open quote, etc.}
  if (cmd.len <= 1) or (cmd.str[cmd.len] <> ':') {not a header line keyword ?}
    then goto loop_retpath;            {ignore this line}
  cmd.len := cmd.len - 1;              {truncate the ":" after keyword name}
  string_upcase (cmd);                 {make upper case for keyword matching}
  string_tkpick80 (cmd,                {pick keyword name from list}
    'RECEIVED FROM',
    pick);
  case pick of                         {which keyword is it ?}
{
*   Mail header keyword RECEIVED.
}
1: begin
loop_received:                         {back here each new token until FROM}
  string_token (info, p, cmd, stat);   {get next token on line}
  if sys_error(stat) then goto loop_retpath; {ignore line on error}
  string_upcase (cmd);
  if not string_equal (cmd, str_from)  {this isn't FROM keyword ?}
    then goto loop_received;
  string_token (info, p, cmd, stat);   {get machine name token}
  if sys_error(stat) then goto loop_retpath; {ignore line on error}
  if cmd.len <= 0 then goto loop_retpath;
  list_retpath.size := cmd.len;        {add this machine name to return path list}
  string_list_line_add (list_retpath);
  string_copy (cmd, list_retpath.str_p^);
  end;
{
*   Mail header keyword FROM.
}
2: begin
  string_substr (info, p, info.len, cmd); {extract string after FROM: keyword}
  email_adr_extract (cmd, adr_from, errmsg); {get raw address in ADR_FROM}
  string_downcase (adr_from);
  end;

    end;                               {end of special handling keyword cases}
  goto loop_retpath;                   {back for next header line in mail message}

done_retpath:                          {done reading mail message header}
{
*   The return path for this mail message is in LIST_RETPATH.  This is the
*   list of machines from last to first that relayed this mail message.
*   The sender's address is in ADR_FROM.
}
  if debug_smtp >= 10 then begin
    writeln ('List of machines from last to first:');
    string_list_pos_abs (list_retpath, 1);
    while list_retpath.str_p <> nil do begin
      writeln ('  ', list_retpath.str_p^.str:list_retpath.str_p^.len);
      string_list_pos_rel (list_retpath, 1);
      end;
    writeln;
    end;
{
*   Open and initialize the bounce mail message file.
}
  string_pathname_split (mconn_p^.tnam, tnam, lnam); {get message file dir and name}
  lnam.str[1] := 'e';                  {change to error file leafname}
  string_pathname_join (tnam, lnam, tnam2); {make error file full treename}
  file_open_write_text (tnam2, '', conne, stat); {open error output file}
  if sys_error(stat) then goto abort2;
  eopen := true;                       {indicate bounce message file is now open}

  string_vstring (info, 'To: '(0), -1);
  string_append (info, adr_from);
  werr (info, stat);
  if sys_error(stat) then goto abort2;

  string_vstring (info, 'From: '(0), -1);
  string_append (info, qconn.opts.bouncefrom);
  werr (info, stat);
  if sys_error(stat) then goto abort2;

  string_vstring (info, 'Subject: Mail delivery error'(0), -1);
  werr (info, stat);
  if sys_error(stat) then goto abort2;

  info.len := 0;                       {write blank line to end email header}
  werr (info, stat);
  if sys_error(stat) then goto abort2;

  string_vstring (info,
    'A mail message from you was not delivered to all its recipients.'(0), -1);
  werr (info, stat);
  if sys_error(stat) then goto abort2;

  string_vstring (info,
    'Errors were received from the SMTP server on port '(0), -1);
  string_f_int (tk, serv_port);
  string_append (info, tk);
  string_appends (info, ' of'(0));
  werr (info, stat);
  if sys_error(stat) then goto abort2;

  string_vstring (info, 'machine '(0), -1);
  string_append (info, serv_dot);
  if qconn.opts.remotesys.len > 0 then begin {server name is available ?}
    string_appends (info, ' ('(0));
    string_append (info, qconn.opts.remotesys);
    string_appends (info, ')'(0));
    end;
  string_append1 (info, '.');
  werr (info, stat);
  if sys_error(stat) then goto abort2;

  string_vstring (info,
    'Below is a list of the commands sent to the server and its error'(0), -1);
  werr (info, stat);
  if sys_error(stat) then goto abort2;

  string_vstring (info,
    'responses, followed by the first '(0), -1);
  string_f_int (tk, nshow_err_k);
  string_append (info, tk);
  string_appends (info,
    ' lines of your message.'(0));
  werr (info, stat);
  if sys_error(stat) then goto abort2;
{
*   Send command "MAIL FROM:<reverse path>"
}
  string_vstring (cmd, 'MAIL FROM:<'(0), -1);

(*
**   This section is commented out, even though it produces the correct
**   reverse path as described in RFC 821.  Unfortunately, some ISPs are
**   trying to detect spam mail, and are not parsing the reverse path
**   correctly.  Any message with a reverse path with more than one
**   machine is considered spam and refused.  We therefore always report
**   the reverse path as if the message had originated here, still using
**   the sender's full return address as the originating mail address.
**   Bounced messages should still work as long as we know how to pass
**   on a message addressed to the sender.
**
**   string_list_pos_abs (list_retpath, 1); {init to first entry in return path list}
**   while list_retpath.str_p <> nil do begin {once for each return path list entry}
**     if list_retpath.curr > 1 then begin {this is not first machine in list ?}
**       string_append1 (cmd, ', ');
**       end;
**     string_append1 (cmd, '@');
**     string_append (cmd, list_retpath.str_p^);
**     string_list_pos_rel (list_retpath, 1); {advance to next entry in ret path list}
**     end;                               {back to process this new entry}
**   if list_retpath.n >= 1 then begin    {at least one machine in return path list ?}
**     string_append1 (cmd, ':');
**     end;
**
**   End of hack to get around ISP spam detection bugs.
*)

(*
**   Additional hack to get around ISP spam detection bugs.  Some ISPs
**   now refuse any reverse path that isn't just a normal email address
**   that doesn't contain "source routing".  This section is commented
**   out to avoid sending even this machine's address.
**
**   string_append1 (cmd, '@');        {only machine in reverse path is this one}
**   string_append (cmd, qconn.opts.localsys); {name of this machine}
**   string_append1 (cmd, ':');        {separator before address on last machine}
**
**   Back to common code regardless of whether working around ISP spam bug or not.
*)

  string_append (cmd, adr_from);       {end with sender's address on his machine}
  string_append1 (cmd, '>');
  inet_vstr_crlf_put (cmd, conn, stat); {send MAIL command}
  if sys_error(stat) then goto abort2;
  smtp_resp_get (conn, code, info, ok, stat); {get MAIL command response}
  if sys_error(stat) then goto abort2;
  if not ok then begin                 {received error from server ?}
    serror (stat);                     {write message to bounce file}
    if sys_error(stat) then goto abort2;
    goto next_msg;                     {abort this mail message}
    end;
{
*   Send an RCPT command for each recipient of this mail message.
}
  n_rcpt_ok := 0;                      {init number of accepted recipients}
  string_list_pos_abs (list_adr_p^, 1); {init to first target address in list}

  while list_adr_p^.str_p <> nil do begin {once for each target address in list}
    string_vstring (cmd, 'RCPT TO:<'(0), -1);
    string_append (cmd, list_adr_p^.str_p^);
    string_append1 (cmd, '>');
    inet_vstr_crlf_put (cmd, conn, stat); {send this RCPT command}
    if sys_error(stat) then goto abort2;
    smtp_resp_get (conn, code, info, ok, stat); {get response to this RCPT command}
    if sys_error(stat) then goto abort2;
    if ok
      then begin                       {remote system accepted this target address}
        n_rcpt_ok := n_rcpt_ok + 1;    {count one more accepted recipient}
        string_list_line_del (list_adr_p^, true); {delete this entry, move to next}
        end
      else begin                       {remote system rejected this recipient}
        serror (stat);                 {write message to bounce file}
        if sys_error(stat) then goto abort2;
        string_list_pos_rel (list_adr_p^, 1); {to next adr, leave old adr in list}
        end
      ;
    end;                               {back to process this new list entry}

  if n_rcpt_ok <= 0 then begin         {no recipients accepted, don't send msg ?}
    inet_str_crlf_put ('RSET', conn, stat); {abort this mail message}
    if sys_error(stat) then goto abort2;
    smtp_resp_get (conn, code, info, ok, stat); {get response to RSET command}
    goto next_msg;
    end;
{
*   Send the mail message data.
}
  inet_cstr_crlf_put ('DATA'(0), conn, stat); {indicate start of msg transmission}
  if sys_error(stat) then goto abort2;
  smtp_resp_get (conn, code, info, ok, stat); {get immediate response to DATA cmd}
  if sys_error(stat) then goto abort2;
  if not ok then begin
    serror (stat);                     {write message to bounce file}
    if sys_error(stat) then goto abort2;
    string_vstring (
      errmsg, 'Unexpected response to DATA command for message '(0), -1);
    string_append (errmsg, mconn_p^.tnam);
    show_resp;                         {show error and response to user}
    goto next_msg;
    end;

  file_pos_start (mconn_p^, stat);     {re-position to start of file}
  if sys_error(stat) then goto abort2;
loop_send:                             {back here to send each new message line}
  file_read_text (mconn_p^, cmd, stat); {read next message line from file}
  if file_eof(stat) then goto done_send; {hit end of mail message file ?}
  if sys_error(stat) then goto abort2;
  smtp_mailline_put (cmd, conn, stat); {send this message line}
  if sys_error(stat) then goto abort2;
  goto loop_send;                      {back to send next message line}
done_send:                             {done sending whole message file}
  smtp_mail_send_done (conn, stat);    {send end of message notification}
  if sys_error(stat) then goto abort2;
  smtp_resp_get (conn, code, info, ok, stat); {get final response to DATA cmd}
  if sys_error(stat) then goto abort2;
  if not ok then begin
    serror (stat);                     {write message to bounce file}
    if sys_error(stat) then goto abort2;
    string_vstring (
      errmsg, 'Unexpected response message data for message '(0), -1);
    string_append (errmsg, mconn_p^.tnam);
    show_resp;                         {show error and response to user}
    goto next_msg;
    end;

  msg_sent := true;                    {message sent or bounce errors generated}
{
*   Done with the current queue entry, advance to the next.
*   MSG_SENT is TRUE if the whole message was sent and acknoledged.  The string
*   list LIST_ADR_P is left containing only those destination addresses that
*   were not accepted.  ERR is TRUE if one or more error messages were written
*   to the bounce message file.
}
next_msg:
  if err then begin                    {errors written to bounce file ?}
    send_bounce;                       {send bounce message on any errors}
    msg_sent := true;                  {this message fully dealt with}
    end;
  err_close;                           {close and delete the bounce message file}

  if msg_sent
    then begin                         {message was successfully sent}
      qrclose := [smtp_qrclose_del_k];
      end
    else begin                         {message was not sent}
      qrclose := [];
      end
    ;
  smtp_queue_read_ent_close (qconn, qrclose, stat); {close this queue entry}
  if sys_error(stat) then goto abort1;
  goto loop_msg;                       {back to process next queue entry}
{
*   End of queue encountered.
}
done_msgs:
  if turn then begin                   {supposed to reverse send/receive roles ?}
    inet_cstr_crlf_put ('TURN'(0), conn, stat); {request roles reversal}
    if sys_error(stat) then goto abort1;
    smtp_resp_get (conn, code, info, ok, stat); {get response to TURN command}
    if sys_error(stat) then goto abort1;
    if ok
      then begin                       {receiver accepted roles reversal}
        turn := true;                  {indicate roles are now reversed}
        end
      else begin                       {roles reversal was rejected}
        turn := false;                 {tell caller roles weren't reversed}
        string_vstring (errmsg, 'Response to TURN command:'(0), -1);
        show_resp;
        sys_error_none (stat);         {TURN failure is not a hard error}
        end
      ;
    end;                               {done handling roles reversal request}
  return;                              {normal return}
{
*   Abort on error with queue entry open.
}
abort2:
  err_close;                           {close and delete bounce message file, if any}
  smtp_queue_read_ent_close (qconn, [], stat2); {close queue entry if open}
{
*   Jump here to abort on error with nothing additional open.  STAT is
*   already set to indicate the error.
}
abort1:
  turn := false;                       {we definately didn't reverse send/recv roles}
  end;
