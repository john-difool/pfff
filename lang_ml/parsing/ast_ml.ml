(* Yoann Padioleau
 *
 * Copyright (C) 2010, 2012 Facebook
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

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*****************************************************************************)
(* The AST related types *)
(*****************************************************************************)

(* ------------------------------------------------------------------------- *)
(* Token/info *)
(* ------------------------------------------------------------------------- *)
type tok = Parse_info.info

(* a shortcut to annotate some information with token/position information *)
and 'a wrap = 'a * tok

and 'a paren   = tok * 'a * tok
and 'a brace   = tok * 'a * tok
and 'a bracket = tok * 'a * tok 

and 'a comma_list = ('a, tok (* ',' *)) Common.either list
and 'a and_list = ('a, tok (* 'and' *)) Common.either list

(* optional first | *)
and 'a pipe_list = ('a, tok (* '*' *)) Common.either list
(* optional final ; *)
and 'a semicolon_list = ('a, tok (* ';' *)) Common.either list

and 'a star_list = ('a, tok (* '*' *)) Common.either list

 (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* Names  *)
(* ------------------------------------------------------------------------- *)
type name = Name of string wrap

  (* lower and uppernames aliases, just for clarity *)
  and lname = name
  and uname = name

 (* with tarzan *)

type long_name = qualifier * name
 and qualifier = (name * tok (*'.'*)) list

 (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* Types *)
(* ------------------------------------------------------------------------- *)

