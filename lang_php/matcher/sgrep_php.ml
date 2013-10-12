(* Yoann Padioleau
 *
 * Copyright (C) 2010-2012 Facebook
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

open Ast_php
open Parse_info
module Ast = Ast_php
module V = Visitor_php
module PI = Parse_info

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* See https://github.com/facebook/pfff/wiki/Sgrep 
 *
 * todo? many things are easier in sgrep than in spatch. For instance
 * many isomorphisms are ok to do in sgrep but would result in badly
 * generated code for spatch (e.g. the order of the attributes in Xhp
 * does not matter). Using ast_php.ml has many disadvantages
 * for sgrep; it complicates things. Maybe we should use
 * a unsugar AST a la PIL to do the maching and the concrete AST for
 * transforming. For instance the Xhp vs XhpSingleton isomorphisms would
 * not even be needed in an unsugared AST. At the same time it's
 * convenient to have a single php_vs_php.ml that kinda works
 * both for sgrep and spatch at the same time.
 *)

(*****************************************************************************)
(* Type *)
(*****************************************************************************)

(* right now only Expr and Stmt are actually supported *)
type pattern = Ast_php.any

(*****************************************************************************)
(* Parsing *)
(*****************************************************************************)

(* We can't have Flag_parsing_php.case_sensitive set to false here
 * because metavariables in sgrep patterns are in uppercase
 * and we don't want to lowercase them.
 * 
 * We actually can't use Flag_parsing_php.case_sensitive at all
 * because we also want the Foo() pattern to match foo() code
 * so we have anyway to do some case insensitive string
 * comparisons in php_vs_php.ml
 *)
let parse str =
  Common.save_excursion Flag_parsing_php.sgrep_mode true (fun () ->
    Parse_php.any_of_string str +> Metavars_php.check_pattern
  )

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let sgrep ?(case_sensitive=false) ~hook pattern file =
  let ast = 
    try 
      Parse_php.parse_program file
    with Parse_php.Parse_error err ->
      (* we usually do sgrep on a set of files or directories,
       * so we don't want on error in one file to stop the
       * whole process.
       *)
      Common.pr2 (spf "warning: parsing problem in %s" file);
      []
  in

  (* coupling: copy paste with lang_php/matcher/spatch_php.ml 
   * coupling: copy paste with sgrep_lint
   *)
  let hook = 
    match pattern with
    (* bugfix: if we have an ExprVar, then a pattern such as 
     * $foo->method() will not match expressions such as 
     * $foo->method()->method because the full ExprVar will not
     * match. The pb is that we need not only a match_e_e but also
     * a match_v_v with the same visitor. For each recursive
     * types inside a recursive types, we need to do that
     * (for now lvalue and xhp_html).
     *)
    | Expr (XhpHtml xhp) ->
        { V.default_visitor with
          V.kxhp_html = (fun (k, _) x ->
            let matches_with_env =  
              Matching_php.match_xhp_xhp xhp x
            in 
            if matches_with_env = []
            then k x
            else begin
              (* could also recurse to find nested matching inside
               * the matched code itself.
               *)
              let matched_tokens = Lib_parsing_php.ii_of_any (XhpHtml2 x) in
              matches_with_env +> List.iter (fun env -> 
                hook env matched_tokens
              )
            end
          );
        }

    | Expr pattern_expr ->
        { V.default_visitor with
          V.kexpr = (fun (k, _) x ->
            let matches_with_env =  
              Matching_php.match_e_e pattern_expr  x
            in
            if matches_with_env = []
            then k x
            else begin
              (* could also recurse to find nested matching inside
               * the matched code itself.
               *)
              let matched_tokens = Lib_parsing_php.ii_of_any (Expr x) in
              matches_with_env +> List.iter (fun env ->
                hook env matched_tokens
              )
            end
          );
        }
    | Stmt2 pattern ->
        { V.default_visitor with
          V.kstmt = (fun (k, _) x ->
            let matches_with_env =  
              Matching_php.match_st_st pattern x
            in
            if matches_with_env = []
            then k x
            else begin
              (* could also recurse to find nested matching inside
               * the matched code itself.
               *)
              let matched_tokens = Lib_parsing_php.ii_of_any (Stmt2 x) in
              matches_with_env +> List.iter (fun env ->
                hook env matched_tokens
              )
            end
          );
        }

    | _ -> failwith (spf "pattern not yet supported:" ^ 
                        Export_ast_php.ml_pattern_string_of_any pattern)
  in
  (* opti ? dont analyze func if no constant in it ?*)
  Common.save_excursion Php_vs_php.case_sensitive case_sensitive (fun() ->
    (V.mk_visitor hook) (Program ast)
  )

