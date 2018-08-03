{   Module of common routines used in handling remote clients.  Unless otherwise
*   noted, all these routines are assumed to be thread-safe.  In other words,
*   they can be called by client handling threads without worrying about thread
*   interlocks.  The interlocks, if any, are handled here.
}
module smtp_client;
define smtp_client_init;
define smtp_client_new;
define smtp_client_close_conn;
define smtp_client_close;
define smtp_client_open;
define smtp_client_wrlock;
define smtp_client_wrunlock;
define smtp_client_log_vstr;
define smtp_client_log_str;
define smtp_client_log_err;
define smtp_client_log_stat_vstr;
define smtp_client_log_stat_str;
define smtp_client_blacklist;

%include 'email2.ins.pas';

const
  wrapcol_k = 72;                      {wrap columns for log entries}

type
  cladr_p_t = ^cladr_t;
  cladr_t = record                     {info we maintain about a client IP address}
    nconn: sys_int_machine_t;          {number of current connections from this node}
    blacklist: boolean;                {this remote machine is blacklisted}
    end;

  treenode_p_t = ^treenode_t;
  treenode_t = record                  {one node in client addresses tree}
    p: array[0..15] of treenode_p_t;
    end;

var
  mem_p: util_mem_context_p_t;         {memory context private to this module}
  lock_mem: sys_sys_threadlock_t;      {single thread interlock for mem context}
  lock: sys_sys_threadlock_t;          {single thread lock for other data here}
  adrtree: treenode_t;                 {root node of client addresses tree}
  nclients: sys_int_machine_t;         {total number of separate clients had}
  nopen: sys_int_machine_t;            {number of clients currently open}
  lock_wr: sys_sys_threadlock_t;       {lock for writing to output and log}
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_INIT
*
*   This must be the first call into this module.  No other calls may be made
*   into this module until this routine returns.  This routine performs one-time
*   initialization of local data structures.
}
procedure smtp_client_init;            {one-time initialization of CLIENT module}
  val_param;

var
  ii: sys_int_machine_t;               {scratch integer and loop counter}
  stat: sys_err_t;                     {completion status}

begin
  util_mem_context_get (util_top_mem_context, mem_p); {create our private memory context}
  sys_thread_lock_create (lock_mem, stat); {create thread interlock for mem context}
  sys_error_abort (stat, 'email', 'email_client_lock', nil, 0);
  sys_thread_lock_create (lock, stat); {create thread interlock for mem context}
  sys_error_abort (stat, 'email', 'email_client_lock', nil, 0);
  for ii := 0 to 15 do begin
    adrtree.p[ii] := nil;              {init client addresses tree to empty}
    end;
  nclients := 0;                       {no clients so far}
  nopen := 0;
  sys_thread_lock_create (lock_wr, stat); {create thread interlock for writing output}
  sys_error_abort (stat, 'email', 'email_client_lock', nil, 0);
  end;
{
********************************************************************************
*
*   Local routine FIND_CLADR (ADR, CLADR_P)
*
*   Returns a pointer to the descriptor for a particular client address.  If
*   there is no previous record of this address, then one is created.
}
procedure find_cladr (                 {find descriptor for client address}
  in      adr: sys_inet_adr_node_t;    {the address to look up}
  out     cladr_p: cladr_p_t);         {returned pointer to the address descriptor}
  val_param; internal;

var
  iadr: sys_int_conv32_t;              {address in a single integer}
  lev: sys_int_machine_t;              {0-7 level in client addresses tree}
  node_p: treenode_p_t;                {pointer to current tree node}
  next_p: treenode_p_t;                {pointer to tree node at next level}
  ii, jj: sys_int_machine_t;           {scratch integer and loop counter}
  adr_p: cladr_p_t;                    {pointer to address descriptor}

