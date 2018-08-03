{   Module of SMTP utility routines.
}
module smtp_subs;
define smtp_mail_send_done;
define smtp_mailline_get;
define smtp_mailline_put;
define smtp_resp_get;
define smtp_resp_check;
%include 'email2.ins.pas';

var
  dot: char := '.';                    {DOT special character}
{
*********************************************************************
*
*   Subroutine SMTP_MAILLINE_PUT (STR, CONN, STAT)
*
*   Send one line of a mail message.  This routine takes care of the special
*   protocol used when lines start with ".".  The mail message line to send
*   is in STR.
}
procedure smtp_mailline_put (          {send line of mail message}
  in      str: univ string_var_arg_t;  {mail message line to send}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

begin
  if (str.len >= 1) and then (str.str[1] = '.') then begin {line starts with "." ?}
    file_write_inetstr (dot, conn, 1, stat); {write extra leading dot}
    if sys_error(stat) then return;
    end;

  inet_vstr_crlf_put (str, conn, stat); {send remainder of line}
  end;
{
*********************************************************************
*
*   Subroutine SMTP_MAIL_SEND_DONE (CONN, STAT)
*
*   Indicate done sending mail message lines.  This sends the special line
*   containing only one dot.
}
procedure smtp_mail_send_done (        {indicate done sending mail message}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

begin
  inet_cstr_crlf_put ('.'(0), conn, stat); {write line containing only one dot}
  end;
{
*********************************************************************
*
*   Subroutine SMTP_MAILLINE_GET (CONN, STR, DONE, STAT)
*
*   Read one line of a mail message.  This routine takes care of the special
*   protocol used when lines start with ".".  The real text line is returned
*   in STR.  DONE is set if the end of message was encountered.  In that case
*   STR will contain garbage.
}
procedure smtp_mailline_get (          {get line of mail message}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  in out  str: univ string_var_arg_t;  {string for this line of mail message}
  out     done: boolean;               {TRUE if hit end of mail msg, STR unused}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  i: sys_int_machine_t;                {loop counter}

begin
  done := false;                       {init to not hit end of mail message}

  inet_vstr_crlf_get (str, conn, stat); {read one line from sender}
  if sys_error(stat) then return;

  if                                   {this is not a special "dot" line ?}
      (str.len < 1) or else            {not long enough to contain dot ?}
      (str.str[1] <> '.')              {doesn't start with a dot ?}
    then return;                       {nothing more to do}

  if str.len = 1 then begin            {this line indicates end of mail message ?}
    done := true;
    return;
    end;

  for i := 1 to str.len - 1 do begin   {once for each character to move}
    str.str[i] := str.str[i + 1];      {shift characters left over leading dot}
    end;
  str.len := str.len - 1;              {one less char after leading dot removed}
  end;
{
*********************************************************************
*
*   Subroutine SMTP_RESP_GET (CONN, CODE, STR, OK, STAT)
*
*   Read an entire SMTP command response.  CONN is the connection handle to
*   the internet stream.  CODE is returned the standard 3-digit response code.
*   This is taken from the last response line, although they should all be
*   the same.  STR is returned with the contents of all the response line
*   texts.  If the response has multiple lines, the text portion of the lines
*   are concatenated with one space character between each line.  OK is
*   set to TRUE if the response code indicates that the command was performed
*   as specified (no error, etc).
}
procedure smtp_resp_get (              {read entire response, return info}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     code: smtp_code_resp_t;      {standard 3 digit response code}
  in out  str: univ string_var_arg_t;  {concatenated response string, blank sep}
  out     ok: boolean;                 {TRUE if command completed as specified}
  out     stat: sys_err_t);
  val_param;

var
  line: string_var8192_t;              {one line input buffer}
  i: sys_int_machine_t;                {loop counter}
  n: sys_int_machine_t;                {number of characters to copy}

label
  loop;

begin
  line.max := sizeof(line.str);        {init local var string}
  str.len := 0;                        {init to no text characters returned}

loop:                                  {back here to read each new response line}
  line.str[4] := ' ';                  {short lines will terminate response}
  inet_vstr_crlf_get (line, conn, stat); {read next response line}
  if sys_error(stat) then return;

  if str.len > 0 then begin            {concatenating to previous responses ?}
    string_append1 (str, ' ');         {add separator between response lines}
    end;

  n := min(str.max - str.len, line.len - 4); {number of characters to copy}
  for i := 1 to n do begin             {copy response line chars to output string}
    str.len := str.len + 1;            {one more character in output string}
    str.str[str.len] := line.str[i + 4]; {copy this character}
    end;                               {back to copy next text char to output string}

  if line.str[4] <> ' ' then goto loop; {back for next line in this response ?}

  code[1] := line.str[1];              {pass back 3 digit response code}
  code[2] := line.str[2];
  code[3] := line.str[3];
  ok := (line.len >= 3) and            {line long enough to be valid ?}
    (code[1] >= '1') and (code[1] <= '3'); {one of the positive reponse categories ?}
  end;
{
*********************************************************************
*
*   Subroutine SMTP_RESP_CHECK (CONN, STAT)
*
*   Read and check a response from a remote SMTP server.  STAT is filled in
*   with the appropriate error code on a negative response.  This routine should
*   only be used when a negative response is handled the same was as a hard
*   error.
}
procedure smtp_resp_check (            {get and check SMTP server response}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {error on bad response}
  val_param;

var
  code: smtp_code_resp_t;              {3 digit SMTP response code}
  buf: string_var8192_t;               {one line in/out buffer}
  s: string_var32_t;                   {scratch string}
  ok: boolean;                         {TRUE if SMTP response indicates no error}

begin
  buf.max := sizeof(buf.str);          {init local var strings}
  s.max := sizeof(s.str);

  smtp_resp_get (                      {read initial greeting response from server}
    conn,                              {handle to remote server connection}
    code,                              {returned 3 digit response code}
    buf,                               {returned response string}
    ok,                                {returned TRUE on no error}
    stat);
  if sys_error(stat) then return;      {hard error ?}

  if not ok then begin                 {server indicated negative response ?}
    string_vstring (s, code, 3);       {set STAT to indicate negative response}
    sys_stat_set (email_subsys_k, email_stat_smtp_resp_err_k, stat);
    sys_stat_parm_vstr (s, stat);
    sys_stat_parm_vstr (buf, stat);
    end;
  end;
