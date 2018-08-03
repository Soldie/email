{   Module of routines to mess with email addresses.
}
module email_adr;
define email_adr_create;
define email_adr_delete;
define email_adr_string_add;
define email_adr_t_string;
define email_adr_domain;
define email_adr_tkadd;
define email_adr_tkdel;
%include 'email2.ins.pas';
{
********************************************************************************
}
procedure email_adr_create (           {create and init email address descriptor}
  out     adr: email_adr_t;            {descriptor to create and initialize}
  in out  mem: util_mem_context_t);    {mem context to use for private memory}
  val_param;

begin
  string_list_init (adr.names, mem);   {create empty address names list}
  adr.info.max := sizeof(adr.info.str);
  adr.info.len := 0;
  adr.dom_first := 0;                  {init indicies to indicate fields not present}
  adr.dom_last := 0;
  adr.sys_first := 0;
  adr.sys_last := 0;
  adr.user := 0;
  end;
{
********************************************************************************
}
procedure email_adr_delete (           {release all resources used by adr descriptor}
  in out  adr: email_adr_t);           {adr descriptor to delete, returned useless}
  val_param;

begin
  string_list_kill (adr.names);        {deallocate dynamic mem for string list}
  end;
{
********************************************************************************
*
*   Subroutine EMAIL_ADR_STRING_ADD (ADR, STR)
*
*   Add the email address in STR to the accumulated email address ADR.  STR can
*   contain normal email address delimiters, like "@", "!", ".", and "%".
}
procedure email_adr_string_add (       {add string to existing email address}
  out     adr: email_adr_t;            {email address descriptor to add to}
  in      str: univ string_var_arg_t); {source email address string}
  val_param;

var
  c: char;                             {current input string character}
  p: sys_int_machine_t;                {current STR parse index}
  dot_valid: sys_int_machine_t;        {string index after which "." starts dom name}
  tktype: email_tktyp_k_t;             {type of current token}
  tktype_new: email_tktyp_k_t;         {type of next token}
  token: string_var80_t;               {token parsed from input string}
  adrs: string_var256_t;               {full email address extracted from STR}
  info: string_var132_t;               {info text extracted from STR}

label
  normal_char, next_char;

begin
  token.max := sizeof(token.str);      {init local var strings}
  adrs.max := sizeof(adrs.str);
  info.max := sizeof(info.str);

  email_adr_extract (str, adrs, info); {get address and info text from source string}
  if (adr.info.len > 0) and (info.len > 0) then begin {adding new info text to old ?}
    string_appendn (adr.info, ', ', 2); {separator between different info texts}
    end;
  string_append (adr.info, info);      {accumulate global user info text}

  dot_valid := 0;                      {init to "." has special meaning everywhere}
  for p := adrs.len downto 1 do begin  {look for last "@" in address string}
    if adrs.str[p] = '@' then begin    {found last "@" ?}
      dot_valid := p;                  {"." only has special meaning after here}
      exit;                            {no need to look further}
      end;
    end;                               {back to look for "@" in previous char}

  token.len := 0;                      {init accumulated token to empty}
  tktype := email_tktyp_user_k;        {init next token type is user name}

  for p := 1 to adrs.len do begin      {once for each character in input string}
    c := adrs.str[p];                  {extract this character}
    case c of                          {what kind of character is this}
{
*   Process the special characters that delimit tokens in the address.
}
'.': begin                             {could be indicating domain name}
      if p <= dot_valid                {"." not valid yet ?}
        then goto normal_char;
      tktype_new := email_tktyp_dom_first_k;
      end;
'@': tktype_new := email_tktyp_sys_first_k;
'%': tktype_new := email_tktyp_sys_first_k;
'!': tktype_new := email_tktyp_user_k;
{
*   Process normal token text character.
}
otherwise
normal_char:                           {jump here if not special char after all}
      string_append1 (token, c);       {add character to end of current token}
      goto next_char;                  {advance to next input string character}
      end;
{
*   We just processed a delimiter character.  TOKEN contains the whole token.
*   TKTYPE is the type of the token.  TKTYPE_NEW has just been set to indicate
*   the type of the token to follow.
}
    email_adr_tkadd (adr, token, tktype); {add token to address descriptor}
    token.len := 0;                    {reset accumulated token to empty}
    tktype := tktype_new;              {set type of new token being accumulated}