begin
  iadr := adr;                         {get address into local integer}

  node_p := addr(adrtree);             {init to root tree node}
  for lev := 0 to 6 do begin           {once for all but last tree level}
    ii := 28 - (lev * 4);
    ii := rshft(iadr, ii) & 15;        {make index into this tree level}
    next_p := node_p^.p[ii];           {get pointer to next tree level}
    if next_p = nil then begin         {next tree node doesn't exist yet ?}
      sys_thread_lock_enter (lock_mem);
      next_p := node_p^.p[ii];         {check next node again now lock is held}
      if next_p = nil then begin       {next node still doesn't exist ?}
        util_mem_grab (                {allocate memory for next tree node}
          sizeof(next_p^), mem_p^, false, next_p);
          for jj := 0 to 15 do begin   {init new tree node}
            next_p^.p[jj] := nil;
            end;
        node_p^.p[ii] := next_p;       {link new node into tree}
        end;
      sys_thread_lock_leave (lock_mem);
      end;
    node_p := next_p;                  {go down to this next node}
    end;                               {back and process next node}
{
*   NODE_P is pointing to the last level tree node.
}
  ii := iadr & 15;                     {make index into this node}
  adr_p := cladr_p_t(node_p^.p[ii]);   {get pointer to final addres descriptor}
  if adr_p = nil then begin            {address descriptor doesn't exist ?}
    sys_thread_lock_enter (lock_mem);
    adr_p := cladr_p_t(node_p^.p[ii]); {get pointer again now with lock held}
    if adr_p = nil then begin          {still doesn't exist ?}
      util_mem_grab (                  {allocate memory for the address descriptor}
        sizeof(adr_p^), mem_p^, false, adr_p);
      adr_p^.nconn := 0;               {init the new descriptor}
      adr_p^.blacklist := false;
      node_p^.p[ii] := treenode_p_t(adr_p); {link new descriptor to tree}
      end;
    sys_thread_lock_leave (lock_mem);
    end;

  cladr_p := adr_p;                    {return pointer to the address descriptor}
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_NEW (CLIENT_P)
*
*   Create a new client descriptor, allocate resources for it as needed, and
*   initialize it.
}
procedure smtp_client_new (            {create new initialized client descriptor}
  out     client_p: smtp_client_p_t);  {pointer to the new descriptor}
  val_param;

var
  clmem_p: util_mem_context_p_t;       {pointer to private mem context for the client}

begin
  sys_thread_lock_enter (lock_mem);
  util_mem_context_get (mem_p^, clmem_p); {create private mem context for the client}
  sys_thread_lock_leave (lock_mem);
  util_mem_grab (                      {allocate memory for the client descriptor}
    sizeof(client_p^), clmem_p^, false, client_p);

  client_p^.mem_p := clmem_p;          {init new client descriptor}
  client_p^.adr := 0;
  client_p^.port := 0;
  client_p^.id := 0;
  client_p^.inq.max := size_char(client_p^.inq.str);
  client_p^.inq.len := 0;
  client_p^.open := false;
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_CLOSE_CONN (CL)
*
*   Close the connection to a client but leave the client descriptor open.
*   Nothing is done if the connection to the client is not currently open.
}
procedure smtp_client_close_conn (     {close connection to client}
  in out  cl: smtp_client_t);          {descriptor for the client}
  val_param;

var
  adr_p: cladr_p_t;                    {pointer to our info about remote node address}
  n: sys_int_machine_t;                {scratch integer}
  str: string_var80_t;                 {log string}
  tk: string_var32_t;                  {scratch token}

begin
  str.max := size_char(str.str);       {init local var strings}
  tk.max := size_char(tk.str);

  if not cl.open then return;          {the connection is not open, nothing do to ?}

  file_close (cl.conn);                {close the connection}
  cl.open := false;                    {mark it as closed}

  find_cladr (cl.adr, adr_p);          {look up our info on the remote address}
  sys_thread_lock_enter (lock);
  if adr_p^.nconn > 0 then begin
    adr_p^.nconn := adr_p^.nconn - 1;  {count one less connection to this address}
    end;
  if nopen > 0 then nopen := nopen - 1; {count one less open connection}
  n := nopen;                          {save number of remaining open connections}
  sys_thread_lock_leave (lock);

  if cl.id <> 0 then begin
    string_vstring (str, 'Closed, '(0), -1);
    string_f_int (tk, n);
    string_append (str, tk);
    string_appends (str, ' still open'(0));
    smtp_client_log_vstr (cl, str);
    end;
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_CLOSE (CL_P)
*
*   Close the connection to the client pointed to by CL_P and deallocate the
*   resources associated with the client descriptor.  CL_P is returned NIL since
*   the descriptor will not longer exist.
}
procedure smtp_client_close (          {close conn to client and deallocate descriptor}
  in out  cl_p: smtp_client_p_t);      {pointer to client descriptor, returned NIL}
  val_param;

var
  clmem_p: util_mem_context_p_t;       {pointer to private mem context for the client}

begin
  smtp_client_close_conn (cl_p^);      {make sure the connection to the client is closed}

  clmem_p := cl_p^.mem_p;              {get pointer to private client mem context}
  util_mem_context_del (clmem_p);      {deallocate all client descriptor memory}
  cl_p := nil;                         {return pointer to descriptor invalid}
  end;
{
********************************************************************************
*
*   Function SMTP_CLIENT_OPEN (CL)
*
*   Set up the client descriptor CL a new connection.  The new connection must
*   be open on CL.CONN.  The client connection may be refused and closed for
*   various reasons.  If so, the function returns FALSE.  In that case the
*   client descriptor is still valid, but the connection to the client has been
*   closed.  If the client connection is accepted, then the function returns
*   TRUE.  Appropriate log entries are written for each of the cases.
}
function smtp_client_open (            {open or reject a new client connection}
  in out  cl: smtp_client_t)           {client descriptor}
  :boolean;                            {TRUE on connection accepted, FALSE on closed}
  val_param;

var
  adr_p: cladr_p_t;                    {pointer to descriptor for this client address}
  str: string_var256_t;                {log entry comment}
  tk: string_var32_t;                  {scratch token}
  stat: sys_err_t;

label
  closeit;

begin
  str.max := size_char(str.str);       {init local var strings}
  tk.max := size_char(tk.str);
  smtp_client_open := false;           {init to client connection rejected and closed}
  cl.open := true;                     {client connection must be open here}

  file_inetstr_info_remote (cl.conn, cl.adr, cl.port, stat); {get remote client info}
  if sys_error(stat) then begin
    smtp_client_wrlock;
    sys_error_print (stat, 'email', 'smtp_client_getadr', nil, 0);
    smtp_client_wrunlock;
    goto closeit;
    end;

  sys_thread_lock_enter (lock);
  nclients := nclients + 1;            {count one more client}
  cl.id := nclients;                   {save unique ID of this client}
  sys_thread_lock_leave (lock);

  string_vstring (str, 'New connection from '(0), -1);
  string_f_inetadr (tk, cl.adr);
  string_append (str, tk);             {add client network address}
  string_appends (str, ' port '(0));
  string_f_int (tk, cl.port);
  string_append (str, tk);             {add port number of client machine}
  smtp_client_log_vstr (cl, str);      {log the new connection from this client}

  find_cladr (cl.adr, adr_p);          {look up client address in our database}

  if adr_p^.blacklist then begin       {this client is blacklisted ?}
    inet_str_crlf_put ('529 Spammer denied', cl.conn, stat);
    smtp_client_log_str (cl, '*** Blacklisted ***  connection closed.');
    goto closeit;
    end;

  sys_thread_lock_enter (lock);
  if
      (adr_p^.nconn >= smtp_maxcladr_k) and {would exceed max connections ?}
      (not sys_inetadr_local(cl.adr))  {client is not local ?}
      then begin
    sys_thread_lock_leave (lock);

    string_vstring (str, '420 Too many connections from this adr, '(0), -1);
    string_f_int (tk, smtp_maxcladr_k);
    string_append (str, tk);
    string_appends (str, ' allowed max');
    inet_vstr_crlf_put (str, cl.conn, stat);
    smtp_client_log_str (cl, 'Too many connections from this client, closing');
    goto closeit;
    end;

  adr_p^.nconn := adr_p^.nconn + 1;    {count one more connection from this address}
  nopen := nopen + 1;                  {count one more concurrent client connection}
  sys_thread_lock_leave (lock);
  smtp_client_open := true;            {indicate client is open}
  return;

closeit:                               {close client connection and leave}
  file_close (cl.conn);                {close the connection to the client}
  cl.open := false;
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_WRLOCK
*
*   Acquire the exclusive lock on writing to the output.
}
procedure smtp_client_wrlock;          {exclusively lock write output}
  val_param;

