(*s: unparse_php.ml *)
(*s: Facebook copyright *)
(* Yoann Padioleau
 * 
 * Copyright (C) 2009-2013 Facebook
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
(*e: Facebook copyright *)
open Common 

open Ast_php 
open Parser_php (* the tokens *)
open Parse_info

module Ast = Ast_php
module V = Visitor_php
module TH = Token_helpers_php
module PI = Parse_info

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
 * There are multiple ways to unparse PHP code:
 *  - one can iterate over the AST, and print its leaves, but 
 *    comments and spaces are not in the AST right now so you need
 *    some extra code that also visits the tokens and try to "sync" the
 *    visit of the AST with the tokens
 *  - one can iterate over the tokens, where comments and spaces are normal
 *    citizens, but this can be too low level
 *  - one can use a real pretty printer with a boxing or backtracking model
 *    working on a AST extended with comments (see julien's ast_pretty_print/)
 * 
 * Right now the preferred method for spatch is the second one. The pretty
 * printer currently is too different from our coding conventions
 * (also because we don't have precise coding conventions).
 * This token-based unparser handles transfo annotations (Add/Remove).
 * 
 * related: the sexp/json "exporters".
 * 
 * note: this module could be in analyze_php/ instead of parsing_php/, 
 * but it's maybe good to have the basic parser/unparser together.
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(*****************************************************************************)
(* Unparsing using AST visitor *)
(*****************************************************************************)

(* This will not preserve space and comments but it's useful
 * and good enough for printing small chunk of PHP code for debugging
 * purpose. We try to preserve the line numbers.
 *)
let string_of_program ast = 
  Common2.with_open_stringbuf (fun (_pr_with_nl, buf) ->
    let pp s = Buffer.add_string buf s in
    let cur_line = ref 1 in

    pp "<?php";
    pp "\n"; 
    incr cur_line;

    let visitor = V.mk_visitor { V.default_visitor with
      V.kinfo = (fun (k, _) info ->
        match info.Parse_info.token with
        | Parse_info.OriginTok p ->
            let line = p.Parse_info.line in 
            if line > !cur_line
            then begin
              (line - !cur_line) +> Common2.times (fun () -> pp "\n"); 
              cur_line := line;
            end;
            let s =  p.Parse_info.str in
            pp s; pp " ";
        | Parse_info.FakeTokStr (s, _opt) ->
            pp s; pp " ";
            if s = ";" 
            then begin
              pp "\n";
              incr cur_line;
            end
        | Parse_info.Ab ->
            ()
        | Parse_info.ExpandedTok _ ->
            raise Todo
      );
    }
    in
    visitor (Program ast);
  )

(*****************************************************************************)
(* Even simpler unparser using AST visitor *)
(*****************************************************************************)

let mk_unparser_visitor pp = 
  let hooks = { V.default_visitor with
    V.kinfo = (fun (k, _) info ->
      match info.Parse_info.token with
      | Parse_info.OriginTok p ->
          let s =  p.Parse_info.str in
          (match s with
          | "new" ->
              pp s; pp " "
          | _ -> 
              pp s;
          )
      | Parse_info.FakeTokStr (s, _opt) ->
          pp s; pp " ";
          if s = ";" || s = "{" || s = "}"
          then begin
            pp "\n";
          end

      | Parse_info.Ab
        ->
          ()
      | Parse_info.ExpandedTok _ -> raise Todo
    );
  }
  in
  (V.mk_visitor hooks)
   

let string_of_infos ii = 
  (* todo: keep space, keep comments *)
  ii +> List.map (fun info -> PI.str_of_info info) +> Common.join ""

let string_of_expr_old e = 
  let ii = Lib_parsing_php.ii_of_any (Expr e) in
  string_of_infos ii

let string_of_any any = 
  Common2.with_open_stringbuf (fun (_pr_with_nl, buf) ->
    let pp s = Buffer.add_string buf s in
    (mk_unparser_visitor pp) any
  )

(* convenient shortcut *)
let string_of_expr x = string_of_any (Expr x)

(*****************************************************************************)
(* Transformation-aware unparser (using the tokens) *)
(*****************************************************************************)

open Lib_unparser

let elt_of_tok tok =
  let str = TH.str_of_tok tok in
  match tok with
  | T_COMMENT _ | T_DOC_COMMENT _ -> Esthet (Comment str)
  | TSpaces _ -> Esthet (Space str)
  | TNewline _ -> Esthet Newline
  (* just after a ?>, the newline are not anymore TNewline but that *)
  | T_INLINE_HTML ("\n", _) -> Esthet Newline
  | _ -> OrigElt str

(* less:
 * - use a AddedBefore where should use a AddedAfter on bar.spatch
 * - put some newline in the Added of a spatch, add_statement.spatch
 *   too many places where we do ugly hack around newline
 *)

let string_of_program_with_comments_using_transfo (ast, toks) =
 toks +> Lib_unparser.string_of_toks_using_transfo 
   ~elt_and_info_of_tok:(fun tok ->
     elt_of_tok tok, TH.info_of_tok tok
   )
(*e: unparse_php.ml *)
