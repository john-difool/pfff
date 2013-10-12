(*s: parser_php_mly_helper.ml *)
open Common

open Ast_php

(*****************************************************************************)
(* Parse helpers functions *)
(*****************************************************************************)
(*s: function top_statements_to_toplevels *)
let rec squash_stmt_list xs =
  match xs with
  | [] -> []
  | x::xs->
      let v, rest = 
        (match x with
        | (FuncDef _ | ClassDef _ | ConstantDef _ | TypeDef _
          | NamespaceDef _ | NamespaceBracketDef _ | NamespaceUse _
          ) -> x,  xs
        | StmtList [st] -> 
            let stmts, rest = xs +> Common.span (function
              | StmtList st -> true 
              | _ -> false
              ) in
            let stmts' = stmts +> List.map (function
              | StmtList [st] -> st
              | _ -> raise Impossible
            ) in
            StmtList (st::stmts'), rest
        | StmtList _ -> raise Impossible
        | (FinalDef _|NotParsedCorrectly _) -> raise Impossible
        )
      in
      v::squash_stmt_list rest
(*e: function top_statements_to_toplevels *)

(*****************************************************************************)
(* todo? *)
(*****************************************************************************)

(*
and refvar_to_variable refvar = 
  let v = 
    match refvar with
    | Var2 (name, scope) -> 
        (match name with
        | DName ("this", info) -> 
            This (info)
        | _ -> 
            Var(name, scope)
        )

    | VDollar2 (tok, exprp) -> VBrace(tok, exprp)
    | VArrayAccess2(refvar, exprb) -> 
        let v = refvar_to_variable refvar in
        VArrayAccess(v, exprb)
    | VBraceAccess2(refvar, exprb) ->
        let v = refvar_to_variable refvar in
        VBraceAccess(v, exprb)
  in
  v
*)

(* even if A::$v['fld'] is parsed in the grammar
 * as a Qualifier(A, ArrayAccess($v, 'fld') we should really
 * generate a ArrayAccess(Qualifier(A, $v), 'fld').
 * 
 * So this function try to put the qualifier closer to the variable
 * it is attached to. We must recurse when we have ArrayAccess to
 * access the deaper variable. We must stop when there is an indirect
 * because A::$$v should not be parsed as $(A::$v).
 *)
(*
and lift_qualifier_closer_to_var qu v =

  let rec aux v =
    match v with
    | Indirect _ | VBrace _ | VBraceAccess _ -> 
        raise Not_found
    | VArrayAccess (lval, e) ->
        let lval' = aux lval in
        VArrayAccess (lval', e)
    | Var (name, scope) ->
        (match qu with
        | Left3 qu -> 
            (ClassVar (qu, name))
        | Middle3 (tok1, tok2) ->
            raise Impossible
        | Right3 (refvar, tok) ->
            let v = refvar_to_variable refvar in
            (DynamicClassVar (v, tok, (Var (name, scope))))
        )
    | This _ ->
        failwith "todo: what mean A::this ?"

    (* v should have been build via vwithoutobj_to_variable so
     * we should see only a restrict set of lvalue constructor here
     *)
    | _ -> raise Impossible
  in
  try 
    aux v
  with Not_found -> 
    (match qu with
    | Left3 qu ->
        (VQualifier (qu, v))
    | Middle3 _ ->
        (* todo: static::$... ? *) 
        raise Parsing.Parse_error
    | Right3 (refvar, tok) ->
        let v2 = refvar_to_variable refvar in
        (* e.g. when parse $class::$$prop *)
        (DynamicClassVar (v2, tok, v))
    )
*)    

(*****************************************************************************)
(* XHP *)
(*****************************************************************************)
let failwith_xhp_ambiguity_colon info =
  let err = 
    "XHP: ambiguity on ':', please put a space after the colon in " ^
      Parse_info.string_of_info info
  in
  (*failwith err*)
  pr2 err;
  raise Parsing.Parse_error

let failwith_xhp_ambiguity_percent info =
  let err = 
    "XHP: ambiguity on '%', please put a space after the percent in " ^
      Parse_info.string_of_info info
  in
  (*failwith err*)
  pr2 err;
  raise Parsing.Parse_error

(*****************************************************************************)
(* Sgrep *)
(*****************************************************************************)
let sgrep_guard v = 
  if !Flag_parsing_php.sgrep_mode
  then v
  else raise Parsing.Parse_error

(*****************************************************************************)
(* Xdebug *)
(*****************************************************************************)

(* todo: xdebug_guard *)

(*****************************************************************************)
(* generics *)
(*****************************************************************************)

(* Split a single (assumed to be 2-chars wide) info and turn it
   into a (1-char) lhs and rhs. Used to convert `>>` into two `>`
*)
let split_two_char pi =
  let lhs = { pi with Parse_info.str = String.sub pi.Parse_info.str 0 1 } in
  let rhs = { pi with Parse_info.str = String.sub pi.Parse_info.str 1 1;
                     Parse_info.charpos = pi.Parse_info.charpos + 1;
                     Parse_info.column = pi.Parse_info.column + 1 } in
  (lhs, rhs)

let split_two_char_info i =
  let tok = match i.Parse_info.token with
    | Parse_info.OriginTok t -> t
    | _ -> failwith "Parse error..."
  in

  let lhspi, rhspi = split_two_char tok in
  let lhs = { Parse_info.token = Parse_info.OriginTok lhspi;
              Parse_info.transfo = Parse_info.NoTransfo
            } in
  let rhs = { Parse_info.token = Parse_info.OriginTok rhspi;
              Parse_info.transfo = Parse_info.NoTransfo
            } in
  (lhs, rhs)

(*****************************************************************************)
(* shortcuts *)
(*****************************************************************************)
(*s: AST builder *)
let mk_param s = 
  { p_type = None;
    p_attrs = None;
    p_ref = None;
    p_name = DName s;
    p_default = None;
    p_modifier = None;
    p_soft_type = None;
  }
(* old:  e, Ast_php.noType() *)
let mk_e e = e

let mk_var (s, tok) = 
  match s with
  | "this" -> This tok
  | _ -> IdVar (DName(s, tok), Ast_php.noScope())

(*e: AST builder *)
(*e: parser_php_mly_helper.ml *)