begin
  sys_thread_lock_enter (lock_wr);
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_WRUNLOCK
*
*   Release the exclusive lock on writing to the output.  This routine undoes
*   what SMTP_CLIENT_WRLOCK does.
}
procedure smtp_client_wrunlock;        {release lock on write output}
  val_param;

begin
  sys_thread_lock_leave (lock_wr);
  end;
{
********************************************************************************
*
*   Local subroutine LOG_ENTRY_STRING (CL, STR)
*
*   Make the leading part of a log entry.  This is the part that is generated
*   from the client information, not the part from the caller.
}
procedure log_entry_string (           {make leading string for log entry}
  in out  cl: smtp_client_t;           {client the log entry is for}
  in out  str: univ string_var_arg_t); {returned string}
  val_param; internal;

var
  tk: string_var32_t;                  {scratch token}

begin
  tk.max := size_char(tk.str);         {init local var string}

  sys_clock_str1 (sys_clock, str);     {init string with current date/time}
  string_append1 (str, ' ');
  string_f_int (tk, cl.id);
  string_append (str, tk);             {add client ID}
  string_appendn (str, ': ', 2);       {separator for user string to follow}
  end;
{
********************************************************************************
*
*   Local subroutine LOG_WRITE_STR (STR)
*
*   Write the string STR to the log.  The string is wrapped at any space to try
*   to limit its length to WRAPCOL_K columns.  Additional wrapped lines, if any,
*   are indented with 2 spaces.  The log writing lock must be held when this
*   routine is called.
}
procedure log_write_str (              {write string to log}
  in      str: univ string_var_arg_t); {the text string to write}
  val_param; internal;

