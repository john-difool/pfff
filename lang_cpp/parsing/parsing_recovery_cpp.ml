(* Yoann Padioleau
 * 
 * Copyright (C) 2006, 2007, 2008 Ecole des Mines de Nantes
 * Copyright (C) 2011 Facebook
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License (GPL)
 * version 2 as published by the Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * file license.txt for more details.
 *)

open Common

module TH = Token_helpers_cpp

module Parser = Parser_cpp

(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)
let pr2_err, pr2_once = Common2.mk_pr2_wrappers Flag_parsing_cpp.verbose_parsing 

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(*****************************************************************************)
(* Skipping stuff, find next "synchronisation" point *)
(*****************************************************************************)

(* todo: do something if find Parser.Eof ? *)
let rec find_next_synchro ~next ~already_passed =

  (* Maybe because not enough }, because for example an ifdef contains
   * in both branch some opening {, we later eat too much, "on deborde
   * sur la fonction d'apres". So already_passed may be too big and
   * looking for next synchro point starting from next may not be the
   * best. So maybe we can find synchro point inside already_passed
   * instead of looking in next.
   * 
   * But take care! must progress. We must not stay in infinite loop!
   * For instance now I have as a error recovery to look for 
   * a "start of something", corresponding to start of function,
   * but must go beyond this start otherwise will loop.
   * So look at premier(external_declaration2) in parser.output and
   * pass at least those first tokens.
   * 
   * I have chosen to start search for next synchro point after the
   * first { I found, so quite sure we will not loop. *)

  let last_round = List.rev already_passed in
  let is_define = 
    let xs = last_round +> List.filter TH.is_not_comment in
    match xs with
    | Parser.TDefine _::_ -> true
    | _ -> false
  in
  if is_define 
  then find_next_synchro_define (last_round ++ next) []
  else 

  let (before, after) = 
    last_round +> Common.span (fun tok -> 
      match tok with
      (* by looking at TOBrace we are sure that the "start of something"
       * will not arrive too early 
       *)
      | Parser.TOBrace _ -> false
      | Parser.TDefine _ -> false
      | _ -> true
    ) 
  in
  find_next_synchro_orig (after ++ next)  (List.rev before)

    

and find_next_synchro_define next already_passed =
  match next with
  | [] ->  
      pr2_err "ERROR-RECOV: end of file while in recovery mode"; 
      already_passed, []
  | (Parser.TCommentNewline_DefineEndOfMacro i as v)::xs  -> 
      pr2_err ("ERROR-RECOV: found sync end of #define "^i_to_s(TH.line_of_tok v));
      v::already_passed, xs
  | v::xs -> 
      find_next_synchro_define xs (v::already_passed)


    

and find_next_synchro_orig next already_passed =
  match next with
  | [] ->  
      pr2_err "ERROR-RECOV: end of file while in recovery mode"; 
      already_passed, []

  | (Parser.TCBrace i as v)::xs when TH.col_of_tok v = 0 -> 
      pr2_err ("ERROR-RECOV: found sync '}' at line "^i_to_s (TH.line_of_tok v));

      (match xs with
      | [] -> raise Impossible (* there is a EOF token normally *)

      (* still useful: now parser.mly allow empty ';' so normally no pb *)
      | Parser.TPtVirg iptvirg::xs -> 
          pr2_err "ERROR-RECOV: found sync bis, eating } and ;";
          (Parser.TPtVirg iptvirg)::v::already_passed, xs

      | Parser.TIdent x::Parser.TPtVirg iptvirg::xs -> 
          pr2_err "ERROR-RECOV: found sync bis, eating ident, }, and ;";
          (Parser.TPtVirg iptvirg)::(Parser.TIdent x)::v::already_passed, 
          xs
            
      | Parser.TCommentSpace sp::Parser.TIdent x::Parser.TPtVirg iptvirg
        ::xs -> 
          pr2_err "ERROR-RECOV: found sync bis, eating ident, }, and ;";
          (Parser.TCommentSpace sp)::
            (Parser.TPtVirg iptvirg)::
            (Parser.TIdent x)::
            v::
            already_passed, 
          xs
            
      | _ -> 
          v::already_passed, xs
      )
  | v::xs when TH.col_of_tok v = 0 && TH.is_start_of_something v  -> 
      pr2_err ("ERROR-RECOV: found sync col 0 at line "^ i_to_s(TH.line_of_tok v));
      already_passed, v::xs
        
  | v::xs -> 
      find_next_synchro_orig xs (v::already_passed)

