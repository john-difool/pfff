(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)

open Common

open Parser_nw

module Ast = Ast_nw
module PI = Parse_info

(*****************************************************************************)
(* Token Helpers *)
(*****************************************************************************)

let is_eof = function
  | EOF _ -> true
  | _ -> false

let is_comment = function
  | TComment _ | TCommentSpace _ | TCommentNewline _ -> true
  | _ -> false 

let is_just_comment = function
  | TComment _ -> true
  | _ -> false 

(*****************************************************************************)
(* Visitors *)
(*****************************************************************************)
let visitor_info_of_tok f = function
  | TComment ii -> TComment (f ii)
  | TCommentSpace ii -> TCommentSpace (f ii)
  | TCommentNewline ii -> TCommentNewline (f ii)

  | TCommand (s, ii) -> TCommand (s, f ii)

  | TOBrace ii -> TOBrace (f ii)
  | TCBrace ii -> TCBrace (f ii)

  | TWord (s, ii) -> TWord (s, f ii)
  | TSymbol (s, ii) -> TSymbol (s, f ii)
  | TNumber (s, ii) -> TNumber (s, f ii)

  | TBeginVerbatim ii -> TBeginVerbatim (f ii)
  | TEndVerbatim ii -> TEndVerbatim (f ii)
  | TVerbatimLine (s, ii) -> TVerbatimLine (s, f ii)

  | TBeginNowebChunk ii -> TBeginNowebChunk (f ii)
  | TEndNowebChunk ii -> TEndNowebChunk (f ii)
  | TNowebChunkLine (s, ii) -> TNowebChunkLine (s, f ii)


  | TUnknown ii -> TUnknown (f ii)
  | EOF ii -> EOF (f ii)

let info_of_tok tok = 
  let res = ref None in
  visitor_info_of_tok (fun ii -> res := Some ii; ii) tok +> ignore;
  Common2.some !res


(*****************************************************************************)
(* Accessors *)
(*****************************************************************************)

let linecol_of_tok tok =
  let info = info_of_tok tok in
  PI.line_of_info info, PI.col_of_info info

let col_of_tok x  = snd (linecol_of_tok x)
let line_of_tok x = fst (linecol_of_tok x)

let str_of_tok  x = PI.str_of_info  (info_of_tok x)
let file_of_tok x = PI.file_of_info (info_of_tok x)