var
  s: string_var8192_t;                 {current output line}
  p: string_index_t;                   {input string parse index}
  sk: string_index_t;                  {last S index to definitely keep}
  ik: string_index_t;                  {STR index to restart at after keep only SK}
  ntk: sys_int_machine_t;              {number of tokens on current output line}
  nb: boolean;                         {non-blank written to output line}
  c: char;                             {current input character}

begin
  s.max := size_char(s.str);           {init local var string}

  p := 1;                              {init input string parse index}
  s.len := 0;                          {init first output string to empty}
  ntk := 0;                            {no tokens on current output line}
  nb := false;                         {no printable since last token break}
  while p <= str.len do begin          {loop until input string exhausted}
    c := str.str[p];                   {fetch this input character}
    p := p + 1;                        {update input string parse index}
    if c <> ' ' then begin             {this is not a blank ?}
      string_append1 (s, c);           {add this line to current output string}
      nb := true;                      {at least one non-blank on this line}
      next;                            {done with this input character}
      end;
    if (ntk = 0) and (not nb) then next; {ignore blanks at start of lines}
    if nb then begin                   {this blank ends a new token ?}
      if (ntk = 0) or (s.len <= wrapcol_k)
        then begin                     {keep token that just ended}
          sk := s.len;                 {definitely keep up to end of last token}
          ik := p;                     {parse restart if need to go back to here}
          ntk := ntk + 1;              {count one more token in output line}
          nb := false;                 {no printable since end of last token}
          end
        else begin                     {this last token overflowed current line ?}
          s.len := sk;                 {truncate back to last token that fits}
          p := ik;                     {reset input parse index for next line}
          string_unpad (s);            {remove any trailing blanks from this line}
          if s.len > 0 then writeln (s.str:s.len); {write this line}
          s.len := 0;                  {reset output line to empty}
          string_appendn (s, '  ', 2); {indent new line}
          ntk := 0;                    {no tokens yet on this new line}
          nb := false;                 {no printable chars yet on this line}
          next;                        {back to process next input line char}
          end
        ;
      end;
    string_append1 (s, c);             {add input char to this output line}
    end;                               {back to get next input char}

  string_unpad (s);                    {delete trailing blanks from partial out line}
  if s.len > 0 then writeln (s.str:s.len); {write last partial output line}
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_LOG_VSTR (CLIENT, STR)
*
*   Write one log entry for the client indidated by CLIENT.  STR is the comment
*   string to write for this log entry.  STR must be a var string.
*
*   The log entry will be written with date/time stamp and information to
*   identify the client, followed by the comment string.
}
procedure smtp_client_log_vstr (       {write log entry, var string comment}
  in out  client: smtp_client_t;       {info about the particular client}
  in      str: univ string_var_arg_t); {log entry comment string}
  val_param;

var
  s: string_var256_t;                  {complete log entry string}

