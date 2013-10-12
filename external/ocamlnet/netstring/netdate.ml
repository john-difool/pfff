(* $Id: netdate.mlp 1501 2010-12-06 21:43:28Z gerd $
 * ----------------------------------------------------------------------
 *
 *)
(* Thanks to Nicolas George for contributing the parsing and format code *)
type token =
  | Number of int * int
  | (* number of digits, value *)
  Day of int
  | Month of int
  | Meridian of bool
  | Zone of int
  | Dst
  | Plus
  | Minus
  | Comma
  | Colon
  | Slash
  | Dot
  | Time
  | (* "T" *)
  Invalid

let tokens_list =
  [ ("january", (Month 1)); ("jan", (Month 1)); ("february", (Month 2));
    ("feb", (Month 2)); ("march", (Month 3)); ("mar", (Month 3));
    ("april", (Month 4)); ("apr", (Month 4)); ("may", (Month 5));
    ("june", (Month 6)); ("jun", (Month 6)); ("july", (Month 7));
    ("jul", (Month 7)); ("august", (Month 8)); ("aug", (Month 8));
    ("september", (Month 9)); ("sept", (Month 9)); ("sep", (Month 9));
    ("october", (Month 10)); ("oct", (Month 10)); ("november", (Month 11));
    ("nov", (Month 11)); ("december", (Month 12)); ("dec", (Month 12));
    ("sunday", (Day 0)); ("sun", (Day 0)); ("monday", (Day 1));
    ("mon", (Day 1)); ("tuesday", (Day 2)); ("tues", (Day 2));
    ("tue", (Day 2)); ("wednesday", (Day 3)); ("wednes", (Day 3));
    ("wed", (Day 3)); ("thursday", (Day 4)); ("thur", (Day 4));
    ("thurs", (Day 4)); ("thu", (Day 4)); ("friday", (Day 5));
    ("fri", (Day 5)); ("saturday", (Day 6)); ("sat", (Day 6));
    ("am", (Meridian false)); ("pm", (Meridian true)); ("gmt", (Zone 0000));
    ("ut", (Zone 0000)); ("utc", (Zone 0000)); ("wet", (Zone 0000));
    ("z", (Zone 0000)); ("bst", (Zone 0100)); (*DST*) ("cet", (Zone 0100));
    ("cest", (Zone 0200)); ("met", (Zone 0100)); ("mewt", (Zone 0100));
    ("mest", (Zone 0200)); (*DST*) ("mesz", (Zone 0200)); (*DST*)
    ("swt", (Zone 0100)); ("sst", (Zone 0200)); (*DST*) ("fwt", (Zone 0100));
    ("fst", (Zone 0100)); (*DST*) ("eet", (Zone 0200)); ("bt", (Zone 0300));
    ("zp4", (Zone 0400)); ("zp5", (Zone 0500)); ("zp6", (Zone 0600));
    ("wast", (Zone 0700)); ("wadt", (Zone 0800)); (*DST*)
    ("cct", (Zone 0800)); ("jst", (Zone 0900)); ("east", (Zone 1000));
    ("eadt", (Zone 1100)); (*DST*) ("gst", (Zone 1000));
    ("nzt", (Zone 1200)); ("nzst", (Zone 1200)); ("nzdt", (Zone 1300));
    (*DST*) ("idle", (Zone 1200)); ("idlw", (Zone (-1200)));
    ("nt", (Zone (-1100))); ("hst", (Zone (-1000))); ("hdt", (Zone (-0900)));
    (*DST*) ("cat", (Zone (-1000))); ("ahst", (Zone (-1000)));
    ("ydt", (Zone (-0800))); (*DST*) ("yst", (Zone (-0900)));
    ("pst", (Zone (-0800))); ("pdt", (Zone (-0700))); (*DST*)
    ("mst", (Zone (-0700))); ("mdt", (Zone (-0600))); (*DST*)
    ("cst", (Zone (-0600))); ("cdt", (Zone (-0500))); (*DST*)
    ("est", (Zone (-0500))); ("edt", (Zone (-0400))); (*DST*)
    ("ast", (Zone (-0400))); ("adt", (Zone (-0300))); (*DST*)
    ("wat", (Zone (-0100))); ("at", (Zone (-0200))); ("t", Time) ]
  
