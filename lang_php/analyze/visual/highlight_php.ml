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

open Ast_php
open Highlight_code
module Ast = Ast_php
module V = Visitor_php
module T = Parser_php
module S = Scope_code
module Db = Database_code

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*****************************************************************************)
(* Helpers when have global analysis information *)
(*****************************************************************************)

(* todo: should do that generically via the light db.
 * look if def in same file of current file
 *)
let place_ids current_file ids db =
  match ids with
  | [] -> NoInfoPlace
  | [x] ->
      let other_file = 
        (* DbPHP.filename_of_id x db *)
        "TODO"
      in
      if other_file = current_file
      then PlaceLocal
      else
        if Common2.dirname current_file =
           Common2.dirname other_file
        then PlaceSameDir
        else PlaceExternal

  | x::y::xs ->
      let other_files =
        List.map (fun id -> 
          "TODO"
          (* DbPHP.filename_of_id id db *)
        ) ids +> Common2.uniq
      in
      if List.mem current_file other_files
      then PlaceLocal
      else
        if List.exists (fun other_file ->
          Common2.dirname current_file =
          Common2.dirname other_file
        ) other_files
        then PlaceSameDir
        else PlaceExternal

(* obsolete: this is now computed generically in pfff_visual via the light_db
 * in rewrite_categ_using_entities using x.e_number_external_users.
 *)
let arity_of_number nbuses =
  match nbuses with
  | 0 -> NoUse
  | 1 -> UniqueUse
  | n when n < 50 -> MultiUse
  | _ -> LotsOfUse

