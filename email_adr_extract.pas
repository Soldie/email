{   Subroutine EMAIL_ADR_EXTRACT (STR, ADR, INFO)
*
*   Read the string STR and separate its contents into a pure email address
*   string and all the other info.  A composite string like STR can occurr
*   after the "FROM:" keyword in the email header, on the SENDMAIL command
*   line, and other places.  The parsing rules are:
*
*   1  -  Tokens surrounded by <> are definately the email address.
*
*   2  -  Tokens surrounded by () or "" or '' are definately other info.
*
*   3  -  The first token that can't be definately identified is assumed
*         to be the email address unless a subsequent token comes along
*         that is definately the email address.
*
*   The characters that surround tokens listed above are stripped before
*   being returned in ADR and INFO.  The format of ADR is compatible with
*   subroutine EMAIL_ADR_STRING_ADD.
}
module email_adr_extract;
define email_adr_extract;
%include 'email2.ins.pas';

procedure email_adr_extract (          {extract adr and other info from email string}
  in      str: univ string_var_arg_t;  {input string, like after "FROM:", etc.}
  in out  adr: univ string_var_arg_t;  {returned just the pure email address string}
  in out  info: univ string_var_arg_t); {all the other non-address text in string}
  val_param;

const
  max_token_length = 1024;             {max token length before we lose characters}

type
  state_t = (                          {current parser state}
    state_start_k,                     {initial state, looking for start of token}
    state_token_k,                     {in non-quoted token}
    state_quote_k);                    {in quoted token, looking for Q_END char}

var
  list: string_list_t;                 {list of tokens parsed from STR}
  nadr: sys_int_machine_t;             {line number of email address}
  p: sys_int_machine_t;                {STR parse index}
  adr_sure: boolean;                   {TRUE when sure we have email address}
  c: char;                             {scratch character parsed from STR}
  q_end: char;                         {quote end character}
  state: state_t;                      {current parse state}

begin
  string_list_init (list, util_top_mem_context); {init tokens list}
  list.size := max_token_length;       {set length for new lines in list}
  list.deallocable := false;           {don't need to deallocate individual lines}
  state := state_start_k;              {init current parsing state}
  p := 1;                              {init parse index}
  nadr := 0;                           {indicate no email address found yet}
  adr_sure := false;                   {not definately have email address yet}

  while p <= str.len do begin          {loop until input string exhausted}
    c := str.str[p];                   {fetch this character from input string}
    if (ord(c) < 32) or (ord(c) = 127) then begin {control character ?}
      c := ' ';                        {replace control characters with blanks}
      end;
    p := p + 1;                        {update parse index for next character}
    case state of                      {what is current parsing state ?}
{
*   We are looking for the start of the next token.  There is no current
*   token in LIST.
}
state_start_k: begin
  case c of                            {check for all the special character cases}

' ': ;                                 {extra separator between tokens}

'''', '"': begin                       {quotes with same start and end char}
      state := state_quote_k;          {now parsing a quoted token}
      string_list_line_add (list);     {make string for new token}
      q_end := c;                      {set end quote character to look for}
      end;

'(': begin                             {quoted info token}
      state := state_quote_k;          {now parsing a quoted token}
      string_list_line_add (list);     {make string for new token}
      q_end := ')';                    {set end quote character to look for}
      end;

'<': begin                             {quoted email address token}
      state := state_quote_k;          {now parsing a quoted token}
      string_list_line_add (list);     {make string for new token}
      q_end := '>';                    {set end quote character to look for}
      if not adr_sure then begin       {not already have definate address token ?}
        nadr := list.curr;             {new line is email address token}
        adr_sure := true;              {this is definately email address token}
        end;
      end;

otherwise                              {unquoted token}
    state := state_token_k;            {now parsing an unquoted token}
    string_list_line_add (list);       {make string for new token}
    string_append1 (list.str_p^, c);   {init token with this character}
    if nadr = 0 then begin             {don't even have suspected adr token yet ?}
      nadr := list.curr;               {this token may be email address}
      end;
    end;                               {end of character classification cases}
  end;                                 {end of START parse state case}
{
*   We are currently parsing a non-quoted token.
}
state_token_k: begin
  if c = ' '
    then begin                         {at first character after token}
      state := state_start_k;          {reset to looking for a new token}
      end
    else begin                         {this is another character in this token}
      string_append1 (list.str_p^, c); {add character to end of current token}
      end
    ;
  end;
{
*   We are currently parsing a quoted token.
}
state_quote_k: begin
  if c = q_end
    then begin                         {found ending quote character}
      state := state_start_k;          {reset to looking for a new token}
      end
    else begin                         {this is another character in this token}
      string_append1 (list.str_p^, c); {add character to end of current token}
      end
    ;
  end;

      end;                             {end of parse state cases}
    end;                               {back and process next input character}
{
*   All done reading the input string and splitting it into a sequence of
*   tokens.  All the resulting tokens are in the strings list LIST.
*   NADR is the line number in LIST of the email address token, if any.
*
*   Now run thru the lines in LIST and dole them out to the appropriate return
*   strings.
}
  adr.len := 0;                        {init return strings to empty}
  info.len := 0;
  string_list_pos_abs (list, 1);       {position to first token in list}

  while list.str_p <> nil do begin     {once for each token in list}
    if list.curr = nadr
      then begin                       {this token is email address}
        string_copy (list.str_p^, adr);
        end
      else begin                       {this is another info token}
        if info.len > 0 then begin     {previous email already in INFO ?}
          string_append1 (info, ' ');  {add separator between tokens}
          end;
        string_append (info, list.str_p^); {append this token to info string}
        end
      ;
    string_list_pos_rel (list, 1);     {advance to next token in list}
    end;                               {back to handle this new token from list}

  string_list_kill (list);             {deallocate resources in LIST}
  end;