type ty = 
  | TyName of long_name
  | TyVar of tok (* ' *) * name

  | TyTuple of ty star_list (* at least 2 *)
  | TyTuple2 of ty star_list paren (* at least 1 *)
  | TyFunction of ty * tok (* -> *) * ty
  | TyApp of ty_args * long_name (* todo? could be merged with TyName *)

  | TyTodo


and type_declaration =
  | TyAbstract of ty_params * name
  | TyDef of ty_params * name * tok (* = *) * type_def_kind

 and type_def_kind =
   | TyCore of ty
   | TyAlgebric of constructor_declaration pipe_list
   | TyRecord   of field_declaration semicolon_list brace

 (* OR type: algebric data type *)
 and constructor_declaration = name (* constr_ident *) * constructor_arguments
  and constructor_arguments =
    | NoConstrArg
    | Of of tok * ty star_list

 (* AND type: record *)
 and field_declaration = {
   fld_mutable: tok option;
   fld_name: name;
   fld_tok: tok; (* : *)
   fld_type: ty; (* poly_type ?? *)
 }



 and ty_args = 
    | TyArg1 of ty
    | TyArgMulti of ty comma_list paren
    (* todo? | TyNoArg and merge TyName and TyApp ? *)

 and ty_params =
   | TyNoParam
   | TyParam1 of ty_parameter
   | TyParamMulti of ty_parameter comma_list paren
 and ty_parameter = tok (* ' *) * name (* a TyVar *)


(* ------------------------------------------------------------------------- *)
(* Expressions *)
(* ------------------------------------------------------------------------- *)
and expr =
  | C of constant
  | L of long_name (* val_longident *)

  | Constr(*Algebric*) of long_name (* constr_longident *) * expr option
  | Tuple of expr comma_list
  | List of expr semicolon_list bracket

  (* can be empty; can not be singular as we use instead ParenExpr *) 
  | Sequence of seq_expr paren (* can also be 'begin'/'end' *)

  | Prefix of string wrap * expr
  | Infix of expr * string wrap * expr

  | FunCallSimple of long_name * argument list
  | FunCall of expr * argument list

  (* could be factorized with Prefix but it's not a usual prefix operator! *)
  | RefAccess of tok (* ! *) * expr
  | RefAssign of expr * tok (* := *) * expr

  | FieldAccess of expr * tok (* . *) * long_name
  | FieldAssign of expr * tok (* . *) * long_name * tok (* <- *) * expr
  | Record of record_expr brace

  | New of tok * long_name (* class_longident *)
  | ObjAccess of expr * tok (* # *) * name
  

  | LetIn of tok * rec_opt * let_binding and_list * tok (* in *) * seq_expr
  | Fun of tok * parameter list (* at least one *) * match_action
  | Function of tok * match_case pipe_list

  (* why they allow seq_expr ?? *)
  | If of tok * seq_expr * tok * expr * (tok * expr) option
  | Match of tok * seq_expr * tok * match_case pipe_list

  | Try of tok * seq_expr * tok * match_case pipe_list 

  | While of tok * seq_expr * tok * seq_expr * tok
  | For of tok * name * tok * seq_expr * for_direction * seq_expr * 
           tok * seq_expr * tok

  | ParenExpr of expr paren
  (* todo: LetOpenIn *)
  | ExprTodo

and seq_expr = expr semicolon_list

 and constant =
   | Int of string wrap
   | Float of string wrap
   | Char of string wrap
   | String of string wrap

 and record_expr =
   | RecordNormal of            field_and_expr semicolon_list
   | RecordWith of expr * tok * field_and_expr semicolon_list
   and field_and_expr = 
     | FieldExpr of long_name * tok (* = *) * expr
     (* new 3.12 feature *)
     | FieldImplicitExpr of long_name

 and argument = 
   | ArgExpr of expr

   | ArgLabelTilde of name (* todo: without the tilde and : ? *) * expr
   | ArgImplicitTildeExpr of tok * name

   (* apparently can do 'foo ?attr:1' *)
   | ArgLabelQuestion of name (* todo: without the tilde and : ? *) * expr
   | ArgImplicitQuestionExpr of tok * name


 and match_case =
  pattern * match_action

  and match_action =
    | Action of tok (* -> *) * seq_expr
    | WhenAction of tok (* when *) * seq_expr * tok (* -> *) * seq_expr


 and for_direction =
  | To of tok
  | Downto of tok

 and rec_opt = tok option

(* ------------------------------------------------------------------------- *)
(* Patterns *)
(* ------------------------------------------------------------------------- *)
and pattern = 
  | PatVar of name
  | PatConstant of signed_constant
  | PatConstr(*Algebric*) of long_name (* constr_longident *) * pattern option
  | PatConsInfix of pattern * tok (* :: *) * pattern
  | PatTuple of pattern comma_list
  | PatList of pattern semicolon_list bracket
  | PatUnderscore of tok

  | PatAs of pattern * tok (* as *) * name
  (* ocaml disjunction patterns extension *)
  | PatDisj of pattern * tok (* | *) * pattern

  | PatTyped of tok (*'('*) * pattern * tok (*':'*) * ty * tok (*')'*)

  | ParenPat of pattern paren
  | PatTodo
    
 and labeled_simple_pattern = unit

 and parameter = labeled_simple_pattern

 and signed_constant = 
    | C2 of constant
    (* actually only valid for the Int and Float case, not Char and String
     * but don't want to introduce yet another intermediate type just for
     * the Int and Float
     *)
    | CMinus of tok * constant
    | CPlus of tok * constant

(* ------------------------------------------------------------------------- *)
(* Let binding *)
(* ------------------------------------------------------------------------- *)

and let_binding =
  | LetClassic of let_def
  | LetPattern of pattern * tok (* = *) * seq_expr

 (* was called fun_binding in the grammar *)
 and let_def = {
   l_name: name; (* val_ident *)
   l_args: parameter list; (* can be empty *)
   l_tok: tok; (* = *)
   l_body: seq_expr;
   (* todo: l_type: ty option *)
 }

(* ------------------------------------------------------------------------- *)
(* Module *)
(* ------------------------------------------------------------------------- *)
and module_type = unit

and module_expr =
  | ModuleName of long_name
  | ModuleStruct of tok (* struct *) * item list * tok (* end *)
  | ModuleTodo

(* ------------------------------------------------------------------------- *)
(* Class *)
(* ------------------------------------------------------------------------- *)

(* ------------------------------------------------------------------------- *)
(* Signature/Structure items *)
(* ------------------------------------------------------------------------- *)

(* could split in sig_item and struct_item but many constructions are
 * valid in both contexts.
 *)
and item = 
  | Type      of tok * type_declaration and_list

  | Exception of tok * name * constructor_arguments
  | External  of tok * name (* val_ident *) * tok (*:*) * ty * tok (* = *) *
      string wrap list (* primitive declarations *)
      
  | Open of tok * long_name
      
  (* only in sig_item *)
  | Val of tok * name (* val_ident *) * tok (*:*) * ty
      
  (* only in struct_item *)
  | Let of tok * rec_opt * let_binding and_list

  | Module of tok * uname * tok * module_expr
      
  | ItemTodo of tok

and sig_item = item
and struct_item = item

(* ------------------------------------------------------------------------- *)
(* Toplevel phrases *)
(* ------------------------------------------------------------------------- *)

and toplevel =
  | Item of item

  (* should both be removed *)
  | TopSeqExpr of seq_expr
  | ScSc of tok (* ;; *)

  (* some ml files contain some #! or even #load directives *)
  | TopDirective of tok

  | NotParsedCorrectly of tok list
  (* todo: could maybe get rid of that now that we don't really use
   * berkeley DB and prefer Prolog, and so we don't need a sentinel
   * ast elements to associate the comments with it
   *)
  | FinalDef of tok (* EOF *)

 and program = toplevel list

 (* with tarzan *)

(*****************************************************************************)
(* Any *)
(*****************************************************************************)

type any =
  | Ty of ty
  | Expr of expr
  | Pattern of pattern

  | Item2 of item
  | Toplevel of toplevel
  | Program of program

  | TypeDeclaration of type_declaration
  | TypeDefKind of type_def_kind
  | FieldDeclaration of field_declaration

  | MatchCase of match_case
  | LetBinding of let_binding

  | Constant of constant

  | Argument of argument
  | Body of seq_expr

  | Info of tok
  | InfoList of tok list
  (* with tarzan *)

(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)

let str_of_name (Name (s,_)) = s
let info_of_name (Name (_,info)) = info

let uncomma xs = Common.map_filter (function
  | Left e -> Some e
  | Right info -> None
  ) xs
let unpipe xs = uncomma xs

let name_of_long_name (_, name) = name
let module_of_long_name (qu, _) = 
  qu +> List.map fst +> List.map str_of_name +> Common.join "."
let module_infos_of_long_name (qu, _) = 
  qu +> List.map fst +> List.map info_of_name

let ast_todo = ()
let ast_todo2 = []