next_char:                             {jump here to advance to next input str char}
    end;                               {back for next input string character}

  email_adr_tkadd (adr, token, tktype); {handle last token, if any}
  end;
{
********************************************************************************
*
*   Subroutine EMAIL_ADR_T_STRING (ADR, ADRTYP, STR)
*
*   Create the single-string email address in STR from the email address
*   descriptor ADR.  ADRTYP is the desired format type of the resulting string.
*   Choices for ADRTYP are:
*
*     EMAIL_ADRTYP_AT_K  -  Normal email address containing "@", joe@acme.com.
*
*     EMAIL_ADRTYP_BANG_K  -  Bang path email address, acme!joe.com.  This type
*       is no longer in common use.
*
*   Only the email address is written to STR.  This routine ignores the optional
*   text in the INFO field of ADR.
}
procedure email_adr_t_string (         {create string from email address descriptor}
  in out  adr: email_adr_t;            {email address descriptor}
  in      adrtyp: email_adrtyp_k_t;    {desired string address format}
  in out  str: univ string_var_arg_t); {resulting email address string}
  val_param;

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

var
  n: sys_int_machine_t;                {number of things}
  i: sys_int_machine_t;                {loop counter}
  adtyp: email_adrtyp_k_t;             {address format used internally}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;

label
  domains;

begin
  str.len := 0;                        {init output string to empty}
  adtyp := adrtyp;                     {init address format type to use internally}
  if adr.user <= 0 then goto domains;  {no user or system names exist ?}
  if adr.sys_first > 0
    then begin                         {system names exist}
      n := adr.user - adr.sys_first + 1;
      end
    else begin                         {no system names exist}
      n := 1;
      adtyp := email_adrtyp_at_k;
      end
    ;                                  {N is number of user and system names}
  case adtyp of                        {how should string be formatted ?}
{
*   Write user and systems names using "@" delimieters.
}
email_adrtyp_at_k: begin
      string_list_pos_last (adr.names); {position to user name}
      string_copy (adr.names.str_p^, str); {init string with first name}
      for i := 2 to n do begin         {once for each new user and system name}
        string_append1 (str, '@');     {add delimiter before new name}
        string_list_pos_rel (adr.names, -1); {position to previous system name}
        string_append (str, adr.names.str_p^); {add this name to output string}
        end;                           {back for next system name}
      end;
{
*   Write user and systems names using "!" delimieters.
*   There is definately at least one system name, else we would already have
*   been switched to the "AT" code, above.
}
email_adrtyp_bang_k: begin
      string_list_pos_abs (adr.names, adr.sys_first); {position to first system name}
      string_copy (adr.names.str_p^, str); {init string with first name}
      for i := 2 to n do begin         {once for each new user and system name}
        string_append1 (str, '!');     {add delimiter before new name}
        string_list_pos_rel (adr.names, 1); {position to next system/user name}
        string_append (str, adr.names.str_p^); {add this name to output string}
        end;                           {back for next system/user name}
      end;
{
*   Unrecognized address format type.
}
otherwise
    sys_msg_parm_int (msg_parm[1], ord(adtyp));
    sys_message_bomb ('email', 'email_adrtyp_bad', msg_parm, 1);
    end;
{
*   The user and system names have already been written to the output string.
*   Now write the domain names in local to global order.
}
domains:                               {jump here to start writing domain names}
  if adr.dom_last <= 0 then return;    {no domain names present ?}
  string_list_pos_abs (adr.names, adr.dom_last); {position to last domain name}
  while adr.names.str_p <> nil do begin {once for each domain name}
    string_append1 (str, '.');         {add delimiter before this domain name}
    string_append (str, adr.names.str_p^); {add this domain name}
    string_list_pos_rel (adr.names, -1); {go to previous domain name}
    end;                               {back to process this new domain name}
  end;
{
********************************************************************************
*
*   Subroutine EMAIL_ADR_DOMAIN (ADR, DOM)
*
*   Returns the fully qualified domain in DOM that the email address described
*   by ADR is in.
}
procedure email_adr_domain (           {get domain of email address}
  in out  adr: email_adr_t;            {email address description}
  in out  dom: univ string_var_arg_t); {returned full domain name, upper case}
  val_param;

var
  ii: sys_int_machine_t;

