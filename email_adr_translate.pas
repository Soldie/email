{   Subroutine EMAIL_ADR_TRANSLATE (ADR)
*
*   Translate the email address in ADR thru the translation rules in the MAIL.ADR
*   environment file set.  These may contain the following commands:
*
*     ADD <address string>
*
*       Adds the tokens in the address string to the current email address.
*
*     DEL <token type>
*
*       Deletes the specified token type from the current email address.
*       Nothing is done if the token type does not exist.
*
*     USER <name> <address string>
*
*       If the current user name matches <name>, then the user name is
*       deleted and <address string> is added to the current email address.
*       Nothing is done if <name> doesn't match the current user name.
*       This command is intended to declare user name aliases.  NOTE: this
*       command compares <name> to the current user name in a case-insensitive
*       way.  However, the address string is still added to the current
*       address without any case alterations.
*
*     IF <expression>
*         -  true commands  -
*       ELSE
*         -  false commands  -
*       ENDIF
*
*       If the expression evaluates to TRUE, then the "true commands" are executed,
*       else the "false commands" are executed.  The ELSE line may be omitted if
*       there are no "false commands".
*
*     MESSAGE <subsystem name> <message name>
*
*       This causes the text of the indicated message to be written to
*       standard output.
*
*     ERROR
*
*       Abort program with error condition.
*
*   The constructions are defined as follows:
*
*     <name>
*
*       This is a user, system, or domain name.  These may not contain any
*       blanks or special characters.
*
*     <address string>
*
*       This string contains a list of user, system, and domain names, each
*       preceeded by a special character indentifying how it is to be inserted
*       into the current email address.  The special character for the first
*       name may be omitted, which defaults it to a new user name.  The special
*       characters are:
*
*       !  -  Insert as new user name.  Old user name becomes last system name.
*       @  -  Insert as first system name.
*       .  -  Insert as first domain name.
*
*     <token type>
*
*       This identifies a particular token in the current email address.  It
*       must always be one of the following:
*
*       DOM_FIRST  -  First domain name
*       DOM_LAST  -  Last domain name
*       SYS_FIRST  -  First system name
*       SYS_LAST  -  Last system name
*       USER  -  User name
*
*     <expression>
*
*       This is a logical expression that evaluates to either TRUE or FALSE.
*       It can be made up of any of the following constructions:
*
*       <item>
*
*       <item> AND <item>  . . .   AND <item>
*
*         This is a list of two or more items separated by AND operators.
*         The entire construction is TRUE iff all the items are TRUE.
*
*       <item> OR <item>  . . .   OR <item>
*
*         This is a list of two or more items separated by OR operators.
*         The entire construction is TRUE iff any of the items are TRUE.
*
*     <item>
*
*       This is one "term" in an expression.  It can be any of the following:
*
*       <token type> <name>
*
*         TRUE if the <name> matches the token of the current email address
*         indicated by <token type>.  NOTE: the comparison is case-insensitive.
*
*       NOT <expression>
*
*         This has the reverse TRUE/FALSE value of <expression>.
*
*       (<expression>)
}
module email_adr_translate;
define email_adr_translate;
%include 'email2.ins.pas';

var
  env_name: string_var4_t :=           {generic name of environment files}
    [str := 'mail', len := 4, max := 4];

procedure email_adr_translate (        {xlate email address thru mail.adr env files}
  in out  adr: email_adr_t);           {email address descriptor to translate}
  val_param;

const
  passes_max = 16;                     {max passes allowed thru env file set}

type
  cmd_end_k_t = (                      {reason for end of command processing}
    cmd_end_eof_k,                     {hit end of environment file set}
    cmd_end_else_k,                    {just did ELSE statement}
    cmd_end_endif_k);                  {just did ENDIF statement}

  exp_end_k_t = (                      {reason for end exp or item processing}
    exp_end_eos_k,                     {end of expression string}
    exp_end_paren_k,                   {encountered close parenthesis}
    exp_end_itend_k);                  {end of item, returned by ITEM only}

function expression (                  {evaluate expression}
  in      str: univ string_var_arg_t;  {source string containing the expression}
  in out  p: string_index_t;           {STR parse index, updated}
  out     tf: boolean)                 {returned expression true/false value}
  :exp_end_k_t;                        {expression processing termination reason}
  val_param; forward;