begin
  s.max := size_char(s.str);           {init local var string}

  log_entry_string (client, s);        {make leading string for log entry}
  string_append (s, str);              {add caller's comment}

  smtp_client_wrlock;
  log_write_str (s);                   {write the complete log string}
  smtp_client_wrunlock;
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_LOG_STR (CLIENT, STR)
*
*   Just like SMTP_CLIENT_LOG_VSTR except that STR is a Pascal string instead of
*   a var string.  Trailing blanks of STR will not be written.
}
procedure smtp_client_log_str (        {write log entry, Pascal string comment}
  in out  client: smtp_client_t;       {info about the particular client}
  in      str: string);                {log entry comment string}
  val_param;

var
  vstr: string_var256_t;

begin
  vstr.max := size_char(vstr.str);     {init local var string}
  string_vstring (vstr, str, size_char(str)); {convert caller's string to var string}
  smtp_client_log_vstr (client, vstr); {write the log entry}
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_LOG_ERR (CL, STAT, SUBSYS, MSG, PARMS, N_PARMS)
*
*   Write a log entry about the error indicated by STAT.  In addition, the
*   message described by SUBSYS, MSG, PARMS, and N_PARMS is written.
}
procedure smtp_client_log_err (        {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      subsys: string;              {name of subsystem, used to find message file}
  in      msg: string;                 {message name withing subsystem file}
  in      parms: univ sys_parm_msg_ar_t; {array of parameter descriptors}
  in      n_parms: sys_int_machine_t); {number of parameters in PARMS}
  val_param;

var
  str: string_var8192_t;
  m: string_var8192_t;

begin
  str.max := size_char(str.str);       {init local var strings}
  m.max := size_char(m.str);

  log_entry_string (cl, str);          {make leading part of log entry string}
  string_f_message (m, subsys, msg, parms, n_parms); {get expansion of user string}
  string_append (str, m);              {append to leading part of log entry}
  string_appends (str, ' --> '(0));
  sys_error_string (stat, m);          {get string associated with error status}
  string_append (str, m);

  smtp_client_wrlock;
  log_write_str (str);                 {write the complete log entry}
  smtp_client_wrunlock;
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_LOG_STAT_VSTR (CL, STAT, MSG)
*
*   Write log entry with the message in string MSG and the expansion of the
*   error status in STAT.
}
procedure smtp_client_log_stat_vstr (  {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      msg: univ string_var_arg_t); {user message, var string}
  val_param;

var
  str: string_var8192_t;
  m: string_var8192_t;

begin
  str.max := size_char(str.str);       {init local var strings}
  m.max := size_char(m.str);

  log_entry_string (cl, str);          {make leading part of log entry string}
  string_append (str, msg);            {add on user message}
  string_appends (str, ' --> '(0));
  sys_error_string (stat, m);
  string_append (str, m);              {add on error status message}

  smtp_client_wrlock;
  log_write_str (str);                 {write the complet log entry}
  smtp_client_wrunlock;
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_LOG_STAT_STR (CL, STAT, MSG)
*
*   Write log entry with the message in string MSG and the expansion of the
*   error status in STAT.
}
procedure smtp_client_log_stat_str (   {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      msg: string);                {user message, Pascal string}
  val_param;

var
  str: string_var8192_t;

begin
  str.max := size_char(str.str);       {init local var string}

  string_vstring (str, msg, sizeof(msg)); {make var string of user message}
  smtp_client_log_stat_vstr (cl, stat, str);
  end;
{
********************************************************************************
*
*   Subroutine SMTP_CLIENT_BLACKLIST (CL)
*
*   Blacklist the indicated client.  This will cause future connections to be
*   rejected.
}
procedure smtp_client_blacklist (      {blacklist a remote client}
  in out  cl: smtp_client_t);          {client to blacklist}
  val_param;

var
  adr_p: cladr_p_t;                    {pointer to our info about remote node address}
  str: string_var80_t;                 {log string}
  tk: string_var32_t;                  {scratch string}

begin
  str.max := size_char(str.str);       {init local var strings}
  tk.max := size_char(tk.str);

  find_cladr (cl.adr, adr_p);          {look up our info on the remote address}
  adr_p^.blacklist := true;            {blacklist this address}

  string_vstring (str, 'Blacklisting '(0), -1);
  string_f_inetadr (tk, cl.adr);
  string_append (str, tk);
  smtp_client_log_vstr (cl, str);
  end;