begin
  dom.len := 0;                        {init domain name to empty}
  if adr.dom_last <= 0 then return;    {no domain names present ?}

  for ii := 2 downto 1 do begin
    string_list_pos_abs (adr.names, ii);
    if dom.len > 0 then string_append1 (dom, '.'); {delimiter before this name}
    string_append (dom, adr.names.str_p^); {add this domain name}
    end;

  string_upcase (dom);                 {return domain name upper case}
  end;
{
********************************************************************************
}
procedure email_adr_tkadd (            {add token to email address}
  in out  adr: email_adr_t;            {email address descriptor to edit}
  in      tk: univ string_var_arg_t;   {new token to add}
  in      tktyp: email_tktyp_k_t);     {identifies the token type}
  val_param;

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  pos: sys_int_machine_t;              {string list line number position}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;

label
  add_user;

begin
  if tk.len <= 0 then return;          {ignore empty tokens}
  case tktyp of                        {where does this token go ?}
{
*   First domain name.
}
email_tktyp_dom_first_k: begin
  string_list_pos_start (adr.names);   {first domain name always starts the list}
  adr.names.size := tk.len;            {set length of new line}
  string_list_line_add (adr.names);    {create line for new name}
  string_copy (tk, adr.names.str_p^);  {copy name into new string}
  adr.dom_first := adr.names.curr;     {save line number of new string}

  if adr.dom_last > 0
    then begin
      adr.dom_last := adr.dom_last + 1;
      end
    else begin
      adr.dom_last := adr.dom_first;
      end
    ;
  if adr.sys_first > 0
    then adr.sys_first := adr.sys_first + 1;
  if adr.sys_last > 0
    then adr.sys_last := adr.sys_last + 1;
  if adr.user > 0
    then adr.user := adr.user + 1;
  end;
{
*   Last domain name.
}
email_tktyp_dom_last_k: begin
  string_list_pos_abs (adr.names, adr.dom_last); {position for new line}
  adr.names.size := tk.len;            {set length of new line}
  string_list_line_add (adr.names);    {create line for new name}
  string_copy (tk, adr.names.str_p^);  {copy name into new string}
  adr.dom_last := adr.names.curr;      {save line number of new string}

  if adr.dom_first = 0
    then adr.dom_first := adr.dom_last;
  if adr.sys_first > 0
    then adr.sys_first := adr.sys_first + 1;
  if adr.sys_last > 0
    then adr.sys_last := adr.sys_last + 1;
  if adr.user > 0
    then adr.user := adr.user + 1;
  end;
{
*   First system name.
}
email_tktyp_sys_first_k: begin
  if adr.user <= 0 then goto add_user; {always add user name before any sys names}

  string_list_pos_abs (adr.names, adr.dom_last); {position for adding new line}
  adr.names.size := tk.len;            {set length of new line}
  string_list_line_add (adr.names);    {create line for new name}
  string_copy (tk, adr.names.str_p^);  {copy name into new string}
  adr.sys_first := adr.names.curr;     {save line number of new string}

  if adr.sys_last > 0
    then begin
      adr.sys_last := adr.sys_last + 1;
      end
    else begin
      adr.sys_last := adr.sys_first;
      end
    ;
  adr.user := adr.names.n;             {user name is always last in list}
  end;
{
*   Last system name.
}
email_tktyp_sys_last_k: begin
  if adr.user <= 0 then goto add_user; {always add user name before any sys names}

  if adr.sys_last > 0
    then begin                         {a previous system name exists}
      pos := adr.sys_last;
      end
    else begin                         {no previous system names exist}
      pos := adr.dom_last;
      end
    ;
  string_list_pos_abs (adr.names, pos); {position for adding new line}
  adr.names.size := tk.len;            {set length of new line}
  string_list_line_add (adr.names);    {create line for new name}
  string_copy (tk, adr.names.str_p^);  {copy name into new string}
  adr.sys_last := adr.names.curr;      {save line number of new string}

  adr.user := adr.names.n;             {user name is always last in list}
  end;
{
*   User name.
}
email_tktyp_user_k: begin
add_user:                              {jump here to add user name despite TKTYP}
  adr.sys_last := adr.user;            {old user name becomes last system name}
  if adr.sys_first <= 0 then begin     {old user name also new first system name ?}
    adr.sys_first := adr.sys_last;
    end;

  string_list_pos_last (adr.names);    {position to last line in list}
  adr.names.size := tk.len;            {set length of new line}
  string_list_line_add (adr.names);    {create line for new name}
  string_copy (tk, adr.names.str_p^);  {copy name into new string}
  adr.user := adr.names.curr;          {save line number of new string}
  end;
{
*   Unrecognized token type.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], tk);
    sys_msg_parm_int (msg_parm[2], ord(tktyp));
    sys_message_bomb ('email', 'email_token_type_bad', msg_parm, 2);
    end;
  end;
{
********************************************************************************
}
procedure email_adr_tkdel (            {delete token from email address}
  in out  adr: email_adr_t;            {email address descriptor to edit}
  in      tktyp: email_tktyp_k_t);     {identifies which token to delete}
  val_param;

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

