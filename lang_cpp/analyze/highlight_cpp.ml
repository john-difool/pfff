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
open Common2
open Common

open Ast_cpp

module Ast = Ast_cpp
module V = Visitor_cpp
module Lib = Lib_parsing_cpp

open Highlight_code

module T = Parser_cpp
module TH = Token_helpers_cpp

module S = Scope_code

module Type = Type_cpp

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*
 * TODO:
 *  - take into account class qualifier as a use
 *  - take inheritance as a class use
 *)

(*****************************************************************************)
(* Helpers when have global analysis information *)
(*****************************************************************************)

let h_debug_functions = Common.hashset_of_list [
  "DEBUG"
]

let fake_no_def2 = NoUse
let fake_no_use2 = (NoInfoPlace, UniqueDef, MultiUse)

(*****************************************************************************)
(* Code highlighter *)
(*****************************************************************************)

let visit_toplevel ~tag_hook prefs (*db_opt *) (toplevel, toks) =
  let already_tagged = Hashtbl.create 101 in
  let tag = (fun ii categ ->
    tag_hook ii categ;
    Hashtbl.add already_tagged ii true
  )
  in

  (* -------------------------------------------------------------------- *)
  (* Toks phase 1 *)
  (* -------------------------------------------------------------------- *)

  let rec aux_toks xs = 
    match xs with
    | [] -> ()

    (* a little bit pad specific *)
    |   T.TComment(ii)
      ::T.TCommentNewline (ii2)
      ::T.TComment(ii3)
      ::T.TCommentNewline (ii4)
      ::T.TComment(ii5)
      ::xs ->
        let s = Ast.str_of_info ii in
        let s5 =  Ast.str_of_info ii5 in
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

    (* a little bit hphp specific *)
    | T.TComment ii::T.TCommentSpace ii2::T.TComment ii3::xs 
      ->
        let s = Ast.str_of_info ii in
        let s2 = Ast.str_of_info ii3 in
        (match () with
        | _ when s =~ "//////////.*" 
            && s2 =~ "// .*" 
            ->
            tag ii3 CommentSection1
        | _ -> 
            ()
        );
        aux_toks xs

    (* heuristic for class/struct definitions. 
     * 
     * Must be before the heuristic for function definitions
     * otherwise this pattern will never be exercised
     * 
     * the code below has been commented because it generates
     * too much false positives. For instance in 'struct foo * bar(...) '
     * foo would be classified as the start of a struct definition
     *
     * don't want forward class declarations to generate noise
     * | (T.Tclass(ii) | T.Tstruct(ii) | T.Tenum(ii))
     * ::T.TCommentSpace ii2::T.TIdent(s, ii3)::T.TPtVirg _::xs ->
     * aux_toks xs
     * | (T.Tclass(ii) | T.Tstruct(ii) | T.Tenum (ii) 
     * | T.TIdent ("service", ii)
     * )
     * ::T.TCommentSpace ii2::T.TIdent(s, ii3)::xs
     * when Ast.col_of_info ii = 0 ->
     * 
     * tag ii3 (Class (Def2 fake_no_def2));
     * aux_toks xs;
     *)

    | (T.Tclass(ii) | T.Tstruct(ii) | T.Tenum (ii)
        (* thrift stuff *)
        | T.TIdent ("service", ii)
      )
      ::T.TCommentSpace ii2
      ::T.TIdent(s, ii3)
      ::T.TCommentSpace ii4
      ::T.TOBrace ii5
      ::xs
        when Ast.col_of_info ii = 0 ->

        tag ii3 (Class (Def2 fake_no_def2));
        aux_toks xs;


    (* heuristic for function definitions *)
    | t1::xs when TH.col_of_tok t1 = 0 && TH.is_not_comment t1 ->
        let line_t1 = TH.line_of_tok t1 in
        let rec find_ident_paren xs =
          match xs with
          | T.TIdent(s, ii1)::T.TOPar ii2::_ ->
              tag ii1 (Function (Def2 NoUse));
          | T.TIdent(s, ii1)::T.TCommentSpace _::T.TOPar ii2::_ ->
              tag ii1 (Function (Def2 NoUse));
          | x::xs ->
              find_ident_paren xs
          | [] -> ()
        in
        let same_line = (t1::xs) +> Common2.take_while (fun t ->
          TH.line_of_tok t = line_t1) 
        in
        find_ident_paren same_line;
        aux_toks xs

    | x::xs ->
        aux_toks xs
  in
  aux_toks toks;

  let is_at_toplevel = ref true in

  (* -------------------------------------------------------------------- *)
  (* Ast phase 1 *) 
  (* -------------------------------------------------------------------- *)

  let visitor = V.mk_visitor { (*V.default_visitor with *)

    V.kinfo =  (fun (k, vx) x -> () );

    V.kcompound =  (fun (k, vx) x ->
      Common.save_excursion is_at_toplevel false (fun () ->
        k x
      )
    );

    V.kblock_decl = (fun (k, _) x ->
      match x with
      | DeclList (xs_comma, ii) ->
          let xs = Ast.uncomma xs_comma in
          xs +> List.iter (fun onedecl ->

            onedecl.v_namei +> Common.do_option (fun (name, ini_opt) ->

              let categ = 
                if Type.is_function_type onedecl.v_type
                then FunctionDecl NoUse
                else
                 (* could be a global too when the decl is at the top *)
                  if !is_at_toplevel  || 
                     fst (unwrap onedecl.v_storage) = (Sto Extern)
                  then (Global (Def2 fake_no_def2))
                  else (Local Def)
              in
              Ast.ii_of_id_name name +>List.iter (fun ii -> tag ii categ)
            );
          );
          k x
      | MacroDecl _ ->
           k x

      |   (Asm (_, _, _, _) 
        | NameSpaceAlias (_, _, _, _, _) | UsingDirective (_, _, _, _)
        | UsingDecl _) -> ()
    );

    V.kstmt = (fun (k, _) x ->
      match x with
      | Labeled (Ast.Label (_s, st)), ii ->
          ii +> List.iter (fun ii -> tag ii KeywordExn);
          k x

      | Jump (Goto s), ii ->
          let (iigoto, lblii, iiptvirg) = Common2.tuple_of_list3 ii in
          tag lblii KeywordExn;
          k x
      | _ -> k x
    );

    V.kexpr = (fun (k, _) x ->
      let ebis, ii = x in
      match ebis with

      | Ident (name, idinfo) ->
          (match name with
          | (_, _, IdIdent (s, ii)) ->
            if s ==~ Parsing_hacks_lib.regexp_macro &&
             (* the FunCall case might have already tagged it with something *)
              not (Hashtbl.mem already_tagged ii)
            then 
              tag ii (MacroVar (Use2 fake_no_use2))
            else 
              (match idinfo.Ast.i_scope with
              | S.Local -> 
                  tag ii (Local Use)
              | S.Param ->
                  tag ii (Parameter Use)
              | S.Global ->
                  tag ii (Global (Use2 fake_no_use2));
              | S.NoScope ->
                  ()
              | S.Static ->
                  (* todo? could invent a Static in highlight_code ? *)
                  tag ii (Global (Use2 fake_no_use2));
                
              | S.Class ->
                  (* TODO *)
                  ()
              (* todo? valid only for PHP? *)
              | (S.ListBinded|S.LocalIterator|S.LocalExn|S.Closed)
                -> failwith "scope not handled"
              )
          | _ -> ()
          )
          
      | FunCallSimple (name, args) ->
          (match name with
          | _, _, IdIdent (s, ii) ->
              (if Hashtbl.mem h_debug_functions s
              then
                tag ii BuiltinCommentColor
                else
                  tag ii (Function (Use2 fake_no_use2))
              );
          | _ -> ()
          );
          k x

      | FunCallExpr (e, args) ->
          (match e with
          | RecordAccess (e, name), _
          | RecordPtAccess (e, name), _
            ->
              Ast.ii_of_id_name name +> List.iter (fun ii ->
                tag ii (Method (Use2 fake_no_use2))
              )

          | _ -> 
              (* dynamic stuff, should highlight! *)
              let ii = Lib.ii_of_any (Expr e) in
              ii +> List.iter (fun ii -> tag ii PointerCall);
          );
          k x

      | RecordAccess (e, name)
      | RecordPtAccess (e, name) 
          ->
          (match name with
          | _, _, IdIdent (s, ii) ->
              if not (Hashtbl.mem already_tagged ii)
              then tag ii (Field (Use2 fake_no_use2));
          | _ -> ()
          );
          k x

      | New (_colon, _tok, _placement, ft, _args) ->
          (match ft with
          | _nq, ((TypeName (name, opt)), _) ->
              Ast.ii_of_id_name name +> List.iter (fun ii -> 
                tag ii (Class (Use2 fake_no_use2));
              )
          | _ ->
              ()
          );
          k x
      | _ -> k x
    );

    V.kparameter = (fun (k, vx) x ->
      (match x.p_name with
      | Some (s, ii) ->
          tag ii (Parameter Def)
      | None -> ()
      );
      k x
    );

    V.ktypeC = (fun (k, vx) x ->
      let (typeCbis, _)  = x in
      match typeCbis with
      | TypeName (name, opt) ->
          Ast.ii_of_id_name name +> List.iter (fun ii -> 
            (* new Xxx and other places have priority *)
            if not (Hashtbl.mem already_tagged ii)
            then tag ii (TypeDef Use)
          );
          k x

      | Ast_cpp.EnumName (_tok, (s, ii)) ->
          tag ii (TypeDef Use)

      | StructUnionName (su, (s, ii)) ->
          tag ii (StructName Use);
          k x

      | TypenameKwd (tok, name) ->
          Ast.ii_of_id_name name +> List.iter (fun ii -> tag ii (TypeDef Use));
          k x

      | _ -> k x
    );

    V.kfieldkind = (fun (k, vx) x -> 
      match x with
      | FieldDecl onedecl ->
          onedecl.v_namei +> Common.do_option (fun (name, ini_opt) ->
            let kind = 
              (* poor's man object using function pointer; classic C idiom *)
              if Type.is_method_type onedecl.v_type
              then Method (Def2 fake_no_def2)
              else Field (Def2 NoUse)
            in
            Ast.ii_of_id_name name +> List.iter (fun ii -> tag ii kind)
          );
          k x

      | BitField (sopt, _tok, ft, e) ->
          (match sopt with
          | Some (s, iiname) ->
              tag iiname (Field (Def2 NoUse))
          | None -> ()
          )
    );

    V.kclass_def = (fun (k,_) def ->
      let name = def.c_name in
      name +> Common.do_option (fun name ->
        Ast.ii_of_id_name name +> List.iter (fun ii -> 
          tag ii (Class (Def2 fake_no_def2));
        )
      );
      k def
    );
    V.kfunc_def = (fun (k,_) def ->
      let name = def.f_name in
      Ast.ii_of_id_name name +> List.iter (fun ii -> 
        if not (Hashtbl.mem already_tagged ii)
        then tag ii (Class (Def2 fake_no_def2));
      );
      k def
    );
    V.kclass_member = (fun (k,_) def ->
      (match def with
      | MemberFunc x ->
          let def =
            match x with
            | FunctionOrMethod def
            | Constructor (def)
            | Destructor def
              -> def
          in
          let name = def.f_name in
          Ast.ii_of_id_name name +> List.iter (fun ii -> 
            tag ii (Method (Def2 fake_no_def2))
          );
      | 
(EmptyField _|UsingDeclInClass _|TemplateDeclInClass _|
QualifiedIdInClass (_, _)|
MemberField _|MemberDecl _ | Access (_, _))
          -> ()
      );
      k def
    );
    V.kcpp = (fun (k,_) def ->
      k def
    );
    V.ktoplevel = (fun (k,_) def ->
      (match def with
      | NotParsedCorrectly ii ->
          ii +> List.iter (fun ii -> tag ii NotParsed)
      | _ ->()
      );
      k def
    );
  }
  in
  visitor (Toplevel toplevel);

  (* -------------------------------------------------------------------- *)
  (* toks phase 2 *)
  (* -------------------------------------------------------------------- *)
  toks +> List.iter (fun tok -> 
    match tok with

    | T.TComment ii ->
        if not (Hashtbl.mem already_tagged ii)
        then tag ii Comment

    | T.TInt (_,ii) | T.TFloat (_,ii) ->
        tag ii Number
    | T.TString (s,ii) ->
        tag ii String
    | T.TChar (s,ii) ->
        tag ii String
    | T.Tfalse ii | T.Ttrue ii  ->
        tag ii Boolean

    | T.TPtVirg ii
    | T.TOPar ii | T.TOPar_CplusplusInit ii | T.TOPar_Define ii | T.TCPar ii
    | T.TOBrace ii | T.TOBrace_DefineInit ii | T.TCBrace ii 
    | T.TOCro ii | T.TCCro ii
    | T.TDot ii | T.TComma ii | T.TPtrOp ii  
    | T.TAssign (_, ii)
    | T.TEq ii 
    | T.TWhy ii | T.TTilde ii | T.TBang ii 
    | T.TEllipsis ii 
    | T.TCol ii ->
        tag ii Punctuation

    | T.TInc ii | T.TDec ii 
    | T.TOrLog ii | T.TAndLog ii | T.TOr ii 
    | T.TXor ii | T.TAnd ii | T.TEqEq ii | T.TNotEq ii
    | T.TInf ii | T.TSup ii | T.TInfEq ii | T.TSupEq ii
    | T.TShl ii | T.TShr ii  
    | T.TPlus ii | T.TMinus ii | T.TMul ii | T.TDiv ii | T.TMod ii  
        ->
        tag ii Operator

    | T.Tshort ii | T.Tint ii ->
        tag ii TypeInt
    | T.Tdouble ii | T.Tfloat ii 
    | T.Tlong ii |  T.Tunsigned ii | T.Tsigned ii 
    | T.Tchar ii 
        -> tag ii TypeInt (* TODO *)
    | T.Tvoid ii 
        -> tag ii TypeVoid
    | T.Tbool ii 
    | T.Twchar_t ii
      -> tag ii TypeInt
    (* thrift stuff *)

    (* needed only when have FP in the typedef inference *)
    | T.TIdent (
        ("string" | "i32" | "i64" | "i8" | "i16" | "byte"
          | "list" | "map" | "set" 
          | "binary"
        ), ii) ->
        tag ii TypeInt


    | T.Tauto ii | T.Tregister ii | T.Textern ii | T.Tstatic ii  
    | T.Tconst ii | T.Tconst_MacroDeclConst ii | T.Tvolatile ii 
    | T.Tbreak ii | T.Tcontinue ii
    | T.Treturn ii
    | T.Tdefault ii 
    | T.Tsizeof ii 
    | T.Trestrict ii 
      -> 
        tag ii Keyword

    | T.Tgoto ii ->
        (* people often use goto as an try/throw exception mechanism
         * so let's use the same color
         *)
        tag ii Keyword

    | T.Tasm ii | T.Tattribute ii 
    | T.Tinline ii | T.Ttypeof ii 
     -> 
        tag ii Keyword

    (* pp *)
    | T.TDefine ii -> 
        tag ii Define
    | T.TUndef (_, ii) ->
        tag ii Define

    (* todo: could be also a MacroFunc *)
    | T.TIdent_Define (_, ii) ->
        tag ii (MacroVar (Def2 NoUse))

    (* TODO: have 2 tokens? 
    | T.TInclude_Filename (_, ii) ->
        tag ii String
    | T.TInclude_Start (ii, _aref) ->
        tag ii Include
     *)

    | T.TInclude (_, _, ii) -> 
        tag ii Include

    | T.TIfdef ii | T.TIfdefelse ii | T.TIfdefelif ii | T.TEndif ii ->
        tag ii Ifdef
    | T.TIfdefBool (_, ii) | T.TIfdefMisc (_, ii) | T.TIfdefVersion (_, ii) ->
        tag ii Ifdef

    | T.TCppDirectiveOther _ -> 
        ()
    | T.Tnamespace ii -> tag ii KeywordModule

    | T.Tthis ii -> tag ii (Class (Use2 fake_no_use2))

    | T.Tnew ii | T.Tdelete ii ->
        tag ii KeywordObject
    | T.Tvirtual ii  ->
        tag ii KeywordObject

    | T.Ttemplate ii | T.Ttypeid ii | T.Ttypename ii  
    | T.Toperator ii  
    | T.Tpublic ii | T.Tprivate ii | T.Tprotected ii | T.Tfriend ii  
    | T.Tusing ii  
    | T.Tconst_cast ii | T.Tdynamic_cast ii
    | T.Tstatic_cast ii | T.Treinterpret_cast ii
    | T.Texplicit ii | T.Tmutable ii  
    | T.Texport ii 
      ->
        tag ii Keyword

    | T.TPtrOpStar ii | T.TDotStar ii  ->
        tag ii Punctuation

    | T.TColCol ii  | T.TColCol_BeforeTypedef ii ->
        tag ii Punctuation

    | T.Ttypedef ii | T.Tunion ii | T.Tenum ii ->
        tag ii TypeMisc (* TODO *)

    | T.Tif ii | T.Telse ii ->
        tag ii KeywordConditional

    | T.Tswitch ii | T.Tcase ii ->
        tag ii KeywordConditional

    | T.Ttry ii | T.Tcatch ii | T.Tthrow ii ->
        tag ii KeywordExn

    (* thrift *)
    | T.TIdent (("throws" | "exception"), ii) ->
        tag ii KeywordExn


    | T.Tfor ii | T.Tdo ii | T.Twhile ii ->
        tag ii KeywordLoop

    | T.Tclass ii | T.Tstruct ii ->
        tag ii KeywordObject

    | T.TAt_interface ii
    | T.TAt_implementation ii
    | T.TAt_protocol ii
    | T.TAt_class ii
    | T.TAt_selector ii
    | T.TAt_encode ii
    | T.TAt_defs ii
    | T.TAt_end ii
    | T.TAt_public ii
    | T.TAt_private ii
    | T.TAt_protected ii
        -> tag ii KeywordObject

    | T.TAt_throw ii
    | T.TAt_catch ii
    | T.TAt_try ii
    | T.TAt_finally ii
      -> tag ii KeywordExn
    | T.TAt_synchronized ii -> tag ii Keyword

    | T.TAt_property ii -> tag ii Keyword

    | T.TAt_synthesize ii
    | T.TAt_autoreleasepool ii
    | T.TAt_dynamic ii
    | T.TAt_YES ii
    | T.TAt_NO ii
    | T.TAt_optional ii
    | T.TAt_required ii
    | T.TAt_compatibility_alias ii

    | T.TAt_Misc ii
      -> tag ii Keyword
    | T.TAt ii
      -> tag ii Keyword


    (* thrift *)
    | T.TIdent (("service" | "include" | "extends"), ii) ->
        tag ii Keyword

    (* should be covered by the xxx_namei case above *)
    | T.TIdent (_, ii) -> 
        ()
    (* should be covered by TypeName above *)
    | T.TIdent_Typedef _ 

    | T.TIdent_TemplatenameInQualifier_BeforeTypedef _
    | T.TIdent_TemplatenameInQualifier _
    | T.TIdent_TypedefConstr _
    | T.TIdent_Constructor _
    | T.TIdent_Templatename _
    | T.TIdent_ClassnameInQualifier_BeforeTypedef _
    | T.TIdent_ClassnameInQualifier _

    | T.TIdent_MacroIterator _
    | T.TIdent_MacroDecl _
    | T.TIdent_MacroString _
    | T.TIdent_MacroStmt _
        -> ()


    | T.Tbool_Constr ii | T.Tlong_Constr ii | T.Tshort_Constr ii
    | T.Twchar_t_Constr ii | T.Tdouble_Constr ii | T.Tfloat_Constr ii
    | T.Tint_Constr ii | T.Tchar_Constr ii | T.Tunsigned_Constr ii
    | T.Tsigned_Constr ii
        -> tag ii TypeInt

    | T.TInt_ZeroVirtual _

    | T.TCCro_new _ | T.TOCro_new _ -> ()

    | T.TSup_Template ii | T.TInf_Template ii -> 
        tag ii TypeMisc

    | T.TAny_Action _
    | T.TCPar_EOL _
        -> ()

    (* TODO *)
    | T.TComment_Pp (kind, ii) -> 
        (match kind with
        | Token_cpp.CppMacroExpanded
        | Token_cpp.CppPassingNormal
          -> tag ii Expanded
        | _ -> tag ii Passed
        )
    | T.TComment_Cpp (kind, ii) -> 
        tag ii Passed

    | T.TDefParamVariadic _

    | T.TCommentNewline _ | T.TCommentNewline_DefineEndOfMacro _
    | T.TCppEscapedNewline _
    | T.TCommentSpace _

    | T.EOF _ 
        -> ()
    | T.TUnknown ii -> tag ii Error

  );
  ()
