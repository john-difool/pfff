open Common

open Ast_web
module Ast = Ast_web
module Flag = Flag_parsing_web

open OUnit

(*****************************************************************************)
(* Subsystem testing *)
(*****************************************************************************)

let test_tokens_web file = 
  if not (file =~ ".*\\.html") 
  then pr2 "warning: seems not a html file";
  raise Todo


let test_parse_web xs =
  raise Todo


let test_dump_web file =
  let (ast, toks) = Parse_web.parse file in
  let s = Export_web.ml_pattern_string_of_web_document ast in
  pr2 s


(*****************************************************************************)
(* Main entry for Arg *)
(*****************************************************************************)

let actions () = [
  "-tokens_web", "   <file>", 
  Common.mk_action_1_arg test_tokens_web;
  "-parse_web", "   <files or dirs>", 
  Common.mk_action_n_arg test_parse_web;
  "-dump_web", "   <file>", 
  Common.mk_action_1_arg test_dump_web;
]