var
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;

begin
  case tktyp of                        {which token to delete ?}
{
*   First domain name.
}
email_tktyp_dom_first_k: begin
  if adr.dom_first <= 0 then return;   {no such token type present ?}
  string_list_pos_abs (adr.names, adr.dom_first); {go to line to be deleted}
  string_list_line_del (adr.names, true); {delete this line}
  adr.dom_first := adr.names.curr;     {update line number for this token type}

  adr.dom_last := adr.dom_last - 1;
  if adr.dom_last < adr.dom_first then begin {just deleted last domain name ?}
    adr.dom_first := 0;
    adr.dom_last := 0;
    end;
  if adr.sys_first > 0 then begin
    adr.sys_first := adr.sys_first - 1;
    end;
  if adr.sys_last > 0 then begin
    adr.sys_last := adr.sys_last - 1;
    end;
  if adr.user > 0 then begin
    adr.user := adr.user - 1;
    end;
  end;
{
*   Last domain name.
}
email_tktyp_dom_last_k: begin
  if adr.dom_last <= 0 then return;    {no such token type present ?}
  string_list_pos_abs (adr.names, adr.dom_last); {go to line to be deleted}
  string_list_line_del (adr.names, false); {delete this line}
  adr.dom_last := adr.names.curr;      {update line number for this token type}

  if adr.dom_last <= 0 then begin      {just deleted last domain name ?}
    adr.dom_first := 0;
    adr.dom_last := 0;
    end;
  if adr.sys_first > 0 then begin
    adr.sys_first := adr.sys_first - 1;
    end;
  if adr.sys_last > 0 then begin
    adr.sys_last := adr.sys_last - 1;
    end;
  if adr.user > 0 then begin
    adr.user := adr.user - 1;
    end;
  end;
{
*   First system name.
}
email_tktyp_sys_first_k: begin
  if adr.sys_first <= 0 then return;   {no such token type present ?}
  string_list_pos_abs (adr.names, adr.sys_first); {go to line to be deleted}
  string_list_line_del (adr.names, true); {delete this line}

  if adr.sys_first = adr.sys_last
    then begin                         {there was only one system name before del}
      adr.sys_first := 0;
      adr.sys_last := 0;
      end
    else begin                         {there is at least one system name left}
      adr.sys_first := adr.names.curr;
      adr.sys_last := adr.sys_last - 1;
      end
    ;
  adr.user := adr.user - 1;
  end;
{
*   Last system name.
}
email_tktyp_sys_last_k: begin
  if adr.sys_last <= 0 then return;    {no such token type present ?}
  string_list_pos_abs (adr.names, adr.sys_last); {go to line to be deleted}
  string_list_line_del (adr.names, false); {delete this line}

  if adr.sys_first = adr.sys_last
    then begin                         {there was only one system name before del}
      adr.sys_first := 0;
      adr.sys_last := 0;
      end
    else begin                         {there is at least one system name left}
      adr.sys_last := adr.names.curr;
      end
    ;
  adr.user := adr.user - 1;
  end;
{
*   User name.
}
email_tktyp_user_k: begin
  adr.info.len := 0;                   {make sure user info text is deleted}
  if adr.user <= 0 then return;        {no such token type present ?}
  string_list_pos_abs (adr.names, adr.user); {go to line to be deleted}
  string_list_line_del (adr.names, false); {delete this line}

  if adr.sys_last > 0
    then begin                         {sys name exists, last sys name becomes user}
      adr.user := adr.names.curr;
      adr.sys_last := adr.sys_last - 1; {take new user from last system name}
      if adr.sys_last < adr.sys_first then begin {just took last system name ?}
        adr.sys_first := 0;
        adr.sys_last := 0;
        end;
      end
    else begin                         {no system names exist to make new user from}
      adr.user := 0;
      end
    ;
  end;
{
*   Unrecognized token type.
}
otherwise
    sys_msg_parm_int (msg_parm[1], ord(tktyp));
    sys_message_bomb ('email', 'email_tktype_bad', msg_parm, 1);
    end;
  end;