var
  conn: file_conn_t;                   {connection handle to environment file set}
  buf: string_var8192_t;               {one line input buffer}
  passes: sys_int_machine_t;           {number of passes made thru environment files}
  changed: boolean;                    {TRUE if address was changed}
  stat: sys_err_t;                     {completion status code}
{
********************************************************************************
*
*   Local subroutine ERROR (SUBSYS, MSG, PARMS, N_PARMS)
*
*   Bomb program with indicated error message.  Information about the current
*   state of processing the environment file set is printed first.
}
procedure error (                      {print parse info and bomb}
  in      subsys: string;              {name of subsystem, used to find message file}
  in      msg: string;                 {message name within subsystem file}
  in      parms: univ sys_parm_msg_ar_t; {array of parameter descriptors}
  in      n_parms: sys_int_machine_t); {number of parameters in PARMS}
  options (noreturn);

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;

begin
  sys_message_parms (subsys, msg, parms, n_parms); {print user's message}

  sys_msg_parm_int (msg_parm[1], conn.lnum);
  sys_msg_parm_vstr (msg_parm[2], conn.tnam);
  sys_message_bomb ('email', 'err_on_line', msg_parm, 2);
  end;
{
********************************************************************************
*
*   Local subroutine ERROR_CHECK (STAT, SUBSYS, MSG, PARMS, N_PARMS)
*
*   Abort program with indicated error messages and other info if STAT
*   is set to any abnormal status.
}
procedure error_check (                {print parse info and bomb on abnormal STAT}
  in      stat: sys_err_t;             {error status to check}
  in      subsys: string;              {name of subsystem, used to find message file}
  in      msg: string;                 {message name within subsystem file}
  in      parms: univ sys_parm_msg_ar_t; {array of parameter descriptors}
  in      n_parms: sys_int_machine_t); {number of parameters in PARMS}

begin
  if sys_error_check (stat, subsys, msg, parms, n_parms) then begin
    error ('', '', nil, 0);            {print parse info and bomb program}
    end;
  end;
{
********************************************************************************
*
*   Local function TOKEN_TYPE (NAME, TKTYPE)
*
*   If NAME is a token type string, then returns TRUE and sets TKTYPE
*   to the token type.  Otherwise returns FALSE.
}
function token_type (
  in      name: univ string_var_arg_t; {token type name to interpret}
  out     tktype: email_tktyp_k_t)     {returned token type on success}
  :boolean;                            {TRUE if NAME was token type name}

var
  uname: string_var16_t;               {upper case NAME string}
  pick: sys_int_machine_t;             {number of token picked from list}

begin
  uname.max := sizeof(uname.str);      {init local var string}

  string_copy (name, uname);           {make local copy of name string}
  string_upcase (uname);               {make upper case for token matching}
  string_tkpick80 (uname,
    'DOM_FIRST DOM_LAST SYS_FIRST SYS_LAST USER',
    pick);                             {number of token picked from list}
  case pick of                         {which token is it ?}
1:  tktype := email_tktyp_dom_first_k;
2:  tktype := email_tktyp_dom_last_k;
3:  tktype := email_tktyp_sys_first_k;
4:  tktype := email_tktyp_sys_last_k;
5:  tktype := email_tktyp_user_k;
otherwise
    token_type := false;               {name wasn't value token type}
    return;
    end;
  token_type := true;                  {returning with TKTYPE set}
  end;
{
********************************************************************************
*
*   Local subroutine ITEM (STR, P, TF, IEND)
*
*   Process the item starting at index P in string STR.  The true/false
*   item value is returned in TF.  P is updated to after the last
*   character used.  IEND is set to indicate why the item processing terminated.
}
procedure item (                       {evaluate item of an expression}
  in      str: univ string_var_arg_t;  {source string containing the expression}
  in out  p: string_index_t;           {STR parse index, updated}
  out     tf: boolean;                 {returned expression true/false value}
  out     iend: exp_end_k_t);          {item processing termination reason}

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

var
  pick: sys_int_machine_t;             {number of token picked from list}
  token: string_var132_t;              {token being parsed from input string}
  token2: string_var132_t;             {additional scratch token}
  tktype: email_tktyp_k_t;             {identifies a token in an email address}
  etf: boolean;                        {true/false returned from EXPRESSION}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

begin
  token.max := sizeof(token.str);      {init local var strings}
  token2.max := sizeof(token2.str);

  while (p <= str.len) and then (str.str[p] = ' ') do begin {skip leading blanks}
    p := p + 1;
    end;
  if p > str.len then begin            {nothing left in input string ?}
    sys_msg_parm_vstr (msg_parm[1], str);
    error ('email', 'email_exp_eos', msg_parm, 1);
    end;

  if str.str[p] = '(' then begin       {open parenthesis ?}
    p := p + 1;                        {advance parse index past open paren}
    case expression (str, p, tf) of    {process expression within parenthesis}
exp_end_paren_k: ;                     {hitting close paren is only legal answer}
otherwise                              {didn't hit close paren}
      sys_msg_parm_vstr (msg_parm[1], str);
      error ('email', 'email_exp_noclose', msg_parm, 1);
      end;                             {end of expression termination reason cases}
    iend := exp_end_itend_k;           {indicate we hit normal end of item}
    return;
    end;

  string_token (str, p, token, stat);  {get next token from input string}
  error_check (stat, '', '', nil, 0);
  string_upcase (token);               {make upper case for keyword matching}
  string_tkpick80 (token,              {pick token from list of keywords}
    'NOT',
    pick);
  case pick of
{
*   NOT <expression>
}
1: begin
  iend := expression (str, p, etf);    {evaluate expression}
  tf := not etf;                       {pass back flipped expression value}
  end;
{
*   Item token is not explicit item keyword.  It may be an address token type
*   or it could be an error.
}
otherwise
    if not token_type (token, tktype) then begin {not a token type either ?}
      sys_msg_parm_vstr (msg_parm[1], token);
      error ('email', 'email_exp_err_token', msg_parm, 1);
      end;
    string_token (str, p, token, stat); {get name to match against adr token}
    error_check (stat, '', '', nil, 0);
    iend := exp_end_itend_k;           {indicate normal end of item}
    if (token.len > 0) and (token.str[token.len] = ')') then begin {close paren ?}
      token.len := token.len - 1;      {remove close parent from token}
      iend := exp_end_paren_k;         {indicate end is due to close parenthesis}
      end;
    pick := 0;                         {init to specified token not present}
    case tktype of                     {which adr token was specified}
email_tktyp_dom_first_k: pick := adr.dom_first;
email_tktyp_dom_last_k: pick := adr.dom_last;
email_tktyp_sys_first_k: pick := adr.sys_first;
email_tktyp_sys_last_k: pick := adr.sys_last;
email_tktyp_user_k: pick := adr.user;
      end;                             {end of adress token type cases}
    if pick <= 0
      then begin                       {specified adr token doesn't exist}
        tf := token.len = 0;           {nonexistant matches null string}
        end
      else begin                       {specified adr token exists}
        string_list_pos_abs (adr.names, pick); {position to specified adr token}
        string_copy (adr.names.str_p^, token2); {make local copy of adr token}
        string_downcase (token);       {lower case to make case-insensitive compare}
        string_downcase (token2);
        tf := string_equal(token, token2); {TRUE if matches}
        end
      ;
    end;                               {end of keyword cases}
  end;
{
********************************************************************************
*
*   Local function EXPRESSION (STR, P, TF)
*
*   Process the expression starting at index P in string STR.  The true/false
*   expression value is returned in TF.  P is updated to after the last
*   character used.  The function value indicates why expression processing
*   terminated.
}
function expression (                  {evaluate expression}
  in      str: univ string_var_arg_t;  {source string containing the expression}
  in out  p: string_index_t;           {STR parse index, updated}
  out     tf: boolean)                 {returned expression true/false value}
  :exp_end_k_t;                        {expression processing termination reason}
  val_param;

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

var
  iend: exp_end_k_t;                   {item termination reason}
  pick: sys_int_machine_t;             {number of token picked from list}
  token: string_var32_t;               {token being parsed from input string}
  itf: boolean;                        {true/false returned from ITEM}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  loop;

begin
  token.max := sizeof(token.str);      {init local var string}

  item (str, p, tf, iend);             {process first mandatory item}
  expression := exp_end_eos_k;         {init reason why expression processing ended}

loop:                                  {back here for each new operator/item pair}
  case iend of                         {why did item terminate ?}
exp_end_eos_k,                         {hit end of expression string}
exp_end_paren_k: begin                 {hit close parenthesis}
      expression := iend;              {pass terminating condition to caller}
      return;
      end;
    end;

  while (p <= str.len) and then (str.str[p] = ' ') do begin {skip leading blanks}
    p := p + 1;
    end;
  if p > str.len then return;          {hit end of input string ?}
  if str.str[p] = ')' then begin       {hit close parenthesis ?}
    p := p + 1;                        {skip over parenthesis}
    expression := exp_end_paren_k;
    return;
    end;

  string_token (str, p, token, stat);  {get next operator name, if any}
  if string_eos(stat) then return;     {hit end of input string ?}
  string_upcase (token);               {make upper case for keyword matching}
  string_tkpick80 (token,
    'AND OR =',
    pick);
  case pick of                         {which operator is it ?}
{
*   AND
}
1: begin
  item (str, p, itf, iend);            {process item after operator}
  tf := tf and itf;                    {do operator logic}
  end;
{
*   OR
}
2: begin
  item (str, p, itf, iend);            {process item after operator}
  tf := tf or itf;                     {do operator logic}
  end;
{
*   =
}
3: begin
  item (str, p, itf, iend);            {process item after operator}
  tf := tf = itf;                      {do operator logic}
  end;
{
*   Unrecognized operator.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], token);
    error ('email', 'email_exp_op', msg_parm, 1);
    end;                               {end of operator type cases}
  goto loop;                           {back to do next operator/item pair}
  end;
{
********************************************************************************
*
*   Local function DO_COMMANDS (EX)
*
*   Process the commands starting on the next line up to the first terminating
*   condition.  The commands are executed if EX is TRUE, not if FALSE.
*   The function value is the termination reason.
}
function do_commands (                 {process command until terminating condition}
  in      ex: boolean)                 {execute the commands if TRUE}
  :cmd_end_k_t;                        {reason terminated}
  val_param;

const
  max_msg_parms = 3;                   {max parameters we can pass to a message}

var
  p: string_index_t;                   {current BUF parse index}
  cmd: string_var32_t;                 {current command name}
  parm, parm2: string_var256_t;        {command parameters}
  str: string_var256_t;                {scratch string}
  subsys, msg: string_var80_t;         {used to identify a particular message}
  pick: sys_int_machine_t;             {number of token picked from list}
  tktyp: email_tktyp_k_t;              {token type identifier}
  lnum_if: sys_int_machine_t;          {starting line number of IF statement}
  fnam_if: string_treename_t;          {file name where IF statement started}
  expp: string_index_t;                {parse index for expression string}
  exp_val: boolean;                    {result of expression evaluation}
  b: boolean;                          {scratch boolean}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_line, user_match, err_if_eof, done_cmd, err_parm_bad, err_parm_get;
{
*******************************
*
*   Local subroutine CHECK_EXTRA_TOKENS
*   This subroutine is local to DO_COMMANDS.
*
*   Bomb program with appropriate error message if any unread tokens exist
*   on the current command line.
}
procedure check_extra_tokens;

begin
  string_token (buf, p, parm, stat);   {try to get another token}
  if not sys_error(stat) then begin    {actually got another token ?}
    sys_msg_parm_int (msg_parm[1], conn.lnum);
    sys_msg_parm_vstr (msg_parm[2], conn.tnam);
    sys_msg_parm_vstr (msg_parm[3], parm);
    sys_message_bomb ('email', 'err_tokens_too_many', msg_parm, 3);
    end;
  sys_error_none (stat);               {reset error condition}
  end;
{
*******************************
*
*   Start of DO_COMMANDS.
}
begin
  cmd.max := sizeof(cmd.str);          {init local var strings}
  parm.max := sizeof(parm.str);
  parm2.max := sizeof(parm2.str);
  str.max := sizeof(str.str);
  fnam_if.max := sizeof(fnam_if.str);
  subsys.max := sizeof(subsys.str);
  msg.max := sizeof(msg.str);

  do_commands := cmd_end_eof_k;        {init termination reason to end of file}

next_line:                             {jump here to read new command line}
  file_read_env (conn, buf, stat);     {read next command line}
  if file_eof(stat) then begin         {hit end of file ?}
    do_commands := cmd_end_eof_k;      {termination reason was end of file}
    return;
    end;
  error_check (stat, '', '', nil, 0);
  p := 1;                              {init parse index for this new line}
  string_token (buf, p, cmd, stat);    {get command from this line}
  error_check (stat, '', '', nil, 0);
  string_upcase (cmd);                 {make upper case for token matching}
  string_tkpick80 (cmd,                {pick command name from list}
    'ADD DEL USER IF ELSE ENDIF MESSAGE ERROR',
    pick);                             {number of command name picked from list}
  case pick of                         {which command is this ?}
{
*   ADD <address string>
}
1: begin
  if p > buf.len then goto err_parm_get;
  string_substr (buf, p, buf.len, parm); {get address string}
  p := buf.len + 1;                    {indicate command line all used up}
  if not ex then goto done_cmd;        {not supposed to execute command ?}
  email_adr_string_add (adr, parm);    {add string to current email address}
  changed := true;                     {flag that address got changed}
  end;
{
*   DEL <token type>
}
2: begin
  string_token (buf, p, parm, stat);   {get token type name}
  if sys_error(stat) then goto err_parm_get;
  if not token_type (parm, tktyp)
    then goto err_parm_bad;
  if not ex then goto done_cmd;        {not supposed to execute command ?}
  email_adr_tkdel (adr, tktyp);        {delete token from address}
  changed := true;                     {flag that address got changed}
  end;
{
*   USER <name> <address string>
}
3: begin
  string_token (buf, p, parm2, stat);  {get user name}
  if sys_error(stat) then goto err_parm_get;
  if p > buf.len then goto err_parm_get;
  string_substr (buf, p, buf.len, parm); {get address string}
  p := buf.len + 1;                    {indicate command line all used up}
  if not ex then goto done_cmd;        {not supposed to execute command ?}
  if adr.user <= 0 then begin          {no user name in current address ?}
    if parm2.len = 0 then goto user_match; {empty name string matches any user}
    goto done_cmd;                     {definately no match}
    end;
  string_downcase (parm2);             {USER command names are case-insensitive}
  string_list_pos_abs (adr.names, adr.user); {position to current user name}
  string_copy (adr.names.str_p^, str); {make copy of current user name}
  string_downcase (str);               {USER command names are case-insensitive}
  if not string_equal (str, parm2)     {parm doesn't match user name ?}
    then goto done_cmd;
  email_adr_tkdel (adr, email_tktyp_user_k); {delete old user name}
user_match:                            {names matched, add new address string}
  email_adr_string_add (adr, parm);    {add new address string}
  changed := true;                     {flag that address got changed}
  end;
{
*   IF <expression>
}
4: begin
  if p > buf.len then goto err_parm_get; {expression is missing ?}
  string_substr (buf, p, buf.len, parm); {extract expression for input buffer}
  p := buf.len + 1;                    {indicate buffer is all used up}
  expp := 1;                           {init expression string parse index}
  case expression (parm, expp, exp_val) of {evaluate expression}
exp_end_paren_k: begin                 {hit unmatched close parenthesis}
      sys_msg_parm_vstr (msg_parm[1], parm);
      error ('email', 'email_exp_close', msg_parm, 1);
      end;
    end;                               {end of expression termination reason cases}
  string_copy (conn.tnam, fnam_if);    {save file name where IF statement started}
  lnum_if := conn.lnum;                {save starting line number of IF statement}
  b := ex and exp_val;
  case do_commands(b) of               {process TRUE case commands}

cmd_end_eof_k: begin
err_if_eof:                            {jump here on unexpected EOF in IF statement}
      sys_msg_parm_int (msg_parm[1], lnum_if);
      sys_msg_parm_vstr (msg_parm[2], fnam_if);
      error ('email', 'email_if_eof', msg_parm, 2);
      end;

cmd_end_else_k: begin                  {hit ELSE statement}
      b := ex and (not exp_val);
      case do_commands(b) of           {process FALSE case commands}
cmd_end_eof_k: goto err_if_eof;
cmd_end_else_k: begin                  {hit a second ELSE statement ?}
          sys_msg_parm_int (msg_parm[1], lnum_if);
          sys_msg_parm_vstr (msg_parm[2], fnam_if);
          error ('email', 'email_if_else', msg_parm, 2);
          end;
cmd_end_endif_k: goto next_line;       {normal end of IF .. ELSE .. ENDIF}
        end;                           {end of ELSE clause termination cases}
      end;                             {end of ELSE classe case}

cmd_end_endif_k: goto next_line;       {normal end of IF .. ENDIF}
    end;
  end;
{
*   ELSE
}
5: begin
  check_extra_tokens;
  do_commands := cmd_end_else_k;
  return;
  end;
{
*   ENDIF
}
6: begin
  check_extra_tokens;
  do_commands := cmd_end_endif_k;
  return;
  end;
{
*   MESSAGE <subsystem name> <message name>
}
7: begin
  string_token (buf, p, subsys, stat); {get subsystem name}
  if sys_error(stat) then goto err_parm_get;
  string_token (buf, p, msg, stat);    {get message name}
  if sys_error(stat) then goto err_parm_get;
  if not ex then goto done_cmd;        {not supposed to execute command ?}

  string_append1 (subsys, chr(0));     {add terminating character}
  string_append1 (msg, chr(0));        {add terminating character}
  sys_message (subsys.str, msg.str);   {write the message}
  end;
{
*   ERROR
}
8: begin
  check_extra_tokens;
  if not ex then goto done_cmd;        {not supposed to execute command ?}
  sys_bomb;                            {abort the program with errors}
  end;
{
*   Unrecognized command.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], cmd);
    sys_msg_parm_int (msg_parm[2], conn.lnum);
    sys_msg_parm_vstr (msg_parm[3], conn.tnam);
    sys_message_bomb ('email', 'err_cmd_bad', msg_parm, 3);
    end;
{
*   All done processing the current command.  Now make sure there are no
*   extraneous tokens left on the command line.
}
done_cmd:                              {jump here on done processing command}
  check_extra_tokens;                  {bomb if unread tokens left on command line}
  goto next_line;                      {back and do next command line}

err_parm_bad:                          {jump here on bad parameter, STAT set}
  sys_error_print (stat, '', '', nil, 0); {print message associated with STAT}
  sys_msg_parm_vstr (msg_parm[1], parm);
  sys_msg_parm_vstr (msg_parm[2], cmd);
  error ('email', 'err_parm_bad', msg_parm, 2);

err_parm_get:                          {jump here on error getting parm, STAT set}
  sys_error_print (stat, '', '', nil, 0); {print message associated with STAT}
  sys_msg_parm_vstr (msg_parm[1], cmd);
  error ('email', 'err_parm_get', msg_parm, 1);
  return;                              {never executed, but makes C compiler happy}
  end;                                 {end of DO_COMMANDS}
{
********************************************************************************
*
*   Start of main routine.
}
begin
  buf.max := sizeof(buf.str);          {init local var string}
  passes := 0;                         {init number of passes made thru env files}

  repeat                               {back here each new pass thru env files}
    passes := passes + 1;              {make number of this new pass}
    if passes > passes_max then begin  {exceeded max allowed passes limit ?}
      sys_message_bomb ('email', 'email_translate_loop', nil, 0);
      end;
    file_open_read_env (               {try to open environment file set}
      env_name,                        {generic environment file set name}
      '.adr',                          {suffix}
      false,                           {read in local to global order}
      conn,                            {returned connection handle}
      stat);
    if file_not_found(stat) then return; {no files in this env file set ?}
    sys_error_abort (stat, 'email', 'email_env_open', nil, 0);

    changed := false;                  {init to address not changed this pass}
    case do_commands(true) of          {what is commands termination status ?}
cmd_end_else_k: begin                  {dangling ELSE statement}
        error ('email', 'email_end_else', nil, 0);
        end;
cmd_end_endif_k: begin                 {dnagling ENDIF statement}
        error ('email', 'email_end_endif', nil, 0);
        end;
      end;
    file_close (conn);                 {close environment file set}
    until not changed;                 {do it again if address got changed this time}
  end;