let use_arity_ident_function_or_macro s db =
  let ids = 
    (* DbPHP.function_ids__of_string s db *)
    []
  in
  let nbuses =
    ids +> List.map (fun id ->
      try
        let callers =
          (* db.DbPHP.uses.DbPHP.callers_of_f#assoc id in*)
          []
        in
        List.length callers
      with Not_found -> 0
    )
    +> Common2.sum_int
  in
  arity_of_number nbuses

(* we generate fake value here because the real one are computed in a
 * later phase in rewrite_categ_using_entities in pfff_visual.
 *)
let fake_no_def2 = NoUse
let fake_no_use2 = (NoInfoPlace, UniqueDef, MultiUse)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(* strings are more than just strings in PHP (and webapps in general) *)
let tag_string ~tag s ii =
  match s with
  | s when s =~ "/.*"       -> tag ii EmbededUrl
  | s when s =~ "[a-z]+://" -> tag ii EmbededUrl
  (* security: html in strings is BAD ! *)
  | s when s =~ "<" -> tag ii BadSmell
  | _ -> tag ii String

(*****************************************************************************)
(* Properties highlighter *)
(*****************************************************************************)

let highlight_funcall_simple ~tag ~hentities f args info =
  if Hashtbl.mem Env_php.hdynamic_call_wrappers f
  then begin
    match args with
    | [] -> failwith "dynamic call wrappers should have arguments"
    | x::xs ->
        (* alternative: could also have a FunCallVarBuiltins
         * but any wrappers around call_user_func should also
         * be considered as dangerous. Better to use
         * the ContainDynamicCall of database_code then.
         *)
        let ii = Lib_parsing_php.ii_of_any (Argument x) in
        ii +> List.iter (fun info -> tag info PointerCall);
  end;
  (match () with
  (* security: *)
  | _ when Hashtbl.mem Env_php.hbad_functions f ->
      tag info BadSmell
  | _ ->
      (match Hashtbl.find_all hentities f with
      | [e] ->
          let ps = e.Db.e_properties in

          (* dynamic call *)
          (if List.mem Db.ContainDynamicCall ps
          then
            (* todo: should try to find instead which arguments
             * is called dynamically using dataflow analysis
             *)
            tag info PointerCall
            else
              tag info (Function (Use2 fake_no_use2))
          );

          (* args by ref *)
          ps +> List.iter (function
          | Db.TakeArgNByRef i ->
              (try
                let a = List.nth args i in
                let ii = Lib_parsing_php.ii_of_any (Argument a) in
                ii +> List.iter (fun info -> tag info CallByRef)
              with exn ->
                pr2_once ("highlight_php: pb with TakeArgNByRef for " ^ f);
              )

          | Db.ContainDynamicCall -> ()
          | _ -> raise Todo
          );
          ()

      | x::y::xs ->
          pr2_once ("highlight_php: multiple entities for: " ^ f);

          (* todo: place of id *)
          tag info (Function (Use2 fake_no_use2));
      | [] ->
          (* todo: place of id *)
          tag info (Function (Use2 fake_no_use2));
      );
  );
  ()

(*****************************************************************************)
(* PHP Code highlighter *)
(*****************************************************************************)

(*
 * Visitor to help write an emacs-like php mode. Offer some
 * additional coloring and categories compared to font-lock-mode.
 * Offer also now also some semantic coloring and global-information
 * semantic feedback coloring!
 *
 * history:
 *  - I was using emacs_mode_xxx before but now have inlined the code
 *    and extended it.
 *
 * design: Can do either a single function that do all, or multiple independent
 * functions that repeatedly visit the same ast and tokens. The
 * former is faster (no forest) but less flexible. If for instance want you
 * to impose an order between the coloring, such as first keywords and
 * then yacfe specific coloring such as "expanded", then you need extra
 * stuff such as priority lists. If you have separate functions for those then
 * the caller can simply choose to call them in the order he wants so that
 * the last color win. Thus one can easily separate concerns.
 *
 * The idea of the code below is to visit the program either through its
 * AST or its list of tokens. The tokens are easier for tagging keywords,
 * number and basic entities. The Ast is better for tagging idents
 * to figure out what kind of ident it is (a function, a class, a constant)
 *)
let visit_program ~tag prefs  hentities (ast, toks) =

  let already_tagged = Hashtbl.create 101 in

  let tag = (fun ii categ ->
    (* with xhp lots of tokens such as 'var' can also be used
     * as attribute name so we must highlight them with their
     * generic keyword category only if there were not already
     * tagged.
     *
     * The same is true for other kinds of tokens.
     *)
    if not (Hashtbl.mem already_tagged ii)
    then begin
      tag ii categ;
      Hashtbl.add already_tagged ii true
    end
  )
  in

  (* -------------------------------------------------------------------- *)
  (* toks phase 1 *)
  (* -------------------------------------------------------------------- *)
  let rec aux_toks xs =
    match xs with
    | [] -> ()

    (* a little bit pad specific *)
    |   T.T_COMMENT(ii)
      ::T.TNewline (ii2)
      ::T.T_COMMENT(ii3)
      ::T.TNewline (ii4)
      ::T.T_COMMENT(ii5)
      ::xs ->
      let s = Parse_info.str_of_info ii in
      let s5 =  Parse_info.str_of_info ii5 in
      (match () with
      | _ when s =~ ".*\\*\\*\\*\\*" && s5 =~ ".*\\*\\*\\*\\*" ->
        tag ii CommentEstet;
        tag ii5 CommentEstet;
        tag ii3 CommentSection1
      | _ when s =~ ".*------" && s5 =~ ".*------" ->
        tag ii CommentEstet;
        tag ii5 CommentEstet;
        tag ii3 CommentSection2
      | _ when s =~ ".*####" && s5 =~ ".*####" ->
        tag ii CommentEstet;
        tag ii5 CommentEstet;
        tag ii3 CommentSection0
      | _ ->
        ()
      );
      aux_toks xs

    | x::xs ->
      aux_toks xs
  in
  aux_toks toks;

  (* -------------------------------------------------------------------- *)
  (* ast phase 1 *)
  (* -------------------------------------------------------------------- *)

  (* less: some of the logic duplicates what is in check_variables_php.ml
   * where we differentiate the diffent variables uses (parameters, static,
   * global, local, etc). See the pattern for Static, Global, parameter,
   * catch.
   *)
  let hooks = { V.default_visitor with

    (* -------------------------------------------------------------------- *)
    V.ktop = (fun (k, _) top ->
      match top with
      | ConstantDef def ->
        let info = Ast.info_of_ident def.cst_name in
        tag info (MacroVar (Def2 fake_no_def2));
        k top
      | _ -> k top
    );
    V.kfunc_def = (fun (k, vx) def ->
      let info = Ast.info_of_ident def.f_name in
      let kind =
        match def.f_type with
        | FunctionRegular | FunctionLambda ->
          tag def.f_tok Keyword;
          (Function (Def2 NoUse))

        | MethodRegular | MethodAbstract ->
          tag def.f_tok KeywordObject;
          if Class_php.is_static_method def
          then (StaticMethod (Def2 fake_no_def2))
          else (Method (Def2 fake_no_def2))
      in
      tag info kind;
      k def
    );

    V.kclass_def = (fun (k, vx) def ->
      let info = Ast.info_of_ident def.c_name in
      tag info (Class (Def2 fake_no_def2));
      def.c_extends +> Common.do_option (fun (tok, name) ->
        let name = name_of_class_name name in
        let info = Ast.info_of_name name in
        tag info (Class (Use2 fake_no_use2));
      );
      def.c_implements +> Common.do_option (fun (tok, xs) ->
        xs +> Ast.uncomma +> List.iter (fun name ->
          let name = name_of_class_name name in
          let info = Ast.info_of_name name in
          tag info (Class (Use2 fake_no_use2));
        );
      );
      k def
    );

    (* -------------------------------------------------------------------- *)
    V.kparameter = (fun (k, _) param ->
      let info = Ast.info_of_dname param.p_name in
      (* we highlight parameters passed by ref elsewhere *)
      if not (Hashtbl.mem already_tagged info)
      then begin
        (if param.p_ref = None
         then tag info (Parameter Def)
         else tag info ParameterRef
        );
      end;
      k param
    );

    (* -------------------------------------------------------------------- *)
    V.kclass_stmt = (fun (k, bigf) x ->
      match x with
      (* done in kfunc_def *)
      | Ast.Method def -> k x

      | Ast.XhpDecl d ->
        (match d with
        | XhpAttributesDecl _ -> k x
        | XhpChildrenDecl _ -> k x
        | XhpCategoriesDecl (tok, decls, tok2) ->
          decls +> Ast.uncomma +> List.iter (fun (_tag, ii) ->
            tag ii TypeMisc
          );
        )

      | Ast.ClassConstants (tok, vars, tok2) ->
        vars +> Ast.uncomma +> List.iter (fun (name, _opt) ->
          let info = Ast.info_of_ident name in
          tag info (MacroVar (Def2 NoUse));
        );
        k x;

      | Ast.ClassVariables (modifiers, _opt_ty, vars, tok) ->
        vars +> Ast.uncomma +> List.iter (fun (dname, _opt) ->
          let info = Ast.info_of_dname dname in
          tag info (Field (Def2 fake_no_def2));
        );
        k x

      | Ast.UseTrait (tok, names, rules_or_tok) ->
        ()
    );

    (* -------------------------------------------------------------------- *)
    V.kstmt = (fun (k,bigf) stmt ->
      k stmt;
      match stmt with
      | Globals ((v1, v2, v3)) ->
        v2 +> Ast.uncomma +> List.iter (fun x ->
          match x  with
          | GlobalVar dname ->
            let info = Ast.info_of_dname dname in
            tag info (Global (Def2 NoUse))

            (* TODO ?? *)
          | GlobalDollar _ -> ()
          | GlobalDollarExpr _ ->  ()
        );
      | StaticVars ((v1, v2, v3)) ->
        v2 +> Ast.uncomma +> List.iter (fun svar ->
          let (dname, affect_opt) = svar in
          let info = Ast.info_of_dname dname in
          tag info (Local Def);
        );
        ()
      | _ -> ()

    );
    (* -------------------------------------------------------------------- *)
    V.kcatch = (fun (k,bigf) c ->
      let (tok, (lp, (cname, dname), rp), stmts) = c in
      let name = name_of_class_name cname in
      let info_class = Ast.info_of_name name in
      tag info_class (Class (Use2 fake_no_use2));

      let info_dname = Ast.info_of_dname dname in
      tag info_dname (Local Use);
      k c
    );

    (* -------------------------------------------------------------------- *)
    V.kexpr = (fun (k,vx) expr ->
      (* do not call k expr; here, let each case call it. Also
       * remember that tag() will not retag something already tagged,
       * so it simplifies a bit the logic where you can visit
       * the children without being scared it will retag things.
       *)
      (match expr with

      | This tok ->
        tag tok (Class (Use2 fake_no_use2))

      | ArrayGet (var, exprbracket) ->
        (match Ast.unbracket exprbracket with
        | None ->
          k expr
        | Some (exprbis) ->
          (match exprbis with
          | Sc (C (Ast.String (s, info))) ->
            tag info (Field (Use2 fake_no_use2));
            vx (Expr var);

          | Sc (C (Int (s, info))) ->
            k expr
          | _ -> k expr
          )
        )

      (* Call *)
      | Call (a, args) ->
        (match a with
        | Id callname ->
          let info = Ast.info_of_name callname in
          let f = Ast.str_of_name callname in
          let args = args +> Ast.unparen +> Ast.uncomma in
          highlight_funcall_simple ~tag ~hentities f args info;
        | ClassGet (lval, _, Id name) ->
          let info = Ast.info_of_name name in
          tag info (StaticMethod (Use2 fake_no_use2));
        | ClassGet (lval, _, _var) ->
          let ii = Lib_parsing_php.ii_of_any (Expr lval) in
          ii +> List.iter (fun info -> tag info PointerCall);
        | ObjGet(lval, tok, Id name) ->
          let info = Ast.info_of_name name in
          tag info (Method (Use2 fake_no_use2));
        | e ->
          (* function pointer call !!! put in big font *)
          let ii = Lib_parsing_php.ii_of_any (Expr e) in
          ii +> List.iter (fun info -> tag info PointerCall);
        );
        k expr

      (* ObjGet *)
      | ObjGet (lval, tok, Id name) ->
        let info = Ast.info_of_name name in
        tag info (Field (Use2 fake_no_use2));
        k expr

      (* ClassGet *)
      | ClassGet (qualif, tok, b) ->
        (* todo: qualif! *)
      (* TODO
         | ClassNameRefStatic (ClassName (name,_)) -> 
         let info = Ast.info_of_name name in
         tag info (Class (Use2 fake_no_use2));
         | (IdStatic tok) ->
         tag tok BadSmell
      *)
        
        (match b with
        | Id name ->
          let info = Ast.info_of_name name in
          tag info (MacroVar (Use2 fake_no_use2))
        | IdVar (dname, _) ->
          let info = Ast.info_of_dname dname in
          (* todo? special category for class variables ? *)
          tag info (Global (Use2 fake_no_use2));

        | v2 ->
          (* todo? colorize qualif? bad to use dynamic variable ...
             let info = Ast.info_of_dname dname in
             tag info BadSmell
          *)
          tag tok BadSmell;
        );
        k expr

      | Id name ->
        (* cf also typing_php.ml *)
        let s = Ast.str_of_name name in
        let info = Ast.info_of_name name in
        (match s with
        | "true" ->
          tag info Boolean
        | "false" ->
          tag info Boolean
        | "null" ->
          tag info Null
        | _ ->
          if not (Hashtbl.mem already_tagged info)
          then tag info (MacroVar (Use2 fake_no_use2))
        )

      | IdVar (dname, aref) ->
        (* see check_variables_php.ml *)
        let info = Ast.info_of_dname dname in
        (match !aref with
        | S.Local ->
          tag info (Local Use)
        | S.Param ->
          tag info (Parameter Use)

        | S.Class ->
          tag info (Field (Use2 fake_no_use2))

        | S.Global | S.Closed ->
              (* TODO, need global_used table *)
          tag info (Global (Use2 fake_no_use2));

        | S.Static ->
              (* less: could invent a Static in highlight_code ? *)
          tag info (Global (Use2 fake_no_use2))

        | S.ListBinded
        | S.LocalIterator
        | S.LocalExn ->
          tag info (Local Use)

        | S.NoScope ->
          tag info (NoType)
        )

      | Cast (((cast, v1), v2)) ->
        tag v1 TypeMisc;
        k expr;
        
      | _ ->
        k expr
      )
    );
    (* -------------------------------------------------------------------- *)
    V.kxhp_attribute = (fun (k, _) x ->
      let ((attr_name, ii_attr_name), tok_eq, attr_val) = x in

      (match attr_name with
      | "href" | "src" ->
        (match attr_val with
        | XhpAttrString (tok1, xs, tok2) ->
          tag tok1 String;
          tag tok2 String;
          xs +> List.iter (function
          | EncapsString (s, ii) ->
            tag ii EmbededUrl
          | EncapsExpr (_, _, _)
          | EncapsDollarCurly (_, _, _)
          | EncapsCurly (_, _, _)
          | EncapsVar _ ->
            ()
          );
        | XhpAttrExpr e -> ()
        | SgrepXhpAttrValueMvar _ -> ()
        )
      | _ -> ()
      );
      k x
    );

    V.kxhp_attr_decl = (fun (k, _) x ->
      match x with
      | XhpAttrInherit (xhp_tag, ii) ->
        tag ii (Class (Use2 (fake_no_use2)));

      | XhpAttrDecl ((attr_type, (attr_name, iiname), affect_opt, tok_opt)) ->
        tag iiname (Field (Use2 fake_no_use2));
        k x
    );

    (* -------------------------------------------------------------------- *)
    V.kconstant = (fun (k, vx) e ->
      match e with
      | Int v1 | Double v1 ->
        tag (snd v1) Number

      | Ast.String (s, ii) ->
          (* this can be sometimes tagged as url, or field access in array *)
        if not (Hashtbl.mem already_tagged ii)
        then
          tag_string ~tag s ii

      | PreProcess v1 ->
        tag (snd v1) Builtin
      | XdebugClass (_, _) | XdebugResource ->
        ()
    );

    V.kencaps = (fun (k, vx) e ->
      match e with
      | EncapsString (s, ii) ->
        if not (Hashtbl.mem already_tagged ii)
        then tag_string ~tag s ii
      | _ -> k e
    );
    (* -------------------------------------------------------------------- *)
    V.khint_type = (fun (k, vx) x ->
      (match x with
      (* TODO: emit info for type args *)
      | Hint (XName [QI (name)], _targsTODO) -> 
        let info = Ast.info_of_ident name in
        tag info (TypeMisc);
      | Hint (XName qu, _) -> 
        (* raise (TodoNamespace (Ast.info_of_qualified_ident qu)) *)
        let info = Ast.info_of_name (XName qu) in
        tag info (Class (Use2 fake_no_use2));
      | Hint ((Self _ | Parent _), _) ->
        ()
      | Hint (LateStatic tok, _) ->
        tag tok BadSmell

      | HintArray tok ->
        tag tok (TypeMisc);
      | HintQuestion (tok,t) ->
        tag tok (TypeMisc);
      | HintTuple (vl, elts, vr) ->
        tag vl (TypeMisc);
        tag vr (TypeMisc);
      | HintCallback (lp, (tok, (lap, args, rap), ret), rp) ->
        tag lp (TypeMisc);
        tag tok (TypeMisc);
        tag lap (TypeMisc);
        tag rap (TypeMisc);
        tag rp (TypeMisc)
      | HintShape (tok, xs) ->
        (* todo: colorize as record the keys? *)
        ()
      );
      k x
    );
  }
  in
  let visitor = V.mk_visitor hooks in
  visitor (Program ast);

  (* -------------------------------------------------------------------- *)
  (* toks phase 2 *)
  (* -------------------------------------------------------------------- *)
  toks +> List.iter (fun tok ->
    (* all the name and varname should have been tagged by now. *)
    match tok with
    | T.EOF ii | T.TNewline ii | T.TSpaces ii -> ()
    | T.TCommentPP ii -> ()

    | T.TUnknown ii -> tag ii Error

    (* they should have been covered before *)
    | T.T_VARIABLE (_, ii) ->
      if not (Hashtbl.mem already_tagged ii)
      then tag ii Error
    | T.T_IDENT (_, ii) ->
      if not (Hashtbl.mem already_tagged ii)
      then tag ii Error

    | T.T_OPEN_TAG ii ->
      tag ii Keyword

    | T.TOPAR ii   | T.TCPAR ii
    | T.TOBRACE ii | T.TCBRACE ii
    | T.TOBRA ii   | T.TCBRA ii
      ->tag ii Punctuation


    (* less: could highlight certain words in the comment? *)
    | T.T_COMMENT (ii)  | T.T_DOC_COMMENT (ii)  -> tag ii Comment

    | T.T_XHP_PCDATA ii | T.T_XHP_ANY ii
    | T.T_XHP_REQUIRED ii | T.T_XHP_ENUM ii
    | T.T_XHP_CATEGORY ii | T.T_XHP_CHILDREN ii
    | T.T_XHP_ATTRIBUTE ii
      -> tag ii KeywordObject

    | T.T_XHP_TEXT (_, ii) -> tag ii String
    | T.T_XHP_ATTR (_, ii) -> tag ii (Field (Use2 fake_no_use2))

    | T.T_XHP_CLOSE_TAG (_, ii) -> tag ii EmbededHtml
    | T.T_XHP_SLASH_GT ii -> tag ii EmbededHtml
    | T.T_XHP_GT ii -> tag ii EmbededHtml
    | T.T_XHP_OPEN_TAG (_, ii) -> tag ii EmbededHtml

      (* should have been transformed into a XhpName or XhpInherit in Ast *)

    | T.T_XHP_PERCENTID_DEF (_, ii) ->
      if not (Hashtbl.mem already_tagged ii)
      then tag ii Error

    | T.T_XHP_COLONID_DEF (_, ii) ->
      if not (Hashtbl.mem already_tagged ii)
      then tag ii Error

    | T.T_RESOURCE_XDEBUG ii -> ()
    | T.T_CLASS_XDEBUG ii -> ()

    | T.TDOTS ii -> tag ii Punctuation
    | T.TANTISLASH ii -> tag ii KeywordModule
    | T.T_NAMESPACE ii -> tag ii Keyword

    | T.TGUIL ii -> tag ii String

    | T.TDOLLAR ii -> tag ii Punctuation
    | T.TSEMICOLON ii -> tag ii Punctuation
    | T.TBACKQUOTE ii -> tag ii Punctuation

      (* we want to highlight code using eval! *)
    | T.T_EVAL ii -> tag ii BadSmell

    | T.T_REQUIRE_ONCE ii | T.T_REQUIRE ii
    | T.T_INCLUDE_ONCE ii | T.T_INCLUDE ii
      -> tag ii Include

    | T.T_INSTANCEOF ii -> tag ii KeywordObject
    | T.T_CLONE ii -> tag ii KeywordObject
    | T.T_NEW ii -> tag ii KeywordObject

    | T.T__AT ii -> tag ii Builtin

    | T.T_IS_NOT_EQUAL ii   | T.T_IS_EQUAL ii
    | T.T_IS_NOT_IDENTICAL ii  | T.T_IS_IDENTICAL ii
      -> tag ii Operator

      (* done in Cast *)
    | T.T_UNSET_CAST ii   | T.T_OBJECT_CAST ii
    | T.T_ARRAY_CAST ii   | T.T_STRING_CAST ii
    | T.T_DOUBLE_CAST ii   | T.T_INT_CAST ii
    | T.T_BOOL_CAST ii
      -> ()

    | T.T_IS_GREATER_OR_EQUAL ii  | T.T_IS_SMALLER_OR_EQUAL ii
    | T.T_SR ii   | T.T_SL ii
    | T.T_LOGICAL_XOR ii  | T.T_LOGICAL_AND ii
    | T.T_LOGICAL_OR ii   | T.T_BOOLEAN_AND ii
    | T.T_BOOLEAN_OR ii
    | T.T_DEC ii  | T.T_INC ii
    | T.T_SR_EQUAL ii   | T.T_SL_EQUAL ii
    | T.T_XOR_EQUAL ii  | T.T_OR_EQUAL ii  | T.T_AND_EQUAL ii
    | T.T_MOD_EQUAL ii
    | T.T_CONCAT_EQUAL ii
    | T.T_DIV_EQUAL ii  | T.T_MUL_EQUAL ii
    | T.T_MINUS_EQUAL ii  | T.T_PLUS_EQUAL ii
    | T.TGREATER ii   | T.TSMALLER ii
    | T.TEQ ii | T.TXOR ii | T.TOR ii | T.TAND ii
    | T.TMOD ii | T.TDIV ii | T.TMUL ii | T.TMINUS ii | T.TPLUS ii
      -> tag ii Operator

    | T.TQUESTION ii  | T.TTILDE ii  | T.TBANG ii  | T.TDOT ii
    | T.TCOMMA ii  | T.TCOLON ii
    | T.TCOLCOL ii
      -> tag ii Punctuation

    | T.T_CURLY_OPEN ii -> tag ii Punctuation
    | T.T_DOLLAR_OPEN_CURLY_BRACES ii -> tag ii Punctuation

    | T.T_END_HEREDOC ii -> tag ii Punctuation
    | T.T_START_HEREDOC ii -> tag ii Punctuation

    | T.T_CLOSE_TAG_OF_ECHO ii -> tag ii Punctuation
    | T.T_OPEN_TAG_WITH_ECHO ii -> tag ii Punctuation

    | T.T_CLOSE_TAG ii -> tag ii Punctuation

      (* done in PreProcess *)
    | T.T_FILE ii  | T.T_LINE ii | T.T_DIR ii
    | T.T_FUNC_C ii | T.T_METHOD_C ii | T.T_CLASS_C ii | T.T_TRAIT_C ii
    | T.T_NAMESPACE_C ii
      -> ()

      (* can be a type hint *)
    | T.T_ARRAY ii ->
      if not (Hashtbl.mem already_tagged ii)
      then
        tag ii Builtin
    | T.T_LIST ii -> tag ii Builtin

    | T.T_DOUBLE_ARROW ii ->
      tag ii Punctuation
    | T.T_OBJECT_OPERATOR ii ->
      tag ii Punctuation

    | T.T_IMPLEMENTS ii -> tag ii KeywordObject
    | T.T_EXTENDS ii -> tag ii KeywordObject
    | T.T_INTERFACE ii -> tag ii KeywordObject

    | T.T_CLASS ii -> tag ii KeywordObject
    | T.T_TRAIT ii -> tag ii KeywordObject
    | T.T_INSTEADOF ii -> tag ii KeywordObject

    | T.T_TYPE ii | T.T_NEWTYPE ii | T.T_SHAPE ii -> tag ii Keyword

    | T.T_EMPTY ii -> tag ii Builtin
    | T.T_ISSET ii -> tag ii Builtin
    | T.T_UNSET ii -> tag ii Builtin

    | T.T_VAR ii -> tag ii Keyword
    | T.T_PUBLIC ii | T.T_PROTECTED ii | T.T_PRIVATE ii
      -> tag ii Keyword

    | T.T_FINAL ii | T.T_ABSTRACT ii -> tag ii KeywordObject

    | T.T_STATIC ii -> tag ii Keyword
    | T.T_ASYNC ii -> tag ii Keyword
    | T.T_CONST ii -> tag ii Keyword

      (* could be for func or method or lambda so tagged via ast *)
    | T.T_FUNCTION ii ->
      if not (Hashtbl.mem already_tagged ii)
      then tag ii Keyword

    | T.T_AS ii -> tag ii Keyword
    | T.T_GLOBAL ii -> tag ii Keyword
    | T.T_USE ii -> tag ii Keyword
    | T.T_ENDDECLARE ii -> tag ii Keyword
    | T.T_DECLARE ii -> tag ii Keyword
    | T.T_EXIT ii -> tag ii Keyword

    | T.T_THROW ii | T.T_CATCH ii | T.T_TRY ii -> tag ii KeywordExn

    | T.T_RETURN ii | T.T_CONTINUE ii | T.T_BREAK ii -> tag ii Keyword

    | T.T_DEFAULT ii | T.T_CASE ii -> tag ii Keyword

    | T.T_ENDSWITCH ii | T.T_SWITCH ii -> tag ii KeywordConditional

    | T.T_ENDFOREACH ii | T.T_FOREACH ii
    | T.T_ENDFOR ii | T.T_FOR ii
    | T.T_ENDWHILE ii | T.T_WHILE ii
    | T.T_DO ii
      -> tag ii KeywordLoop

    | T.T_IF ii | T.T_ELSEIF ii  | T.T_ELSE ii | T.T_ENDIF ii
      -> tag ii KeywordConditional

    | T.T_PRINT ii -> tag ii Builtin
    | T.T_ECHO ii -> tag ii Builtin

    | T.T_SELF ii | T.T_PARENT ii ->
      tag ii (Class (Use2 fake_no_use2));

    | T.T_YIELD ii -> tag ii Keyword
    | T.T_AWAIT ii -> tag ii Keyword

      (* should have been handled in field *)
    | T.T_STRING_VARNAME ii -> ()

    | T.T_INLINE_HTML (_, ii) -> tag ii EmbededHtml

    | T.T_NUM_STRING ii -> ()

    | T.T_ENCAPSED_AND_WHITESPACE (s, ii) ->
      if not (Hashtbl.mem already_tagged ii)
      then tag_string ~tag s ii

    | T.T_CONSTANT_ENCAPSED_STRING (s, ii) ->
      if not (Hashtbl.mem already_tagged ii)
      then tag_string ~tag s ii

      (* should been handled in Constant *)
    | T.T_DNUMBER ii -> ()
    | T.T_LNUMBER ii -> ()
  );

  (* -------------------------------------------------------------------- *)
  (* ast phase 2 *)
  (* -------------------------------------------------------------------- *)
  (match ast with
  | NotParsedCorrectly iis::_ ->
    iis +> List.iter (fun ii -> tag ii NotParsed)
  | _ -> ()
  );
  ()
