{   Public include file for EMAIL library.  This library contains routines for
*   email handling.
}
const
{
*   Error status values related to the EMAIL subsystem.
}
  email_subsys_k = -16;                {our subsystem ID}

  email_stat_queue_end_k = 1;          {end of queue encountered}
  email_stat_qent_open_k = 2;          {a queue entry is already open}
  email_stat_qent_nopen_k = 3;         {no queue entry currently open}
  email_stat_qopt_cmd_get_k = 4;       {error reading command from OPTIONS file}
  email_stat_qopt_cmd_bad_k = 5;       {unrecognized command in SMTP OPTIONS file}
  email_stat_qopt_parm_err_k = 6;      {err with command parm in OPTIONS file}
  email_stat_qopt_parm_extra_k = 7;    {too many parms in SMTP queue OPTIONS file}
  email_stat_qopt_parm_missing_k = 8;  {missing parm in SMTP queue OPTIONS file}
  email_stat_smtp_err_k = 9;           {general SMTP comm or handshaking error}
  email_stat_smtp_noqueue_k = 10;      {no such mail queue}
  email_stat_smtp_queue_full_k = 11;   {mail queue full or unrecognized error}
  email_stat_smtp_no_in_queue_k = 12;  {no mail input queue specified}
  email_stat_mailfeed_loop_k = 13;     {circular dependency in MAILFEED env set}
  email_stat_envcmd_bad_k = 14;        {bad command in environment file set}
  email_stat_envline_extra_k = 15;     {extra email after env file command}
  email_stat_envparm_missing_k = 16;   {missing parm to env file command}
  email_stat_envparm_err_k = 17;       {bad parameter to env file command}
  email_stat_smtp_resp_err_k = 18;     {error response from SMTP server}
  email_stat_mail_relay_k = 26;        {client tried to relay mail thru us}
{
*   Other constants.
}
  mk_nemp_unk_k = -1;                  {number of employees is unknown}
  mk_year_unk_k = 0;                   {year unknown}
  mk_max_phnumbers_k = 3;              {max phone numbers stored per site}

  wav_chan_max_k = 8;                  {max WAV file channels supported}
  wav_chan_last_k = wav_chan_max_k - 1; {last allowed channel number in a WAV file}

  smtp_port_k = 25;                    {standard SMTP server port number}
  smtp_maxcladr_k = 1;                 {max simultaneous clients from same address}

  pi = 3.14159265358979323846;         {what it sounds like, don't touch}
  pi2 = pi * 2.0;                      {2 Pi}

type
  mk_title_k_t = (                     {selected key employee titles}
    mk_title_unk_k,                    {title is not known}
    mk_title_other_k,                  {not one of the pre-defined titles}
    mk_title_pres_k,                   {president}
    mk_title_ceo_k,                    {chief executive officer}
    mk_title_chmn_k,                   {chairman of the board}
    mk_title_cfo_k,                    {chief financial officer}
    mk_title_vp_eng_k);                {VP of engineering}

  mk_company_p_t =                     {pointer to company data descriptor}
    ^mk_company_t;

  mk_site_p_t =                        {pointer to info about one of company's sites}
    ^mk_site_t;

  mk_emp_p_t =                         {pointer to employee descriptor}
    ^mk_emp_t;

  mk_company_t = record                {all the info about one company}
    next_p: mk_company_p_t;            {points to next company descriptor in chain}
    name: string_var80_t;              {full company name}
    n_emp: sys_int_machine_t;          {number of employees or MK_NEMP_UNK_K}
    est_year: sys_int_machine_t;       {year established or MK_YEAR_UNK_K}
    site_p: mk_site_p_t;               {pointer to company sites, first is HQ}
    emp_p: mk_emp_p_t;                 {pointer to employee list}
    end;

  mk_site_t = record                   {info about one site of company}
    next_p: mk_site_p_t;               {points to next site in chain}
    company_p: mk_company_p_t;         {points to company descriptor this is site of}
    n_emp: sys_int_machine_t;          {number of employees or MK_NEMP_UNK_K}
    phone:                             {"main" phone numbers for this site}
      array[1..mk_max_phnumbers_k] of string_var32_t;
    adr_p: string_chain_ent_p_t;       {pointer to mailing address strings}
    end;

  mk_emp_t = record                    {data about one employee}
    next_p: mk_emp_p_t;                {points to next employee in list}
    site_p: mk_site_p_t;               {more info about site where employee works}
    name_last: string_var32_t;         {last name}
    name_first: string_var32_t;        {first name}
    name_middle: string_var32_t;       {middle initials or names}
    name_titles_pre: string_var32_t;   {prefix titles like "Dr."}
    name_titles_post: string_var32_t;  {postfix titles like "Esquire", "PhD"}
    title_id: mk_title_k_t;            {job function title ID}
    title_name: string_var80_t;        {job function title name}
    phone: string_var32_t;             {direct phone number for this employee}
    email: string_var80_t;             {email address}
    mail_stop: string_var16_t;         {internal mail stop for this employee}
    adr_local_p: string_chain_ent_p_t; {local adr after site (building, dept, etc)}
    end;

  rfinder_calib_t = record             {rangefinder calibration info}
    baseline: real;                    {parallax baseline length}
    rreading: real;                    {reading scale radius}
    tick_size: real;                   {tick size at reading radius}
    units_mult: real;                  {multiplier to get desired distance units}
    compass_ofs: real;                 {compass reading for true north}
    end;

  email_tktyp_k_t = (                  {type of incremental email address token}
    email_tktyp_dom_first_k,           {first (most global) domain name}
    email_tktyp_dom_last_k,            {last (most local) domain name}
    email_tktyp_sys_first_k,           {first (farthest from user) system name}
    email_tktyp_sys_last_k,            {last (closest to user) system name}
    email_tktyp_user_k);               {user name (last token of all)}

  email_adrtyp_k_t = (                 {email address string types}
    email_adrtyp_at_k,                 {use "@" when possible (joe@acme.com)}
    email_adrtyp_bang_k);              {bang path (acme!joe.com)}

  email_adr_t = record                 {data about one email address}
    names: string_list_t;              {string list where names are stored}
    info: string_var132_t;             {info text about particular user}
    dom_first: sys_int_machine_t;      {line number of most global domain name, if any}
    dom_last: sys_int_machine_t;       {line number of most local domain name, if any}
    sys_first: sys_int_machine_t;      {line number of first system name, if any}
    sys_last: sys_int_machine_t;       {line number of last system name, if any}
    user: sys_int_machine_t;           {line number of user name, if any}
    end;

  ehead_read_t = record                {state for reading email message header}
    buf: string_var8192_t;             {line read from stream but not used yet}
    buff: boolean;                     {BUF contains a read but unused line}
    conn_p: file_conn_p_t;             {pointer to email message input stream}
    end;

  smtp_code_resp_t = array[1..3] of char; {3 digit SMTP command response code}

  smtp_queue_options_t = record        {all info that comes from queue OPTIONS files}
    localsys: string_var256_t;         {fully qualified name of local system}
    recvdom: string_var256_t;          {list of domains we handle mail for, upper case}
    remotesys: string_var256_t;        {name needed to get to remote system}
    rem_resp: string_var256_t;         {name as reported by remote system}
    remotepswd: string_var80_t;        {password for sending to remote server}
    remoteuser: string_var80_t;        {user name for sending to remote server}
    port: sys_inet_port_id_t;          {port ID of server on remote system, 0 = def}
    inq: string_leafname_t;            {default generic input queue name}
    smtp_cmd: string_treename_t;       {SMTP executable file, may be full pathname}
    pswdget: string_var80_t;           {password from clients for getting from queue}
    pswdput: string_var80_t;           {password from clients for sending to us}
    bouncefrom: string_var80_t;        {FROM address for bounce messages, lower case}
    sendmail: boolean;                 {TRUE if send mail to local SENDMAIL program}
    autosend: boolean;                 {TRUE if supposed to dequeue after write ents}
    pop3: boolean;                     {TRUE if POP3 server allowed to dump queue}
    userput: boolean;                  {clients must give user name to send to us}
    localqueue: boolean;               {local queue of specified name exists}
    localread: boolean;                {OPTIONS file was read in the local queue}
    end;

  smtp_qrclose_k_t = (                 {options for close queue entry open for read}
    smtp_qrclose_del_k,                {delete queue entry}
    smtp_qrclose_undeliv_k);           {remaining adr list ents undeliv, send msg}
  smtp_qrclose_t = set of smtp_qrclose_k_t; {all the flags in one word}

  smtp_qconn_read_t = record           {handle for reading an SMTP queue}
    qdir: string_treename_t;           {tree name of this queue directory}
    opts: smtp_queue_options_t;        {all the info from OPTIONS file set}
    mem_p: util_mem_context_p_t;       {our private memory context}
    list_ents: string_list_t;          {list of all queue control file entries}
    conn_c: file_conn_t;               {connection handle to current control file}
    list_adr: string_list_t;           {destination addresses for current entry}
    conn_m: file_conn_t;               {connection handle to current message file}
    ent_open: boolean;                 {TRUE if queue entry currently open}
    end;

  smtp_rqmeth_k_t = (                  {methods for requesting our queued mail}
    smtp_rqmeth_none_k,                {no request method specified}
    smtp_rqmeth_turn_k,                {SMTP TURN command}
    smtp_rqmeth_etrn1_k,               {simple ETRN, no option chars, see RFC 1985}
    smtp_rqmeth_etrn2_k,               {full ETRN with option chars, see RFC 1985}
    smtp_rqmeth_mqrun_k,               {MAILQRUN method (Ultranet)}
    smtp_rqmeth_qsnd_k);               {SMTP QSND command (Net1Plus)}
{
*   The following is all the information we need to send and receive email
*   to/from a remote system.  All fields may not be relevant for all remote
*   and/or local systems.  This data structure should always be initialized
*   with routine SMTP_RINFO_INIT to avoid compatibility problems when new
*   fields are added.  Fields that are not used or needed must be left as
*   set by SMTP_RINFO_INIT.
}
  smtp_rfld_k_t = (                    {IDs for some fields in SMTP_RINFO_T}
    smtp_rfld_name_k,                  {field NAME}
    smtp_rfld_mach_k,                  {field MACHINE}
    smtp_rfld_qname_k,                 {field QNAME}
    smtp_rfld_isp_k,                   {field ISP}
    smtp_rfld_domisp_k,                {field DOMAIN_ISP}
    smtp_rfld_phbook_k,                {field PHBOOK_ENT}
    smtp_rfld_phnum_k,                 {field PHNUM}
    smtp_rfld_user_k,                  {field USER}
    smtp_rfld_psw_k,                   {field PASSWORD}
    smtp_rfld_port_k,                  {field PORT_SMTP}
    smtp_rfld_sinact_k,                {field SEC_INACT_DONE}
    smtp_rfld_sact_k,                  {field SEC_ACTIVE_DONE}
    smtp_rfld_sredial_k,               {field SEC_REDIAL_WAIT}
    smtp_rfld_mdial_k,                 {field N_MAX_DIAL}
    smtp_rfld_dom_k,                   {field DOMAINS}
    smtp_rfld_meth_k,                  {field RQMETH}
    smtp_rfld_cnct_k);                 {field CONNECT}
  smtp_rfld_t = set of smtp_rfld_k_t;

  smtp_rinfo_t = record                {info about a remote dialup location}
    name: string_var80_t;              {our name for this collection of state}
    machine: string_var256_t;          {remote machine name}
    qname: string_var80_t;             {name of our queue for mail to remote sys}
    isp: string_var80_t;               {name of remote internet service provider}
    domain_isp: string_var80_t;        {ISP's domain name}
    phbook_ent: string_var80_t;        {system phonebook entry name}
    phnum: string_var80_t;             {phone number, only 0-9, #, and *}
    user: string_var80_t;              {user name to log onto remote system}
    password: string_var80_t;          {password for this user on remote system}
    port_smtp: sys_int_machine_t;      {TCP/IP port on remote machine of SMTP server}
    sec_inact_done: real;              {sec assume done on no server activity at all}
    sec_active_done: real;             {sec assume done after server activity}
    sec_redial_wait: real;             {seconds to wait between redial attempts}
    n_max_dial: sys_int_machine_t;     {max allowed total dial tries, 0 = no limit}
    domains: string_var8192_t;         {names of the domains receiving mail for}
    rqmeth: smtp_rqmeth_k_t;           {method used to request mail from remote sys}
    connect: boolean;                  {TRUE if need to actively connect to remote}
    conn: file_conn_t;                 {remote conn handle, use is system dependent}
    userset: smtp_rfld_t;              {element for each field set by the user}
    end;

  smtp_client_p_t = ^smtp_client_t;
  smtp_client_t = record               {thread arg for client, must release bef exit}
    mem_p: util_mem_context_p_t;       {pnt to private mem context for this thread}
    conn: file_conn_t;                 {client TCP/IP connection}
    adr: sys_inet_adr_node_t;          {network address of machine client is on}
    port: sys_inet_port_id_t;          {port number on client machine}
    id: sys_int_machine_t;             {unique ID number for this client}
    inq: string_leafname_t;            {input queue, empty for use default}
    open: boolean;                     {connection to client is open}
    end;

  htm_out_t = record                   {state for writing to an HTML file}
    conn: file_conn_t;                 {I/O connection to output file}
    buf: string_var8192_t;             {buffered output data not yet written}
    indent: sys_int_machine_t;         {number of characters to indent new lines}
    indent_lev: sys_int_machine_t;     {indentation level}
    indent_size: sys_int_machine_t;    {number of indentation chars per level}
    pad: boolean;                      {add separator before next free form token}
    wrap: boolean;                     {allow wrapping to next line at blanks}
    end;
  htm_out_p_t = ^htm_out_t;

  ihn_flag_k_t = (                     {flags in hex file reading state}
    ihn_flag_ownconn_k,                {we own CONN pointed to by CONN_P}
    ihn_flag_eof_k);                   {HEX file EOF record previously read}
  ihn_flag_t = set of ihn_flag_k_t;

  ihex_in_t = record                   {state for reading Intel HEX file stream}
    conn_p: file_conn_p_t;             {pnt to connection to the text input stream}
    adrbase: sys_int_conv32_t;         {base address for adr in individual records}
    ndat: sys_int_conv32_t;            {total number of data bytes read from HEX file}
    ibuf: string_var8192_t;            {one line input buffer}
    p: string_index_t;                 {IBUF parse index}
    cksum: int8u_t;                    {checksum of input line bytes processed so far}
    flags: ihn_flag_t;                 {set of individual flags}
    end;

  ihex_dat_t =                         {data bytes from one Intel HEX file line}
    array[0 .. 255] of int8u_t;        {max possible data bytes on one line}

  ihex_rtype_k_t = int8u_t (           {different Intel HEX file record types}
    ihex_rtype_dat_k = 0,              {data record}
    ihex_rtype_eof_k = 1,              {end of file}
    ihex_rtype_segadr_k = 2,           {segmented address}
    ihex_rtype_linadr_k = 4);          {linear address record}

  ihex_out_t = record                  {state for writing to Intel HEX file stream}
    conn_p: file_conn_p_t;             {pnt to connection to the text output stream}
    adrbase: int32u_t;                 {start address of current 64Kb region}
    maxdat: sys_int_machine_t;         {max data values allowed on one HEX out line}
    adrdat: int32u_t;                  {address for first data byte in DAT}
    ndat: sys_int_machine_t;           {number of data values in DAT}
    dat: ihex_dat_t;                   {buffered data values not yet written}
    flags: ihn_flag_t;                 {set of individual flags}
    end;

  wav_enc_k_t = (                      {WAV encoding formats}
    wav_enc_samp_k);                   {uncompressed samples at regular intervals}

  wav_iterp_k_t = (                    {WAV data interpolation modes}
    wav_iterp_pick_k,                  {pick nearest sample}
    wav_iterp_lin_k,                   {linearly interpolate two nearest}
    wav_iterp_cubic_k);                {cubically interpolate four nearest}

  wav_info_t = record                  {info about WAV data}
    enc: wav_enc_k_t;                  {encoding format}
    nchan: sys_int_machine_t;          {number of audio channels}
    srate: real;                       {sample rate in Hz}
    cbits: sys_int_machine_t;          {bits per channel within a sample}
    cbytes: sys_int_adr_t;             {bytes per channel within a sample}
    sbytes: sys_int_adr_t;             {bytes per sample for all channels}
    end;

  wav_in_t = record                    {state for reading one WAV file}
    {
    *   These fields may be read by applications.
    }
    info: wav_info_t;                  {general info about the WAV data}
    dt: real;                          {seconds between samples}
    tsec: real;                        {total seconds playback time}
    nsamp: sys_int_conv32_t;           {total number of samples}
    salast: sys_int_conv32_t;          {0-N number of the last sample (NSAMP-1)}
    chlast: sys_int_machine_t;         {0-N number of the last channel}
    conn: file_conn_t;                 {connection to WAV file}
    mem_p: util_mem_context_p_t;       {mem context for this WAV file connection}
    {
    *   These fields are private to the WAV file input routines and should
    *   not be accessed by applications.
    }
    map: file_map_handle_t;            {handle to entire WAV file mapped into memory}
    wav_p: univ_ptr;                   {points to WAV file mapped into memory}
    wavlen: sys_int_adr_t;             {total length of the WAV file mapped to mem}
    dat_p: univ_ptr;                   {points to raw WAV data mapped into memory}
    datlen: sys_int_adr_t;             {length of the raw data starting at DAT_P^}
    end;
  wav_in_p_t = ^wav_in_t;

  wav_samp_t =                         {raw sample data of a WAV file}
    array[0 .. wav_chan_last_k] of real;

  wav_kern_t = array[0 .. 0] of real;  {filter kernel template}
  wav_kern_p_t = ^wav_kern_t;

  wav_filt_t = record                  {info for filtering WAV input data}
    wavin_p: wav_in_p_t;               {pointer to WAV input reading state}
    np: sys_int_machine_t;             {number of points in convolution kernel}
    plast: sys_int_machine_t;          {0-N number of last filter point}
    dp: real;                          {delta seconds between convolution points}
    t0: real;                          {relative seconds offset for first kernel pnt}
    kern_p: wav_kern_p_t;              {pointer to convolution kernel function}
    ugain: boolean;                    {normalize filter output for unity gain}
    end;

  wav_out_t = record                   {state for writing to a WAV file}
    info: wav_info_t;                  {info about the WAV data}
    nsamp: sys_int_conv32_t;           {number of samples written so far}
    salast: sys_int_conv32_t;          {0-N number of the last sample (NSAMP-1)}
    chlast: sys_int_machine_t;         {0-N number of the last channel}
    conn: file_conn_t;                 {connection to binary output file}
    buf: array[0 .. 8192] of char;     {output buffer}
    bufn: sys_int_adr_t;               {number of bytes in BUF}
    end;
  wav_out_p_t = ^wav_out_t;
{
*   Quoted printable encoded data handling.
}
  qprflag_k_t = (                      {flags for reading quoted printable text}
    qprflag_conn_close_k,              {close input CONN on EOF}
    qprflag_conn_del_k,                {delete input CONN after close}
    qprflag_passthru_k);               {pass input stream thru without interpreting}
  qprflags_t = set of qprflag_k_t;     {all the flags in one word}

  qprint_read_t = record               {state for reading quoted printable stream}
    buf: string_var1024_t;             {one line input buffer}
    p: string_index_t;                 {BUF parse index}
    flags: qprflags_t;                 {set of individual flags}
    conn_p: file_conn_p_t;             {points to quoted printable text input stream}
    end;
  qprint_read_p_t = ^qprint_read_t;
{
*   Web form reading.
}
  wfread_k_t = (                       {web form parsing state}
    wfread_norm_k,                     {normal, no special conditions exist}
    wfread_cr_k,                       {CR encountered last, end of line returned}
    wfread_lf_k,                       {LF encountered last, end of line returned}
    wfread_eoc_k,                      {at end of command}
    wfread_eof_k);                     {encountered end of input stream}

  wform_read_t = record                {state for reading web form result stream}
    qp_p: qprint_read_p_t;             {pointer to quoted printable decoded stream}
    ps: wfread_k_t;                    {parsing state}
    end;
{
*   CSV file handling.
}
  csv_in_p_t = ^csv_in_t;
  csv_in_t = record                    {data per CSV input file connection}
    conn: file_conn_t;                 {connection to the file, open for text read}
    buf: string_var8192_t;             {one line input buffer}
    p: string_index_t;                 {input line parse index}
    field: sys_int_machine_t;          {1-N field number last read, 0 before line}
    open: boolean;                     {connection to the CSV file is open}
    end;

  csv_out_p_t = ^csv_out_t;
  csv_out_t = record                   {data per CSV output file connection}
    conn: file_conn_t;                 {connection to the CSV file, open for text write}
    buf: string_var8192_t;             {buffer for next line to write}
    open: boolean;                     {connection to CSV file is open}
    end;
{
*   List of name/value pairs.
}
  nameval_ent_p_t = ^nameval_ent_t;
  nameval_ent_t = record
    prev_p: nameval_ent_p_t;           {points to previous list entry}
    next_p: nameval_ent_p_t;           {points to next list entry}
    name_p: string_var_p_t;            {the name string}
    value_p: string_var_p_t;           {the value associated with the name}
    end;

  nameval_list_p_t = ^nameval_list_t;
  nameval_list_t = record
    mem_p: util_mem_context_p_t;       {points to dynamic memory context for list}
    first_p: nameval_ent_p_t;          {points to first list entry}
    last_p: nameval_ent_p_t;           {points to last list entry}
    nents: sys_int_machine_t;          {number of entries in the list}
    memcr: boolean;                    {private memory context created}
    end;
{
*   Parts database structures.
}
  partref_part_p_t = ^partref_part_t;
  partref_part_t = record              {one reference part in list of ref parts}
    prev_p: partref_part_p_t;          {points to previous list entry}
    next_p: partref_part_p_t;          {points to next list entry}
    desc: string_var80_t;              {description string}
    value: string_var80_t;             {value string}
    package: string_var32_t;           {package description string}
    subst_set: boolean;                {SUBST field has been set}
    subst: boolean;                    {substitutions allowed, TRUE when not set}
    inhouse: nameval_list_t;           {list of organizations with their part numbers}
    manuf: nameval_list_t;             {list of manufacturers with their part numbers}
    supplier: nameval_list_t;          {list of suppliers with their part numbers}
    end;

  partref_list_p_t = ^partref_list_t;
  partref_list_t = record              {list of reference part definitions}
    mem_p: util_mem_context_p_t;       {points to dynamic memory context for list}
    first_p: partref_part_p_t;         {points to first list entry}
    last_p: partref_part_p_t;          {points to last list entry}
    nparts: sys_int_machine_t;         {number of entries in the list}
    end;
{
*   Publicly visible debug levels.
*   These debug levels are intended to be set from 0 to 10, where 0 is
*   "production" operation where no extra debug messages are printed, and
*   10 causes maximum debug messages.
}
var (email_debug)
  debug_inet: sys_int_machine_t        {debug level for INET routines}
    := 0;
  debug_smtp: sys_int_machine_t        {debug level for SMTP routines}
    := 0;
{
*   Entry points.
}
procedure csv_in_close (               {close CSV input file}
  in out  cin: csv_in_t;               {CSV file reading state}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

function csv_in_field_fp (             {get next CSV line field as floating point}
  in out  cin: csv_in_t;               {CSV file reading state}
  out     stat: sys_err_t)             {completion status}
  :sys_fp_max_t;                       {returned field value, 0.0 on error}
  val_param; extern;

function csv_in_field_int (            {get next CSV line field as integer}
  in out  cin: csv_in_t;               {CSV file reading state}
  out     stat: sys_err_t)             {completion status}
  :sys_int_max_t;                      {returned field value, 0 on error}
  val_param; extern;

procedure csv_in_field_str (           {read next field from current CSV input line}
  in out  cin: csv_in_t;               {CSV file reading state}
  in out  str: univ string_var_arg_t;  {returned field contents}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_in_line (                {read next line from CSV file}
  in out  cin: csv_in_t;               {CSV file reading state}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_in_open (                {open CSV input file}
  in      fnam: univ string_var_arg_t; {CSV file name, ".csv" suffix may be omitted}
  out     cin: csv_in_t;               {returned CSV reading state}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

function csvfield_null (               {check for empty CSV file field}
  in out  stat: sys_err_t)             {STAT to test, reset on returning TRUE}
  :boolean;                            {STAT is indicating empty CSV file field}
  val_param; extern;

procedure csv_out_close (              {close CSV output file}
  in out  csv: csv_out_t;              {CSV file writing state, returned invalid}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_fp_fixed (           {write fixed format floating point as next CSV field}
  in out  csv: csv_out_t;              {CSV file writing state}
  in      fp: double;                  {floating point value to write}
  in      digr: sys_int_machine_t;     {digits right of decimal point}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_fp_free (            {write free format floating point as next CSV field}
  in out  csv: csv_out_t;              {CSV file writing state}
  in      fp: double;                  {floating point value to write}
  in      sig: sys_int_machine_t;      {number of significant digits}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_fp_ftn (             {write FP as next CSV field, FTN formatting}
  in out  csv: csv_out_t;              {CSV file writing state}
  in      fp: double;                  {floating point value to write}
  in      fw: sys_int_machine_t;       {minimum total number width}
  in      digr: sys_int_machine_t;     {digits right of decimal point}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_blank (              {write completely blank field, not quoted}
  in out  csv: csv_out_t;              {CSV file writing state}
  in      n: sys_int_machine_t;        {number of blanks to write}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_int (                {write integer as next CSV field}
  in out  csv: csv_out_t;              {CSV file writing state}
  in      i: sys_int_max_t;            {integer value}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_line (               {write curr line to CSV file, will be reset to empty}
  in out  csv: csv_out_t;              {CSV file writing state}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_open (               {open CSV output file}
  in      fnam: univ string_var_arg_t; {CSV file name, ".csv" suffix may be omitted}
  out     csv: csv_out_t;              {returned CSV file writing state}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_str (                {string as next CSV field}
  in out  csv: csv_out_t;              {CSV file writing state}
  in      str: string;                 {string to write as field, trailing blanks ignored}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure csv_out_vstr (               {var string as next CSV field}
  in out  csv: csv_out_t;              {CSV file writing state}
  in      vstr: univ string_var_arg_t; {string to write as single field}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ehead_read_close (           {end reading email header, release resources}
  in out  eh: ehead_read_t;            {header reading state, returned invalid}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ehead_read_cmd (             {get next command from email header}
  in out  eh: ehead_read_t;            {state for reading email message header}
  in out  cmd: univ string_var_arg_t;  {command name, ":" stripped, upper case}
  in out  body: univ string_var_arg_t; {body of whole command after ":"}
  out     stat: sys_err_t);            {completion status, EOF at end of header}
  val_param; extern;

procedure ehead_read_open (            {set up for reading an email message header}
  out     eh: ehead_read_t;            {state for reading header, initialized}
  in out  conn: file_conn_t;           {connection to raw email message stream}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure email_adr_create (           {create and init email address descriptor}
  out     adr: email_adr_t;            {descriptor to create and initialize}
  in out  mem: util_mem_context_t);    {mem context to use for private memory}
  val_param; extern;

procedure email_adr_delete (           {release all resources used by adr descriptor}
  in out  adr: email_adr_t);           {adr descriptor to delete, returned useless}
  val_param; extern;

procedure email_adr_domain (           {get domain of email address}
  in out  adr: email_adr_t;            {email address description}
  in out  dom: univ string_var_arg_t); {returned full domain name, upper case}
  val_param; extern;

procedure email_adr_extract (          {extract adr and other info from email string}
  in      str: univ string_var_arg_t;  {input string, like after "FROM:", etc.}
  in out  adr: univ string_var_arg_t;  {returned just the pure email address string}
  in out  info: univ string_var_arg_t); {all the other non-address text in string}
  val_param; extern;

procedure email_adr_string_add (       {add string to existing email address}
  out     adr: email_adr_t;            {email address descriptor to add to}
  in      str: univ string_var_arg_t); {source email address string}
  val_param; extern;

procedure email_adr_t_string (         {create string from email address descriptor}
  in out  adr: email_adr_t;            {email address descriptor}
  in      adrtyp: email_adrtyp_k_t;    {desired string address format}
  in out  str: univ string_var_arg_t); {resulting email address string}
  val_param; extern;

procedure email_adr_tkadd (            {add token to email address}
  in out  adr: email_adr_t;            {email address descriptor to edit}
  in      tk: univ string_var_arg_t;   {new token to add}
  in      tktyp: email_tktyp_k_t);     {identifies the token type}
  val_param; extern;

procedure email_adr_tkdel (            {delete token from email address}
  in out  adr: email_adr_t;            {email address descriptor to edit}
  in      tktyp: email_tktyp_k_t);     {identifies which token to delete}
  val_param; extern;

procedure email_adr_translate (        {xlate email address thru mail.adr env files}
  in out  adr: email_adr_t);           {email address descriptor to translate}
  val_param; extern;

procedure htm_close_write (            {close HTML file open for writing}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_open_write_name (        {open/create HTML output file by name}
  out     hout: htm_out_t;             {returned initialized HTM writing state}
  in      fnam: univ string_var_arg_t; {pathname of file to open or create}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_bline (            {write blank line to HTML output file}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_buf (              {write all buffered data, if any, to HTM file}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_color (            {write a color value in HTML format, no blank before}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      red, grn, blu: real;         {color components in 0-1 scale}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_color_gray (       {write gray color value in HTML format, no blank before}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      gray: real;                  {0-1 gray value}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_indent (           {indent HTM writing by one level}
  in out  hout: htm_out_t);            {state for writing to HTML output file}
  val_param; extern;

procedure htm_write_indent_abs (       {set HTM absolute output indentation level}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      indabs: sys_int_machine_t);  {new absolute indentation level}
  val_param; extern;

procedure htm_write_indent_rel (       {set HTM relative output indentation level}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      indrel: sys_int_machine_t);  {additional levels to indent, may be neg}
  val_param; extern;

procedure htm_write_undent (           {un-indent HTM writing by one level}
  in out  hout: htm_out_t);            {state for writing to HTML output file}
  val_param; extern;

procedure htm_write_line (             {write complete text line to HTM output file}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      line: univ string_var_arg_t; {line to write, will be HTM line exactly}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_line_str (         {write complete text line to HTM output file}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      line: string;                {line to write, NULL term or blank padded}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_newline (          {new data goes to new line of HTML file}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_nopad (            {inhibit blank before next free format token}
  in out  hout: htm_out_t);            {state for writing to HTML output file}
  val_param; extern;

procedure htm_write_pre_line (         {write one line of pre-formatted text}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      line: univ string_var_arg_t; {line to write, HTM control chars converted}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_pre_end (          {stop writing pre-formatted text}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_pre_start (        {start writing pre-formatted text}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_str (              {write free format string to HTM file}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      str: string;                 {string to write, NULL term or blank padded}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_vstr (             {write free format string to HTM file}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      str: univ string_var_arg_t;  {string to write}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure htm_write_wrap (             {set wrapping to new lines a blanks}
  in out  hout: htm_out_t;             {state for writing to HTML output file}
  in      onoff: boolean);             {TRUE enables wrapping, FALSE disables}
  val_param; extern;

procedure ihex_in_close (              {close a use of the IHEX_IN routines}
  in out  ihn: ihex_in_t;              {state this use of routines, returned invalid}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure ihex_in_dat (                {get data bytes from next HEX file data rec}
  in out  ihn: ihex_in_t;              {state for reading HEX file stream}
  out     adr: int32u_t;               {address of first data byte in DAT}
  out     nd: sys_int_machine_t;       {0-255 number of data bytes in DAT}
  out     dat: ihex_dat_t;             {the data bytes}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure ihex_in_line_raw (           {read hex file line and return the raw info}
  in out  ihn: ihex_in_t;              {state for reading HEX file stream}
  out     nd: sys_int_machine_t;       {0-255 number of data bytes}
  out     adr: int32u_t;               {address represented by address field}
  out     rtype: ihex_rtype_k_t;       {record type ID}
  out     dat: ihex_dat_t;             {the data bytes}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure ihex_in_open_conn (          {open HEX in routines with existing stream}
  in out  conn: file_conn_t;           {connection to the input stream}
  out     ihn: ihex_in_t;              {returned state for this IHEX input stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure ihex_in_open_fnam (          {open HEX in routines with file name}
  in      fnam: univ string_var_arg_t; {file name}
  in      ext: string;                 {file name suffix}
  out     ihn: ihex_in_t;              {returned state for this IHEX input stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure ihex_out_byte (              {write one data byte to HEX output file}
  in out  iho: ihex_out_t;             {state for this use of HEX output routines}
  in      adr: int32u_t;               {address of the data byte}
  in      b: int8u_t;                  {the data byte value}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure ihex_out_close (             {close use of HEX output routines}
  in out  iho: ihex_out_t;             {state for this use of HEX output routines}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure ihex_out_open_conn (         {open HEX out routines with existing stream}
  in out  conn: file_conn_t;           {connection to the existing output stream}
  out     iho: ihex_out_t;             {returned state for writing to HEX stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure ihex_out_open_fnam (         {open HEX out routines to write to file}
  in      fnam: univ string_var_arg_t; {file name}
  in      ext: string;                 {file name suffix}
  out     iho: ihex_out_t;             {returned state for writing to HEX file}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_connect (               {connect to remote system, if needed}
  in out  rinfo: smtp_rinfo_t;         {info about the remote system}
  out     new_conn: boolean;           {TRUE on connected if previously wasn't}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_cstr_crlf_put (         {send CRLF terminated string, C format}
  in      cstr: univ string;           {string, NULL terminated, no CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_disconnect (            {disconnect from remote system}
  in out  rinfo: smtp_rinfo_t;         {info about the remote system}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_str_crlf_put (          {send CRLF terminated string, 80 chars max}
  in      str: string;                 {string, blank padded or NULL term, no CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_vstr_crlf_put (         {send CRLF terminated string, vstring format}
  in      vstr: univ string_var_arg_t; {string, doesn't include CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_vstr_crlf_get (         {receive CRLF terminated string}
  in out  vstr: univ string_var_arg_t; {returned string, CRLF removed}
  in out  conn: file_conn_t;           {handle to internet stream to read from}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure mk_init_company (            {init company descriptor to "empty" values}
  in out  company: mk_company_t);      {company descriptor to initialize}
  extern;

procedure mk_init_employee (           {init employee descriptor to "empty" values}
  in out  emp: mk_emp_t);              {employee descriptor to initialize}
  extern;

procedure mk_init_site (               {init site descriptor to "empty" values}
  in out  site: mk_site_t);            {site descriptor to initialize}
  extern;

procedure mk_write_adr (               {write company site address}
  in      site: mk_site_t;             {site descriptor}
  in out  conn: file_conn_t;           {handle to file connection to write to}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure mk_write_adr_phone (         {write company site address and phone numbers}
  in      site: mk_site_t;             {site descriptor}
  in out  conn: file_conn_t;           {handle to file connection to write to}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure mk_ziff_read (               {read next entry from Ziff-Davis data file}
  in out  conn: file_conn_t;           {stream handle to read record from}
  in out  company_p: mk_company_p_t;   {pnt to company desc, NIL = create new}
  in out  mem: util_mem_context_t;     {will use this memory context for new mem}
  out     stat: sys_err_t);            {completion status}
  extern;

procedure nameval_ent_add_end (        {add name/value entry to end of list}
  in out  list: nameval_list_t;        {the list to add the entry to}
  in      ent_p: nameval_ent_p_t);     {pointer to the entry to add}
  val_param; extern;

procedure nameval_ent_new (            {create and initialize new name/value list entry}
  in out  list: nameval_list_t;        {the list to create entry for}
  out     ent_p: nameval_ent_p_t);     {returned pointer to the new entry}
  val_param; extern;

function nameval_get_val (             {look up name and get associated value}
  in      list: nameval_list_t;        {the list to look up in}
  in      name: univ string_var_arg_t; {the name to look up}
  in out  val: univ string_var_arg_t)  {returned value, empty string on not found}
  :boolean;                            {name was found}
  val_param; extern;

procedure nameval_list_del (           {delete (deallocate resources) of list}
  in out  list: nameval_list_t);       {the list to deallocate resources of}
  val_param; extern;

procedure nameval_list_init (          {initialize list of name/value pairs}
  out     list: nameval_list_t;        {the list to initialize}
  in out  mem: util_mem_context_t);    {parent memory context, will create subordinate}
  val_param; extern;

function nameval_match (               {find whether name/value matches a list entry}
  in      list: nameval_list_t;        {the list to match against}
  in      name: univ string_var_arg_t; {the name to match}
  in      val: univ string_var_arg_t)  {the value to match}
  :sys_int_machine_t;                  {-1 = mismatch, 0 = no relevant entry, 1 = match}
  val_param; extern;

procedure nameval_set_name (           {set name in name/value list entry}
  in      list: nameval_list_t;        {the list the entry is associated with}
  out     ent: nameval_ent_t;          {the entry to set the name of}
  in      name: univ string_var_arg_t); {the name to write into the entry}
  val_param; extern;

procedure nameval_set_value (          {set value in name/value list entry}
  in      list: nameval_list_t;        {the list the entry is associated with}
  out     ent: nameval_ent_t;          {the entry to set the value of}
  in      value: univ string_var_arg_t); {the value to write into the entry}
  val_param; extern;

procedure partref_list_del (           {deallocate resources of reference parts list}
  in out  list: partref_list_t);       {list to deallocate resources of, will be invalid}
  val_param; extern;

procedure partref_list_init (          {initialize list of reference part definitions}
  out     list: partref_list_t;        {the list to initialize}
  in out  mem: util_mem_context_t);    {parent memory context, will create subordinate}
  val_param; extern;

procedure partref_part_add_end (       {add part to end of reference parts list}
  in out  list: partref_list_t;        {the list to add the part to}
  in      part_p: partref_part_p_t);   {poiner to the part to add}
  val_param; extern;

procedure partref_part_new (           {create and initialize new partref list entry}
  in      list: partref_list_t;        {the list the entry will be part of}
  out     part_p: partref_part_p_t);   {returned pointer to the new entry, not linked}
  val_param; extern;

procedure partref_read_csv (           {add parts from CSV file to partref list}
  in out  list: partref_list_t;        {the list to add parts to}
  in      csvname: univ string_var_arg_t; {CSV file name, ".csv" suffix may be omitted}
  out     stat: sys_err_t);
  val_param; extern;

procedure qprint_read_char (           {decode next char from quoted printable strm}
  in out  qprint: qprint_read_t;       {state for reading quoted printable stream}
  out     c: char;                     {next character decoded from the stream}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure qprint_read_char_str (       {decode quoted printable char from string}
  in      buf: univ string_var_arg_t;  {qprint input string, no trailing blanks}
  in out  p: string_index_t;           {parse index, init to 1 for start of string}
  in      single: boolean;             {single string, not in succession of lines}
  out     c: char;                     {returned decoded character}
  out     stat: sys_err_t);            {completion status, EOS on input string end}
  val_param; extern;

procedure qprint_read_close (          {deallocate resources for reading quoted print}
  in out  qprint: qprint_read_t;       {reading state, returned invalid}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure qprint_read_getline (        {abort this input line, get next}
  in out  qprint: qprint_read_t;       {reading state, returned invalid}
  out     stat: sys_err_t);            {completion status, can be EOF}
  val_param; extern;

procedure qprint_read_open_conn (      {set up for reading quoted printable stream}
  out     qprint: qprint_read_t;       {reading state, will be initialized}
  in out  conn: file_conn_t;           {connection to quoted printable input stream}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure rfinder_calib_get (          {get current rangefinder calibration values}
  out     cal: rfinder_calib_t);       {returned values}
  val_param; extern;

procedure rfinder_calib_set (          {set current rangefinder calibration values}
  in      cal: rfinder_calib_t);       {new calibration value to use from now on}
  val_param; extern;

procedure rfinder_disp (               {make displacement from rangefinder reading}
  in      tick: real;                  {range finder distance reading in ticks}
  in      comp: real;                  {compass reading, degrees east of north}
  out     dx, dy: real);               {displacement, X is east, Y is north}
  val_param; extern;

function rfinder_dist (                {get rangefinder distance given tick reading}
  in      t: real)                     {reading in ticks from rangefinder scale}
  :real;                               {returned distance value}
  val_param; extern;

procedure smtp_autosend (              {de-queue queue entries in separate process}
  in      qtop_dir: univ string_var_arg_t; {name of top level queue directory}
  in      qloc_dir: univ string_var_arg_t; {name of specific queue directory}
  in      sync: boolean;               {run proc synchronously, get exit status}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_client_blacklist (      {blacklist a remote client}
  in out  cl: smtp_client_t);          {client to blacklist}
  val_param; extern;

procedure smtp_client_close (          {close conn to client and deallocate descriptor}
  in out  cl_p: smtp_client_p_t);      {pointer to client descriptor, returned NIL}
  val_param; extern;

procedure smtp_client_close_conn (     {close connection to client}
  in out  cl: smtp_client_t);          {descriptor for the client}
  val_param; extern;

procedure smtp_client_init;            {one-time initialization of CLIENT module}
  val_param; extern;

procedure smtp_client_log_err (        {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      subsys: string;              {name of subsystem, used to find message file}
  in      msg: string;                 {message name withing subsystem file}
  in      parms: univ sys_parm_msg_ar_t; {array of parameter descriptors}
  in      n_parms: sys_int_machine_t); {number of parameters in PARMS}
  val_param; extern;

procedure smtp_client_log_stat_str (   {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      msg: string);                {user message, Pascal string}
  val_param; extern;

procedure smtp_client_log_stat_vstr (  {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      msg: univ string_var_arg_t); {user message, var string}
  val_param; extern;

procedure smtp_client_log_str (        {write log entry, Pascal string comment}
  in out  client: smtp_client_t;       {info about the particular client}
  in      str: string);                {log entry comment string}
  val_param; extern;

procedure smtp_client_log_vstr (       {write log entry, var string comment}
  in out  client: smtp_client_t;       {info about the particular client}
  in      str: univ string_var_arg_t); {log entry comment string}
  val_param; extern;

procedure smtp_client_new (            {create new initialized client descriptor}
  out     client_p: smtp_client_p_t);  {pointer to the new descriptor}
  val_param; extern;

function smtp_client_open (            {open or reject a new client connection}
  in out  cl: smtp_client_t)           {client descriptor}
  :boolean;                            {TRUE on connection accepted, FALSE on closed}
  val_param; extern;

procedure smtp_client_thread (         {thread routine for one SMTP client}
  in out  d: smtp_client_t);           {unique data for this client}
  extern;

procedure smtp_client_wrlock;          {exclusively lock write output}
  val_param; extern;

procedure smtp_client_wrunlock;        {release lock on write output}
  val_param; extern;

procedure smtp_mail_send_done (        {indicate done sending mail message}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_mailline_get (          {get line of mail message}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  in out  str: univ string_var_arg_t;  {string for this line of mail message}
  out     done: boolean;               {TRUE if hit end of mail msg, STR unused}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_mailline_put (          {send line of mail message}
  in      str: univ string_var_arg_t;  {mail message line to send}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_opts_get (        {read OPTIONS files and return info}
  in      qtop_dir: univ string_var_arg_t; {name of top level queue directory}
  in      qloc_dir: univ string_var_arg_t; {name of specific queue directory}
  out     opts: smtp_queue_options_t;  {returned values from OPTIONS files}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_read_close (      {close connection to an SMTP queue}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_read_ent (        {read next SMTP queue entry}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  out     to_list_p: string_list_p_t;  {list of destination addresses for this msg}
  out     mconn_p: file_conn_p_t;      {handle to open message file connection}
  out     stat: sys_err_t);            {set to EMAIL_STAT_QUEUE_END_K on queue end}
  val_param; extern;

procedure smtp_queue_read_ent_close (  {close this queue entry}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  in      flags: smtp_qrclose_t;       {flags for specific optional operations}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_read_open (       {open an SMTP queue for read}
  in      qname: univ string_var_arg_t; {name of queue to open}
  in out  mem: util_mem_context_t;     {parent mem context for our new mem context}
  out     qconn: smtp_qconn_read_t;    {returned handle to queue read connection}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_create_close (    {close queue entry open for creation}
  in out  conn_c: file_conn_t;         {connection handle to control file}
  in out  conn_a: file_conn_t;         {connection handle to addresses list file}
  in out  conn_m: file_conn_t;         {connection handle to mail message file}
  in      keep: boolean;               {TRUE for keep entry, FALSE for delete}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_create_ent (      {create a new mail queue entry}
  in      qname: univ string_var_arg_t; {generic name of queue to create entry in}
  out     conn_c: file_conn_t;         {handle to open control file}
  out     conn_a: file_conn_t;         {handle to open addresses list file}
  out     conn_m: file_conn_t;         {handle to open mail message file}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

function smtp_receive_wait (           {check for must wait for incoming mail}
  in      rinfo: smtp_rinfo_t)         {info about remote system}
  :boolean;                            {TRUE if must wait on incoming timeout}
  val_param; extern;

function smtp_recv (                   {get all mail from remote system into queue}
  in out  client: smtp_client_t;       {info on the remote client}
  in out  turn: boolean;               {in TRUE to allow TURN, TRUE on TURN received}
  out     stat: sys_err_t)             {returned completion status code}
  :boolean;                            {at least one message written to input queue}
  val_param; extern;

procedure smtp_request_mail (          {request remote system to send us mail}
  in      rinfo: smtp_rinfo_t;         {remote sys info, must already be connected}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_resp_check (            {get and check SMTP server response}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {error on bad response}
  val_param; extern;

procedure smtp_resp_get (              {read entire response, return info}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     code: smtp_code_resp_t;      {standard 3 digit response code}
  in out  str: univ string_var_arg_t;  {concatenated response string, blank sep}
  out     ok: boolean;                 {TRUE if command completed as specified}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_rinfo_init (            {init SMTP_RINFO_T to benign default values}
  out     rinfo: smtp_rinfo_t);        {data structure to fill in}
  val_param; extern;

procedure smtp_rinfo_read_env (        {update RINFO from data in environment files}
  in out  rinfo: smtp_rinfo_t;         {data structure to update, previously init}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_send (                  {send all mail in queue to remote system}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  in out  qconn: smtp_qconn_read_t;    {handle to SMTP queue open for read}
  in out  turn: boolean;               {issue TURN at end on TRUE, TRUE if TURNed}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_send_queue (            {send all mail in a queue}
  in      qname: univ string_var_arg_t; {generic queue name}
  in      recv: boolean;               {try to receive incoming mail on TRUE}
  in      queue_in: univ string_var_arg_t; {name of input queue on RECV TRUE}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure wav_filt_aa (                {set up anti-aliasing filter}
  in out  wavin: wav_in_t;             {state for reading WAV input stream}
  in      fcut: real;                  {cutoff frequency, herz}
  in      attcut: real;                {min required attenuation at cutoff freq}
  out     filt: wav_filt_t);           {returned initialized filter info}
  val_param; extern;

procedure wav_filt_init (              {init WAV input filter}
  in out  wavin: wav_in_t;             {state for reading WAV input stream}
  in      tmin: real;                  {seconds offset for first filter kernel point}
  in      tmax: real;                  {seconds offset for last filter kernel point}
  in      ffreq: real;                 {Hz samp freq for defining filter function}
  out     filt: wav_filt_t);           {initialized filter info, filter all zero}
  val_param; extern;

function wav_filt_samp_chan (          {get filtered value of channel in sample}
  in out  filt: wav_filt_t;            {info for filtering WAV input stream}
  in      t: real;                     {WAV input time at which to create sample}
  in      chan: sys_int_machine_t)     {0-N channel number, -1 to average all}
  :real;                               {-1 to +1 sample value}
  val_param; extern;

function wav_filt_val (                {get interpolated filter kernel value}
  in out  filt: wav_filt_t;            {info for filtering WAV input stream}
  in      t: real)                     {filter time, pos for past, neg for future}
  :real;                               {filter kernel interpolated to filter time T}
  val_param; extern;

procedure wav_in_close (               {close WAV input file}
  in out  wavin: wav_in_t;             {state for reading WAV file, returned invalid}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure wav_in_open_fnam (           {open WAV input file by name}
  out     wavin: wav_in_t;             {returned state for this use of WAV_IN calls}
  in      fnam: univ string_treename_t; {input file name}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

function wav_in_iterp_chan (           {get interpolated WAV input signal}
  in out  wavin: wav_in_t;             {state for reading WAV input signal}
  in      t: real;                     {WAV input time at which to interpolate}
  in      iterp: wav_iterp_k_t;        {interpolation mode to use}
  in      chan: sys_int_machine_t)     {0-N channel number, -1 to average all}
  :real;                               {interpolated WAV value at T}
  val_param; extern;

procedure wav_in_samp (                {get all the data of one sample}
  in out  wavin: wav_in_t;             {state for reading this WAV file}
  in      n: sys_int_conv32_t;         {0-N sample number}
  out     chans: univ wav_samp_t);     {-1 to 1 data for each channel}
  val_param; extern;

function wav_in_samp_chan (            {get particular channel value within sample}
  in out  wavin: wav_in_t;             {state for reading this WAV file}
  in      n: sys_int_conv32_t;         {0-N sample number}
  in      chan: sys_int_machine_t)     {0-N channel number, -1 to average all}
  :real;                               {-1 to +1 sample value}
  val_param; extern;

function wav_in_samp_mono (            {get mono value of particular sample in WAV}
  in out  wavin: wav_in_t;             {state for reading this WAV file}
  in      n: sys_int_conv32_t)         {0-N sample number}
  :real;                               {-1 to +1 sample value}
  val_param; extern;

procedure wav_out_close (              {close WAV output file}
  in out  wavot: wav_out_t;            {state for writing WAV file, returned invalid}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure wav_out_open_fnam (          {open WAV output file by name}
  out     wavot: wav_out_t;            {returned state for this use of WAV_OUT calls}
  in      fnam: univ string_treename_t; {output file name}
  in      info: wav_info_t;            {info about the WAV data}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure wav_out_samp (               {write next sample to WAV output file}
  in out  wavot: wav_out_t;            {state for writing this WAV file}
  in      chans: univ wav_samp_t;      {-1 to 1 data for each chan within the sample}
  in      nchan: sys_int_machine_t;    {number of chans data supplied for in CHANS}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure wav_out_samp_mono (          {write monophonic sample to WAV output file}
  in out  wavot: wav_out_t;            {state for writing this WAV file}
  in      val: real;                   {-1.0 to 1.0 value for all channels}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure wform_read_char (            {read next interpreted web form character}
  in out  wf: wform_read_t;            {web form reading state}
  out     c: char;                     {next char interpreted from stream}
  out     stat: sys_err_t);            {completion status, EOF on "&"}
  val_param; extern;

procedure wform_read_close (           {end reading from web form stream}
  in out  wf: wform_read_t;            {web form reading state, returned invalid}
  out     stat: sys_err_t);            {completion status, EOF at end of command}
  val_param; extern;

procedure wform_read_cmd (             {read next command name from web form stream}
  in out  wf: wform_read_t;            {web form reading state}
  in out  cmd: univ string_var_arg_t;  {command name, upper case}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure wform_read_open_qp (         {init reading web form from quoted printable}
  in out  wf: wform_read_t;            {reading state, will be initialized}
  in out  qp: qprint_read_t;           {state for reading quoted printable stream}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure wform_read_parm (            {read next command paramete line from web frm}
  in out  wf: wform_read_t;            {web form reading state}
  in out  parm: univ string_var_arg_t; {one parameter line}
  out     stat: sys_err_t);            {completion status, EOF at end of command}
  val_param; extern;