let find_token =
  let tokens = Hashtbl.create 53 in
  let add_token (name, value) = Hashtbl.add tokens name value
  in
    (List.iter add_token tokens_list;
     fun name -> try Hashtbl.find tokens name with | Not_found -> Invalid)
  
let tokens_of_string str =
  let rec scan_any (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some (('0' .. '9' as c)) ->
        (Stream.junk __strm; scan_number (1, ((int_of_char c) - 48)) __strm)
    | Some (('a' .. 'z' | 'A' .. 'Z' as c)) ->
        (Stream.junk __strm;
         let rest = __strm in
         let b = Buffer.create 16
         in (Buffer.add_char b (Char.lowercase c); scan_word b rest))
    | Some '(' -> (Stream.junk __strm; scan_comment 0 __strm)
    | Some (' ' | '\t') -> (Stream.junk __strm; scan_any __strm)
    | Some '+' ->
        (Stream.junk __strm;
         let rest = __strm
         in Stream.icons Plus (Stream.slazy (fun _ -> scan_any rest)))
    | Some '-' ->
        (Stream.junk __strm;
         let rest = __strm
         in Stream.icons Minus (Stream.slazy (fun _ -> scan_any rest)))
    | Some ':' ->
        (Stream.junk __strm;
         let rest = __strm
         in Stream.icons Colon (Stream.slazy (fun _ -> scan_any rest)))
    | Some ',' ->
        (Stream.junk __strm;
         let rest = __strm
         in Stream.icons Comma (Stream.slazy (fun _ -> scan_any rest)))
    | Some '/' ->
        (Stream.junk __strm;
         let rest = __strm
         in Stream.icons Slash (Stream.slazy (fun _ -> scan_any rest)))
    | Some '.' ->
        (Stream.junk __strm;
         let rest = __strm
         in Stream.icons Dot (Stream.slazy (fun _ -> scan_any rest)))
    | Some _ ->
        (Stream.junk __strm;
         let rest = __strm
         in Stream.icons Invalid (Stream.slazy (fun _ -> scan_any rest)))
    | _ -> Stream.sempty
  and scan_number (l, a) (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some (('0' .. '9' as c)) ->
        (Stream.junk __strm;
         scan_number ((l + 1), ((a * 10) + ((int_of_char c) - 48))) __strm)
    | _ ->
        let rest = __strm
        in
          Stream.icons (Number (l, a))
            (Stream.slazy (fun _ -> scan_any rest))
  and scan_word b (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some (('a' .. 'z' | 'A' .. 'Z' as c)) ->
        (Stream.junk __strm;
         let rest = __strm
         in (Buffer.add_char b (Char.lowercase c); scan_word b rest))
    | Some '.' -> (Stream.junk __strm; scan_word b __strm)
    | _ ->
        let rest = __strm
        in
          Stream.lcons (fun _ -> find_token (Buffer.contents b))
            (Stream.slazy (fun _ -> scan_any rest))
  and scan_comment n (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some ')' ->
        (Stream.junk __strm;
         let rest = __strm
         in if n = 0 then scan_any rest else scan_comment (n - 1) rest)
    | Some '(' -> (Stream.junk __strm; scan_comment (n + 1) __strm)
    | Some _ -> (Stream.junk __strm; scan_comment n __strm)
    | _ -> raise Stream.Failure
  in scan_any (Stream.of_string str)
  
type t =
  { year : int; (* complete year *) month : int; (* 1..12 *) day : int;
    (* 1..31 *) hour : int; minute : int; second : int; zone : int;
    (* in minutes; 60 = UTC+0100 *) week_day : int
  }

(* 0 = sunday; -1 if not given *)
let parse ?zone:(dzone = 0) str =
  let tokens = tokens_of_string str in
  let hour = ref None and minute = ref None and second = ref None
  and zone = ref None and week_day = ref None and day = ref None
  and month = ref None and year = ref None in
  let add_data ?h ?m ?s ?mdn ?tz ?dst ?wd ?md ?mo ?y ?y2 () =
    (* tz as in the above table *)
    let may_store r =
      function
      | None -> ()
      | v when !r = None -> r := v
      | _ -> invalid_arg "Netdate.parse" in
    let tz =
      match (tz, dst) with
      | (Some tz, Some true) -> Some (tz - 100)
      | _ -> tz in
    let tz =
      match tz with
      | None -> None
      | Some x -> Some ((x mod 100) + (60 * (x / 100))) in
    let h =
      match h with
      | None -> None
      | Some h ->
          (match mdn with
           | None when (h >= 0) && (h <= 23) -> Some h
           | Some false when (h > 0) && (h <= 11) -> Some h
           | Some false when h = 12 -> Some 0
           | Some true when (h > 0) && (h <= 11) -> Some (h + 12)
           | Some true when h = 12 -> Some 12) in
    let y =
      match y with
      | None ->
          (match y2 with
           | Some y -> if y < 69 then Some (2000 + y) else Some (1900 + y)
           | None -> None)
      | Some y -> Some y
    in
      (may_store hour h;
       may_store minute m;
       may_store second s;
       may_store zone tz;
       may_store week_day wd;
       may_store day md;
       may_store month mo;
       may_store year y) in
  let rec scan_gen (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some (Number (l, n)) -> (Stream.junk __strm; scan_number (l, n) __strm)
    | Some Time ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number ((0 | 1 | 2), n)) ->
              (Stream.junk __strm;
               (match Stream.peek __strm with
                | Some Colon ->
                    (Stream.junk __strm;
                     (match Stream.peek __strm with
                      | Some (Number ((0 | 1 | 2), m)) ->
                          (Stream.junk __strm; scan_hour n m __strm)
                      | _ -> raise (Stream.Error "")))
                | _ -> raise (Stream.Error "")))
          | _ -> raise (Stream.Error "")))
    | Some (Zone tz) ->
        (Stream.junk __strm;
         let dst =
           (try scan_dst __strm
            with | Stream.Failure -> raise (Stream.Error "")) in
         let rest = __strm in (add_data ~tz ?dst (); scan_gen rest))
    | Some (Day wd) ->
        (Stream.junk __strm;
         let _ =
           (try scan_opt_coma __strm
            with | Stream.Failure -> raise (Stream.Error "")) in
         let rest = __strm in (add_data ~wd (); scan_gen rest))
    | Some (Month mo) ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number (lmd, md)) ->
              (Stream.junk __strm; scan_date_m mo (lmd, md) __strm)
          | _ -> raise (Stream.Error "")))
    | Some _ -> (Stream.junk __strm; invalid_arg "Netdate.parse")
    | _ -> ()
  and scan_number (l, n) (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some (Meridian mdn) ->
        (Stream.junk __strm;
         let rest = __strm in (add_data ~h: n ~mdn (); scan_gen rest))
    | Some Colon ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number ((0 | 1 | 2), m)) ->
              (Stream.junk __strm;
               let rest = __strm
               in
                 if l <= 2
                 then scan_hour n m rest
                 else invalid_arg "Netdate.parse")
          | _ -> raise (Stream.Error "")))
    | Some Slash ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number ((0 | 1 | 2), m)) ->
              (Stream.junk __strm; scan_date_s (l, n) m __strm)
          | _ -> raise (Stream.Error "")))
    | Some Dot ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number ((0 | 1 | 2), m)) ->
              (Stream.junk __strm;
               let rest = __strm
               in
                 if l <= 2
                 then scan_date_dot n m rest
                 else invalid_arg "Netdate.parse")
          | _ -> raise (Stream.Error "")))
    | Some Minus -> (Stream.junk __strm; scan_date_d (l, n) __strm)
    | Some (Month mo) ->
        (Stream.junk __strm;
         let rest = __strm in (add_data ~md: n ~mo (); scan_gen rest))
    | _ ->
        let rest = __strm
        in
          (if l = 4 then add_data ~y: n () else invalid_arg "Netdate.parse";
           scan_gen rest)
  and scan_hour h m (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Colon ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number (_, s)) ->
              (Stream.junk __strm; scan_hour_second_frac h m s __strm)
          | _ -> raise (Stream.Error "")))
    | _ ->
        (match try Some (scan_tz __strm) with | Stream.Failure -> None with
         | Some tz ->
             let rest = __strm in (add_data ~h ~m ~tz (); scan_gen rest)
         | _ ->
             let mdn = scan_opt_meridian __strm in
             let rest = __strm in (add_data ~h ~m ?mdn (); scan_gen rest))
  and scan_tz (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Plus -> (Stream.junk __strm; scan_tz_details 1 __strm)
    | Some Minus -> (Stream.junk __strm; scan_tz_details (-1) __strm)
    | _ -> raise Stream.Failure
  and scan_tz_details sign (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some (Number (l, tz)) when l = 4 -> (Stream.junk __strm; sign * tz)
    | Some (Number (l, tz)) when l <= 2 ->
        (Stream.junk __strm; scan_tz_details2 sign tz __strm)
    | _ -> raise Stream.Failure
  and scan_tz_details2 sign tz1 (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Colon ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number ((0 | 1 | 2), tz2)) ->
              (Stream.junk __strm; sign * ((100 * tz1) + tz2))
          | _ -> raise (Stream.Error "")))
    | _ -> (sign * 100) * tz1
  and scan_hour_second_frac h m s (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Dot ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number (_, _)) ->
              (Stream.junk __strm;
               (* e.g. 12:50:48.12345 *)
               scan_hour_second h m s __strm)
          | _ -> raise (Stream.Error "")))
    | _ -> scan_hour_second h m s __strm
  and scan_hour_second h m s (__strm : _ Stream.t) =
    match try Some (scan_tz __strm) with | Stream.Failure -> None with
    | Some tz ->
        let rest = __strm in (add_data ~h ~m ~s ~tz (); scan_gen rest)
    | _ ->
        let mdn = scan_opt_meridian __strm in
        let rest = __strm in (add_data ~h ~m ~s ?mdn (); scan_gen rest)
  and scan_date_s (ln, n) m (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Slash ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number (lp, p)) ->
              (Stream.junk __strm;
               let rest = __strm
               in
                 (if ln = 4
                  then add_data ~y: n ~mo: m ~md: p ()
                  else
                    if lp = 4
                    then add_data ~y: p ~mo: n ~md: m ()
                    else
                      if lp = 2
                      then add_data ~y2: p ~mo: n ~md: m ()
                      else invalid_arg "Netdate.parse";
                  scan_gen rest))
          | _ -> raise (Stream.Error "")))
    | _ -> let rest = __strm in (add_data ~mo: n ~md: m (); scan_gen rest)
  and scan_date_dot n m (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Dot ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number (l, p)) ->
              (Stream.junk __strm;
               let rest = __strm
               in
                 (if l = 4
                  then add_data ~md: n ~mo: m ~y: p ()
                  else
                    if l = 2
                    then add_data ~md: n ~mo: m ~y2: p ()
                    else invalid_arg "Netdate.parse";
                  scan_gen rest))
          | _ -> raise (Stream.Error "")))
    | _ -> let rest = __strm in (add_data ~md: n ~mo: m (); scan_gen rest)
  and scan_date_d (ln, n) (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some (Number (_, mo)) ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some Minus ->
              (Stream.junk __strm;
               (match Stream.peek __strm with
                | Some (Number (_, md)) ->
                    (Stream.junk __strm;
                     let rest = __strm
                     in
                       (if ln = 4
                        then add_data ~y: n ~mo ~md ()
                        else
                          if ln = 2
                          then add_data ~y2: n ~mo ~md ()
                          else invalid_arg "Netdate.parse";
                        scan_gen rest))
                | _ -> raise (Stream.Error "")))
          | _ -> raise (Stream.Error "")))
    | Some (Month mo) ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some Minus ->
              (Stream.junk __strm;
               (match Stream.peek __strm with
                | Some (Number (ly, y)) ->
                    (Stream.junk __strm;
                     let rest = __strm
                     in
                       (if ly = 4
                        then add_data ~y ~mo ~md: n ()
                        else
                          if ly = 2
                          then add_data ~y2: y ~mo ~md: n ()
                          else invalid_arg "Netdate.parse";
                        scan_gen rest))
                | _ -> raise (Stream.Error "")))
          | _ -> raise (Stream.Error "")))
    | _ -> raise Stream.Failure
  and scan_date_m mo (lmd, md) (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Comma ->
        (Stream.junk __strm;
         (match Stream.peek __strm with
          | Some (Number (4, y)) ->
              (Stream.junk __strm;
               let rest = __strm in (add_data ~y ~mo ~md (); scan_gen rest))
          | _ -> raise (Stream.Error "")))
    | _ -> let rest = __strm in (add_data ~mo ~md (); scan_gen rest)
  and scan_dst (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Dst -> (Stream.junk __strm; Some true)
    | _ -> None
  and scan_opt_coma (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some Comma -> (Stream.junk __strm; ())
    | _ -> ()
  and scan_opt_meridian (__strm : _ Stream.t) =
    match Stream.peek __strm with
    | Some (Meridian mdn) -> (Stream.junk __strm; Some mdn)
    | _ -> None
  in
    ((try scan_gen tokens
      with | Stream.Error _ -> invalid_arg "Netdate.parse");
     let may_get r =
       match !r with | None -> invalid_arg "Netdate.parse" | Some r -> r in
     let get_default d r = match !r with | None -> d | Some r -> r in
     let month = may_get month
     in
       (if (month < 1) || (month > 12)
        then invalid_arg "Netdate.parse"
        else ();
        {
          year = may_get year;
          month = month;
          day = may_get day;
          hour = get_default 0 hour;
          minute = get_default 0 minute;
          second = get_default 0 second;
          zone = get_default dzone zone;
          week_day = get_default (-1) week_day;
        }))
  
let months_start =
  [| 0; 31; 59; 90; 120; 151; 181; 212; 243; 273; 304; 334 |]
  
let is_leap year =
  ((year mod 4) = 0) && (((year mod 100) <> 0) || ((year mod 400) = 0))
  
let since_epoch date =
  (if (date.month < 1) || (date.month > 12)
   then invalid_arg "Parse.since_epoch"
   else ();
   let in_day =
     float_of_int
       (((date.hour * 3600) + ((date.minute - date.zone) * 60)) + date.second) in
   let days =
     ((((date.year * 365) + ((date.year + 3) / 4)) - ((date.year + 99) / 100))
        + ((date.year + 399) / 400))
       - 719528 in
   let days = ((days + months_start.(date.month - 1)) + date.day) - 1 in
   let days =
     if (is_leap date.year) && (date.month > 2) then days + 1 else days
   in (86400.0 *. (float_of_int days)) +. in_day)
  
let parse_epoch ?zone str = since_epoch (parse ?zone str)
  
let create ?(zone = 0) time =
  let time = time +. (float_of_int (zone * 60)) in
  let days = floor (time /. 86400.0) in
  let in_day = int_of_float (time -. (86400.0 *. days)) in
  let days = days +. 719528.0 in
  let n400 = floor (days /. 146097.0) in
  let r400 = int_of_float (days -. (n400 *. 146097.0)) in
  let n400 = int_of_float n400 in
  let (n100, r100) =
    if r400 < 36525
    then (0, r400)
    else (((r400 - 1) / 36524), ((r400 - 1) mod 36524)) in
  let (n4, r4) =
    if n100 = 0
    then ((r100 / 1461), (r100 mod 1461))
    else
      if r100 < 1460
      then (0, r100)
      else (((r100 + 1) / 1461), ((r100 + 1) mod 1461)) in
  let (n1, r1) =
    if (n4 = 0) && (n100 <> 0)
    then ((r4 / 365), (r4 mod 365))
    else if r4 < 366 then (0, r4) else (((r4 - 1) / 365), ((r4 - 1) mod 365)) in
  let year = (((400 * n400) + (100 * n100)) + (4 * n4)) + n1 in
  let month_start =
    if is_leap year
    then (fun m -> months_start.(m) + (if m > 1 then 1 else 0))
    else (fun m -> months_start.(m)) in
  let month_guess = r1 / 29 in
  let month =
    if month_guess = 12
    then 11
    else
      if r1 >= (month_start month_guess)
      then month_guess
      else month_guess - 1 in
  let second = in_day mod 60 and minutes = in_day / 60 in
  let minute = minutes mod 60
  and hour = minutes / 60
  in
    {
      year = year;
      month = month + 1;
      day = (r1 - (month_start month)) + 1;
      hour = hour;
      minute = minute;
      second = second;
      zone = zone;
      week_day = int_of_float (mod_float (days +. 6.0) 7.0);
    }
  
let full_day_names =
  [| "Sunday"; "Monday"; "Tuesday"; "Wednesday"; "Thursday"; "Friday";
    "Saturday"
  |]
  
let abbr_day_names = [| "Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat" |]
  
let full_month_names =
  [| "January"; "February"; "March"; "April"; "May"; "June"; "July";
    "August"; "September"; "October"; "November"; "December"
  |]
  
let abbr_month_names =
  [| "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep"; "Oct";
    "Nov"; "Dec"
  |]
  
let format_to out_ch ~fmt date =
  let add_char c = out_ch#output_char c
  and add_string s = out_ch#output_string s in
  let fail () = invalid_arg "Netdate.format_to" in
  let add_digits w b n =
    (if n >= (b * 10) then fail () else ();
     let rec aux b n =
       (add_char (char_of_int (48 + (n / b)));
        if b >= 10 then aux (b / 10) (n mod b) else ())
     in
       if w
       then
         (let rec aux_spaces b =
            if (n >= b) || (b < 10)
            then aux b n
            else (add_char ' '; aux_spaces (b / 10))
          in aux_spaces b)
       else aux b n) in
  let wd () =
    (if (date.week_day < 0) || (date.week_day > 6) then fail () else ();
     date.week_day) in
  let yd () = months_start.(date.month - 1) + date.day in
  let rec do_format ?(have_colon = false) =
    function
    | 'a' -> add_string abbr_day_names.(date.week_day)
    | 'A' -> add_string full_day_names.(date.week_day)
    | 'b' | 'h' -> add_string abbr_month_names.(date.month - 1)
    | 'B' -> add_string full_month_names.(date.month - 1)
    | 'C' -> add_digits false 10 (date.year / 100)
    | 'd' -> add_digits false 10 date.day
    | 'e' -> add_digits true 10 date.day
    | 'H' -> add_digits false 10 date.hour
    | 'I' ->
        add_digits false 10 (match date.hour mod 12 with | 0 -> 12 | d -> d)
    | 'j' -> add_digits false 100 (yd ())
    | 'k' -> add_digits true 10 date.hour
    | 'l' ->
        add_digits true 10 (match date.hour mod 12 with | 0 -> 12 | d -> d)
    | 'm' -> add_digits false 10 date.month
    | 'M' -> add_digits false 10 date.minute
    | 'n' -> add_char '\n'
    | 'p' -> add_string (if date.hour >= 12 then "PM" else "AM")
    | 'P' -> add_string (if date.hour >= 12 then "pm" else "am")
    | 'S' -> add_digits false 10 date.second
    | 't' -> add_char '\t'
    | 'u' -> add_digits false 1 (match wd () with | 0 -> 7 | n -> n)
    | 'y' -> add_digits false 10 (date.year mod 100)
    | 'Y' -> add_digits false 1000 date.year
    | 'z' ->
        let (s, z) =
          if date.zone >= 0 then ('+', (date.zone)) else ('-', (- date.zone))
        in
          (add_char s;
           add_digits false 10 (z / 60);
           if have_colon then add_char ':' else ();
           add_digits false 10 (z mod 60))
    | 'U' -> add_digits false 10 ((((yd ()) - (wd ())) + 6) / 7)
    | 'V' -> failwith "TODO"
    | 'W' -> failwith "TODO"
    | 'w' -> add_digits false 1 (wd ())
    | '%' -> add_char '%'
    | 'c' ->
        (do_format 'a';
         add_char ' ';
         do_format 'b';
         add_char ' ';
         do_format 'e';
         add_char ' ';
         do_format 'T';
         add_char ' ';
         do_format 'Y')
    | 'D' | 'x' ->
        (do_format 'm';
         add_char '/';
         do_format 'd';
         add_char '/';
         do_format 'y')
    | 'r' ->
        (do_format 'I';
         add_char ':';
         do_format 'M';
         add_char ':';
         do_format 'S';
         add_char ' ';
         do_format 'p')
    | 'R' -> (do_format 'H'; add_char ':'; do_format 'M')
    | 'T' | 'X' -> (do_format 'R'; add_char ':'; do_format 'S')
    | _ -> fail () in
  let rec aux i =
    if i = (String.length fmt)
    then ()
    else
      (match fmt.[i] with
       | '%' when i = ((String.length fmt) - 1) -> fail ()
       | '%' ->
           if fmt.[i + 1] = ':'
           then (do_format ~have_colon: true fmt.[i + 2]; aux (i + 3))
           else (do_format fmt.[i + 1]; aux (i + 2))
       | c -> (add_char c; aux (i + 1)))
  in try aux 0 with | _ -> fail ()
  
let format ~fmt date =
  let b = Buffer.create ((String.length fmt) * 2)
  in
    (format_to (new Netchannels.output_buffer b) ~fmt date;
     Buffer.contents b)
  
(* Calculate local zone offset in minutes *)
let localzone =
  let t = Unix.time () in
  let gt = Unix.gmtime t and lt = Unix.localtime t in
  let min_diff =
    ((lt.Unix.tm_hour * 60) + lt.Unix.tm_min) -
      ((gt.Unix.tm_hour * 60) + gt.Unix.tm_min) in
  let day_diff = lt.Unix.tm_yday - gt.Unix.tm_yday
  in
    if (day_diff < (-1)) || (day_diff = 1)
    then (* local day is UTC day + 1 *) min_diff + (24 * 60)
    else
      if (day_diff > 1) || (day_diff = (-1))
      then (* local day is UTC day - 1 *) min_diff - (24 * 60)
      else (* local day is UTC day *) min_diff
  
(* The format routines above may want to support internationalization
 * in the future. The following must use the English conventions
 * described in the relevant RFCs.
 *)
let mk_mail_date ?zone t = format "%a, %d %b %Y %H:%M:%S %z" (create ?zone t)
  
let mk_usenet_date ?zone t =
  format "%A, %d-%b-%y %H:%M:%S %z" (create ?zone t)
  
let mk_internet_date ?zone t = format "%Y-%m-%dT%H:%M:%S%:z" (create ?zone t)
  

