open Common

(* tokens *)
open Parser_cpp

module Ast = Ast_cpp

(*****************************************************************************)
(* Is_xxx, categories *)
(*****************************************************************************)

let is_eof = function
  | EOF x -> true
  | _ -> false

(* ---------------------------------------------------------------------- *)
let is_space = function
  | TCommentSpace _  | TCommentNewline _ -> true
  | _ -> false

let is_comment_or_space = function
  | TCommentSpace _  | TCommentNewline _ 
  | TComment _
      -> true
  | _ -> false

let is_just_comment = function
  | TComment _ -> true
  | _ -> false

let is_comment = function
  | TCommentSpace _ | TCommentNewline _
  | TComment _    
  | TComment_Pp _ | TComment_Cpp _
      -> true
  | _ -> false

let is_real_comment = function
  | TComment _    | TCommentSpace _ 
  | TCommentNewline _ 
    -> true
  | _ -> false

let is_fake_comment = function
  | TComment_Pp _ | TComment_Cpp _ -> true
  | _ -> false

let is_not_comment x = 
  not (is_comment x)

(* ---------------------------------------------------------------------- *)
let is_gcc_token = function
  | Tasm _ | Tinline _  | Tattribute _  | Ttypeof _ 
      -> true
  | _ -> false

let is_pp_instruction = function
  | TInclude _ 
  | TDefine _
  | TIfdef _   | TIfdefelse _ | TIfdefelif _
  | TEndif _ 
  | TIfdefBool _ | TIfdefMisc _ | TIfdefVersion _
  | TUndef _ 
  | TCppDirectiveOther _
      -> true
  | _ -> false


let is_opar = function
  | TOPar _ | TOPar_Define _ | TOPar_CplusplusInit _ -> true
  | _ -> false

let is_cpar = function
  | TCPar _ | TCPar_EOL _ -> true
  | _ -> false

let is_obrace = function
  | TOBrace _ | TOBrace_DefineInit _ -> true
  | _ -> false

let is_cbrace = function
  | TCBrace _ -> true
  | _ -> false 


let is_statement = function
  | Tfor _ | Tdo _ | Tif _ | Twhile _ | Treturn _ 
  | Tbreak _ | Telse _ | Tswitch _ | Tcase _ | Tcontinue _
  | Tgoto _ 
  | TPtVirg _
  | TIdent_MacroIterator _
      -> true
  | _ -> false

(* is_start_of_something is used in parse_c for error recovery, to find
 * a synchronisation token.
 * 
 * Would like to put TIdent or TDefine, TIfdef but they can be in the
 * middle of a function, for instance with label:.
 * 
 * Could put Typedefident but fired ? it would work in error recovery
 * on the already_passed tokens, which has been already gone in the
 * Parsing_hacks.lookahead machinery, but it will not work on the
 * "next" tokens. But because the namespace for labels is different
 * from namespace for ident/typedef, we can use the name for a typedef
 * for a label and so dangerous to put Typedefident at true here. 
 * 
 * Can look in parser_c.output to know what can be at toplevel
 * at the very beginning.
 *)

let is_start_of_something = function
  | Tchar _  | Tshort _ | Tint _ | Tdouble _ |  Tfloat _ | Tlong _ 
  | Tunsigned _ | Tsigned _ | Tvoid _ 
  | Tauto _ | Tregister _ | Textern _ | Tstatic _
  | Tconst _ | Tvolatile _
  | Ttypedef _
  | Tstruct _ | Tunion _ | Tenum _ 
  (* c++ext: *)
  | Tclass _
  | Tbool _
  | Twchar_t _ 
    -> true
  | _ -> false


let is_binary_operator = function
  | TOrLog _ | TAndLog _ |  TOr _ |  TXor _ |  TAnd _ 
  | TEqEq _ |  TNotEq _  | TInf _ |  TSup _ |  TInfEq _ |  TSupEq _ 
  | TShl _ | TShr _  
  | TPlus _ |  TMinus _ |  TMul _ |  TDiv _ |  TMod _ 
        -> true
  | _ -> false 

let is_binary_operator_except_star = function
  (* | TAnd _ *) (*|  TMul _*)
  | TOrLog _ | TAndLog _ |  TOr _ |  TXor _   
  | TEqEq _ |  TNotEq _  | TInf _ |  TSup _ |  TInfEq _ |  TSupEq _ 
  | TShl _ | TShr _  
  | TPlus _ |  TMinus _  |  TDiv _ |  TMod _ 
        -> true
  | _ -> false 

let is_stuff_taking_parenthized = function
  | Tif _ 
  | Twhile _ 
  | Tswitch _
  | Ttypeof _
  | TIdent_MacroIterator _
    -> true 
  | _ -> false

let is_static_cast_like = function
  | Tconst_cast _ | Tdynamic_cast _ | Tstatic_cast _ | Treinterpret_cast _ -> 
      true
  | _ -> false

let is_basic_type = function
  | Tchar _  | Tshort _ | Tint _ | Tdouble _ |  Tfloat _ | Tlong _ 
  | Tbool _ | Twchar_t _

  | Tunsigned _ | Tsigned _
        -> true
  (*| Tvoid _  *)
  | _ -> false


let is_struct_like_keyword = function
  | (Tstruct _ | Tunion _ | Tenum _) -> true
  (* c++ext: *)
  | (Tclass _) -> true
  | _ -> false

let is_classkey_keyword = function
  | (Tstruct _ | Tunion _ | Tclass _) -> true
  | _ -> false

let is_cpp_keyword = function
  | Tclass _ | Tthis _
 
  | Tnew _ | Tdelete _
 
  | Ttemplate _ | Ttypeid _ | Ttypename _
 
  | Tcatch _ | Ttry _ | Tthrow _
 
  | Toperator _ 
  | Tpublic _ | Tprivate _ | Tprotected _

  | Tfriend _
 
  | Tvirtual _
 
  | Tnamespace _ | Tusing _
 
  | Tbool _
  | Tfalse _ | Ttrue _
 
  | Twchar_t _ 
  | Tconst_cast _ | Tdynamic_cast _ | Tstatic_cast _ | Treinterpret_cast  _
  | Texplicit _
  | Tmutable _
 
  | Texport _
      -> true

  | _ -> false

let is_really_cpp_keyword = function
  | Tconst_cast _ | Tdynamic_cast _ | Tstatic_cast _ | Treinterpret_cast  _
        -> true
(* when have some asm volatile, can have some ::
  | TColCol  _
      -> true
*)
  | _ -> false

(* some false positive on some C file like sqlite3.c *)
let is_maybenot_cpp_keyword = function
  | Tpublic _ | Tprivate _ | Tprotected _
  | Ttemplate _ | Tnew _ | Ttypename _
  | Tnamespace _
    -> true
  | _ -> false


let is_objectivec_keyword = function
  | _ -> false

(* used in the algorithm for "10 most problematic tokens". C-s for TIdent
 * in parser_cpp.mly
 *)
let is_ident_like = function
  | TIdent _
  | TIdent_Typedef _
  | TIdent_Define  _
(*  | TDefParamVariadic _*)

  | TUnknown _

  | TIdent_MacroStmt _
  | TIdent_MacroString _
  | TIdent_MacroIterator _
  | TIdent_MacroDecl _
(*  | TIdent_MacroDeclConst _ *)
(*
  | TIdent_MacroAttr _
  | TIdent_MacroAttrStorage _
*)

  | TIdent_ClassnameInQualifier _
  | TIdent_ClassnameInQualifier_BeforeTypedef _
  | TIdent_Templatename _
  | TIdent_TemplatenameInQualifier _
  | TIdent_TemplatenameInQualifier_BeforeTypedef _
  | TIdent_Constructor _
  | TIdent_TypedefConstr _
      -> true

  | _ -> false

let is_privacy_keyword = function
  | Tpublic _ | Tprivate _ | Tprotected _
        -> true
  | _ -> false

(*****************************************************************************)
(* Visitors *)
(*****************************************************************************)

(* Because ocamlyacc force us to do it that way. The ocamlyacc token 
 * cant be a pair of a sum type, it must be directly a sum type.
 *)
let info_of_tok = function
  | TString ((string, isWchar), i) -> i
  | TChar  ((string, isWchar), i) -> i
  | TFloat ((string, floatType), i) -> i

  | TAssign  (assignOp, i) -> i

  | TIdent  (s, i) -> i
  | TIdent_Typedef  (s, i) -> i

  | TInt  (s, i) -> i

  (*cppext:*) 
  | TDefine (ii) -> ii 
  | TInclude (includes, filename, i1) ->     i1

  | TUndef (s, ii) -> ii
  | TCppDirectiveOther (ii) -> ii

  | TCommentNewline_DefineEndOfMacro (i1) ->     i1
  | TOPar_Define (i1) ->     i1
  | TIdent_Define  (s, i) -> i
  | TOBrace_DefineInit (i1) ->     i1

  | TCppEscapedNewline (ii) -> ii
  | TDefParamVariadic (s, i1) ->     i1


  | TUnknown             (i) -> i

  | TIdent_MacroStmt             (i) -> i
  | TIdent_MacroString             (i) -> i
  | TIdent_MacroIterator             (s,i) -> i
  | TIdent_MacroDecl             (s, i) -> i
  | Tconst_MacroDeclConst             (i) -> i
(*  | TMacroTop             (s,i) -> i *)
  | TCPar_EOL (i1) ->     i1

  | TAny_Action             (i) -> i

  | TComment             (i) -> i
  | TCommentSpace        (i) -> i
  | TComment_Pp          (cppkind, i) -> i
  | TComment_Cpp          (cppkind, i) -> i
  | TCommentNewline        (i) -> i

  | TIfdef               (i) -> i
  | TIfdefelse           (i) -> i
  | TIfdefelif           (i) -> i
  | TEndif               (i) -> i
  | TIfdefBool           (b, i) -> i
  | TIfdefMisc           (b, i) -> i
  | TIfdefVersion           (b, i) -> i

  | TOPar                (i) -> i
  | TOPar_CplusplusInit                (i) -> i
  | TCPar                (i) -> i
  | TOBrace              (i) -> i
  | TCBrace              (i) -> i
  | TOCro                (i) -> i
  | TCCro                (i) -> i
  | TDot                 (i) -> i
  | TComma               (i) -> i
  | TPtrOp               (i) -> i
  | TInc                 (i) -> i
  | TDec                 (i) -> i
  | TEq                  (i) -> i
  | TWhy                 (i) -> i
  | TTilde               (i) -> i
  | TBang                (i) -> i
  | TEllipsis            (i) -> i
  | TCol              (i) -> i
  | TPtVirg              (i) -> i
  | TOrLog               (i) -> i
  | TAndLog              (i) -> i
  | TOr                  (i) -> i
  | TXor                 (i) -> i
  | TAnd                 (i) -> i
  | TEqEq                (i) -> i
  | TNotEq               (i) -> i
  | TInf                 (i) -> i
  | TSup                 (i) -> i
  | TInfEq               (i) -> i
  | TSupEq               (i) -> i
  | TShl                 (i) -> i
  | TShr                 (i) -> i
  | TPlus                (i) -> i
  | TMinus               (i) -> i
  | TMul                 (i) -> i
  | TDiv                 (i) -> i
  | TMod                 (i) -> i

  | Tchar                (i) -> i
  | Tshort               (i) -> i
  | Tint                 (i) -> i
  | Tdouble              (i) -> i
  | Tfloat               (i) -> i
  | Tlong                (i) -> i
  | Tunsigned            (i) -> i
  | Tsigned              (i) -> i
  | Tvoid                (i) -> i
  | Tauto                (i) -> i
  | Tregister            (i) -> i
  | Textern              (i) -> i
  | Tstatic              (i) -> i
  | Tconst               (i) -> i
  | Tvolatile            (i) -> i

  | Trestrict (i) -> i

  | Tstruct              (i) -> i
  | Tenum                (i) -> i
  | Ttypedef             (i) -> i
  | Tunion               (i) -> i
  | Tbreak               (i) -> i
  | Telse                (i) -> i
  | Tswitch              (i) -> i
  | Tcase                (i) -> i
  | Tcontinue            (i) -> i
  | Tfor                 (i) -> i
  | Tdo                  (i) -> i
  | Tif                  (i) -> i
  | Twhile               (i) -> i
  | Treturn              (i) -> i
  | Tgoto                (i) -> i
  | Tdefault             (i) -> i
  | Tsizeof              (i) -> i

  (* gccext: *)
  | Tasm                 (i) -> i
  | Tattribute           (i) -> i
  | Tinline              (i) -> i
  | Ttypeof              (i) -> i

  (* c++ext: *)
  | Tclass (i) -> i
  | Tthis (i) -> i

  | Tnew (i) -> i
  | Tdelete (i) -> i

  | Ttemplate (i) -> i
  | Ttypeid (i) -> i
  | Ttypename (i) -> i

  | Tcatch (i) -> i
  | Ttry (i) -> i
  | Tthrow (i) -> i

  | Toperator (i) -> i

  | Tpublic (i) -> i
  | Tprivate (i) -> i
  | Tprotected (i) -> i
  | Tfriend (i) -> i

  | Tvirtual (i) -> i

  | Tnamespace (i) -> i
  | Tusing (i) -> i

  | Tbool (i) -> i
  | Ttrue (i) -> i
  | Tfalse (i) -> i

  | Twchar_t (i) -> i

  | Tconst_cast (i) -> i
  | Tdynamic_cast (i) -> i
  | Tstatic_cast (i) -> i
  | Treinterpret_cast (i) -> i

  | Texplicit (i) -> i
  | Tmutable (i) -> i
  | Texport (i) -> i

  | TColCol (i) -> i
  | TColCol_BeforeTypedef (i) -> i

  | TPtrOpStar (i) -> i
  | TDotStar(i) -> i

  | TIdent_ClassnameInQualifier  (s, i) -> i
  | TIdent_ClassnameInQualifier_BeforeTypedef  (s, i) -> i
  | TIdent_Templatename  (s, i) -> i
  | TIdent_Constructor  (s, i) -> i
  | TIdent_TypedefConstr  (s, i) -> i
  | TIdent_TemplatenameInQualifier  (s, i) -> i
  | TIdent_TemplatenameInQualifier_BeforeTypedef  (s, i) -> i

  | TInf_Template                 (i) -> i
  | TSup_Template                 (i) -> i

  | TOCro_new                 (i) -> i
  | TCCro_new                (i) -> i

  | TInt_ZeroVirtual        (i) -> i

  | Tchar_Constr (i) -> i
  | Tint_Constr  (i) -> i
  | Tfloat_Constr (i) -> i
  | Tdouble_Constr  (i) -> i
  | Twchar_t_Constr (i) -> i

  | Tshort_Constr  (i) -> i
  | Tlong_Constr   (i) -> i
  | Tbool_Constr  (i) -> i

  | Tunsigned_Constr i -> i
  | Tsigned_Constr i -> i

  | TAt_interface i -> i
  | TAt_implementation i -> i
  | TAt_protocol i  -> i
  | TAt_class i -> i
  | TAt_selector i -> i
  | TAt_encode i -> i
  | TAt_defs i -> i
  | TAt_end i -> i
  | TAt_public i -> i
  | TAt_private i -> i
  | TAt_protected i -> i

  | TAt_throw i -> i
  | TAt_catch i -> i
  | TAt_try i -> i
  | TAt_finally i -> i
  | TAt_synchronized i -> i

  | TAt_property i -> i

  | TAt_synthesize i -> i
  | TAt_autoreleasepool i -> i
  | TAt_dynamic i -> i
  | TAt_YES i -> i
  | TAt_NO i -> i
  | TAt_optional i -> i
  | TAt_required i -> i
  | TAt_compatibility_alias i -> i
  | TAt_Misc i -> i

  | TAt i -> i      
  | EOF                  (i) -> i
  


(* used by tokens to complete the parse_info with filename, line, col infos *)
let visitor_info_of_tok f = function
  | TString ((s, isWchar), i)  -> TString ((s, isWchar), f i) 
  | TChar  ((s, isWchar), i)   -> TChar  ((s, isWchar), f i) 
  | TFloat ((s, floatType), i) -> TFloat ((s, floatType), f i) 
  | TAssign  (assignOp, i)     -> TAssign  (assignOp, f i) 

  | TIdent  (s, i)       -> TIdent  (s, f i) 
  | TIdent_Typedef  (s, i) -> TIdent_Typedef (s, f i) 

  | TInt  (s, i)         -> TInt  (s, f i) 

  (* cppext: *)
  | TDefine (i1) -> TDefine(f i1) 

  | TUndef (s,i1) -> TUndef(s, f i1) 
  | TCppDirectiveOther (i1) -> TCppDirectiveOther(f i1) 

  | TInclude (includes, filename, i1) -> 
      TInclude (includes, filename, f i1)

  | TCppEscapedNewline (i1) -> TCppEscapedNewline (f i1)
  | TCommentNewline_DefineEndOfMacro (i1) -> 
      TCommentNewline_DefineEndOfMacro (f i1)
  | TOPar_Define (i1) -> TOPar_Define (f i1)
  | TIdent_Define  (s, i) -> TIdent_Define (s, f i)

  | TDefParamVariadic (s, i1) -> TDefParamVariadic (s, f i1)

  | TOBrace_DefineInit (i1) -> TOBrace_DefineInit (f i1)


  | TUnknown             (i) -> TUnknown                (f i)

  | TIdent_MacroStmt           (i)   -> TIdent_MacroStmt            (f i)
  | TIdent_MacroString         (i)   -> TIdent_MacroString          (f i)
  | TIdent_MacroIterator       (s,i) -> TIdent_MacroIterator        (s,f i)
  | TIdent_MacroDecl           (s,i) -> TIdent_MacroDecl            (s, f i)
  | Tconst_MacroDeclConst      (i)   -> Tconst_MacroDeclConst       (f i)
(*  | TMacroTop          (s,i) -> TMacroTop             (s,f i) *)
  | TCPar_EOL (i) ->     TCPar_EOL (f i)


  | TAny_Action               (i) -> TAny_Action             (f i)

  | TComment             (i) -> TComment             (f i) 
  | TCommentSpace        (i) -> TCommentSpace        (f i) 
  | TCommentNewline         (i) -> TCommentNewline         (f i) 

  | TComment_Pp          (cppkind, i) -> TComment_Pp          (cppkind, f i) 
  | TComment_Cpp          (cppkind, i) -> TComment_Cpp          (cppkind, f i) 

  | TIfdef               (i) -> TIfdef               (f i) 
  | TIfdefelse           (i) -> TIfdefelse           (f i) 
  | TIfdefelif           (i) -> TIfdefelif           (f i) 
  | TEndif               (i) -> TEndif               (f i) 
  | TIfdefBool           (b, i) -> TIfdefBool        (b, f i) 
  | TIfdefMisc           (b, i) -> TIfdefMisc        (b, f i) 
  | TIfdefVersion        (b, i) -> TIfdefVersion     (b, f i) 

  | TOPar                (i) -> TOPar                (f i) 
  | TOPar_CplusplusInit                (i) -> TOPar_CplusplusInit     (f i) 
  | TCPar                (i) -> TCPar                (f i) 
  | TOBrace              (i) -> TOBrace              (f i) 
  | TCBrace              (i) -> TCBrace              (f i) 
  | TOCro                (i) -> TOCro                (f i) 
  | TCCro                (i) -> TCCro                (f i) 
  | TDot                 (i) -> TDot                 (f i) 
  | TComma               (i) -> TComma               (f i) 
  | TPtrOp               (i) -> TPtrOp               (f i) 
  | TInc                 (i) -> TInc                 (f i) 
  | TDec                 (i) -> TDec                 (f i) 
  | TEq                  (i) -> TEq                  (f i) 
  | TWhy                 (i) -> TWhy                 (f i) 
  | TTilde               (i) -> TTilde               (f i) 
  | TBang                (i) -> TBang                (f i) 
  | TEllipsis            (i) -> TEllipsis            (f i) 
  | TCol              (i) -> TCol              (f i) 
  | TPtVirg              (i) -> TPtVirg              (f i) 
  | TOrLog               (i) -> TOrLog               (f i) 
  | TAndLog              (i) -> TAndLog              (f i) 
  | TOr                  (i) -> TOr                  (f i) 
  | TXor                 (i) -> TXor                 (f i) 
  | TAnd                 (i) -> TAnd                 (f i) 
  | TEqEq                (i) -> TEqEq                (f i) 
  | TNotEq               (i) -> TNotEq               (f i) 
  | TInf                 (i) -> TInf                 (f i) 
  | TSup                 (i) -> TSup                 (f i) 
  | TInfEq               (i) -> TInfEq               (f i) 
  | TSupEq               (i) -> TSupEq               (f i) 
  | TShl                 (i) -> TShl                 (f i) 
  | TShr                 (i) -> TShr                 (f i) 
  | TPlus                (i) -> TPlus                (f i) 
  | TMinus               (i) -> TMinus               (f i) 
  | TMul                 (i) -> TMul                 (f i) 
  | TDiv                 (i) -> TDiv                 (f i) 
  | TMod                 (i) -> TMod                 (f i) 
  | Tchar                (i) -> Tchar                (f i) 
  | Tshort               (i) -> Tshort               (f i) 
  | Tint                 (i) -> Tint                 (f i) 
  | Tdouble              (i) -> Tdouble              (f i) 
  | Tfloat               (i) -> Tfloat               (f i) 
  | Tlong                (i) -> Tlong                (f i) 
  | Tunsigned            (i) -> Tunsigned            (f i) 
  | Tsigned              (i) -> Tsigned              (f i) 
  | Tvoid                (i) -> Tvoid                (f i) 
  | Tauto                (i) -> Tauto                (f i) 
  | Tregister            (i) -> Tregister            (f i) 
  | Textern              (i) -> Textern              (f i) 
  | Tstatic              (i) -> Tstatic              (f i) 
  | Tconst               (i) -> Tconst               (f i) 
  | Tvolatile            (i) -> Tvolatile            (f i) 

  | Trestrict            (i) -> Trestrict            (f i) 


  | Tstruct              (i) -> Tstruct              (f i) 
  | Tenum                (i) -> Tenum                (f i) 
  | Ttypedef             (i) -> Ttypedef             (f i) 
  | Tunion               (i) -> Tunion               (f i) 
  | Tbreak               (i) -> Tbreak               (f i) 
  | Telse                (i) -> Telse                (f i) 
  | Tswitch              (i) -> Tswitch              (f i) 
  | Tcase                (i) -> Tcase                (f i) 
  | Tcontinue            (i) -> Tcontinue            (f i) 
  | Tfor                 (i) -> Tfor                 (f i) 
  | Tdo                  (i) -> Tdo                  (f i) 
  | Tif                  (i) -> Tif                  (f i) 
  | Twhile               (i) -> Twhile               (f i) 
  | Treturn              (i) -> Treturn              (f i) 
  | Tgoto                (i) -> Tgoto                (f i) 
  | Tdefault             (i) -> Tdefault             (f i) 
  | Tsizeof              (i) -> Tsizeof              (f i) 
  | Tasm                 (i) -> Tasm                 (f i) 
  | Tattribute           (i) -> Tattribute           (f i) 
  | Tinline              (i) -> Tinline              (f i) 
  | Ttypeof              (i) -> Ttypeof              (f i) 


  | Tclass (i) -> Tclass (f i)
  | Tthis (i) -> Tthis (f i)

  | Tnew (i) -> Tnew (f i)
  | Tdelete (i) -> Tdelete (f i)

  | Ttemplate (i) -> Ttemplate (f i)
  | Ttypeid (i) -> Ttypeid (f i)
  | Ttypename (i) -> Ttypename (f i)

  | Tcatch (i) -> Tcatch (f i)
  | Ttry (i) -> Ttry (f i)
  | Tthrow (i) -> Tthrow (f i)

  | Toperator (i) -> Toperator (f i)

  | Tpublic (i) -> Tpublic (f i)
  | Tprivate (i) -> Tprivate (f i)
  | Tprotected (i) -> Tprotected (f i)
  | Tfriend (i) -> Tfriend (f i)

  | Tvirtual (i) -> Tvirtual (f i)

  | Tnamespace (i) -> Tnamespace (f i)
  | Tusing (i) -> Tusing (f i)

  | Tbool (i) -> Tbool (f i)
  | Ttrue (i) -> Ttrue (f i)
  | Tfalse (i) -> Tfalse (f i)

  | Twchar_t (i) -> Twchar_t (f i)

  | Tconst_cast (i) -> Tconst_cast (f i)
  | Tdynamic_cast (i) -> Tdynamic_cast (f i)
  | Tstatic_cast (i) -> Tstatic_cast (f i)
  | Treinterpret_cast (i) -> Treinterpret_cast (f i)

  | Texplicit (i) -> Texplicit (f i)
  | Tmutable (i) -> Tmutable (f i)

  | Texport (i) -> Texport (f i)



  | TColCol (i) -> TColCol (f i)
  | TColCol_BeforeTypedef (i) -> TColCol_BeforeTypedef (f i)

  | TPtrOpStar (i) -> TPtrOpStar (f i)
  | TDotStar(i) -> TDotStar (f i)


  | TIdent_ClassnameInQualifier  (s, i) -> TIdent_ClassnameInQualifier (s, f i) 
  | TIdent_ClassnameInQualifier_BeforeTypedef  (s, i) -> 
      TIdent_ClassnameInQualifier_BeforeTypedef  (s, f i) 
  | TIdent_Templatename  (s, i) -> TIdent_Templatename  (s, f i) 
  | TIdent_Constructor  (s, i) -> TIdent_Constructor  (s, f i) 
  | TIdent_TypedefConstr  (s, i) -> TIdent_TypedefConstr  (s, f i) 

  | TIdent_TemplatenameInQualifier  (s, i) -> 
      TIdent_TemplatenameInQualifier  (s, f i) 
  | TIdent_TemplatenameInQualifier_BeforeTypedef  (s, i) -> 
      TIdent_TemplatenameInQualifier_BeforeTypedef  (s, f i) 

  | TInf_Template                 (i) -> TInf_Template                 (f i) 
  | TSup_Template                 (i) -> TSup_Template                 (f i) 

  | TOCro_new                 (i) -> TOCro_new                 (f i) 
  | TCCro_new                 (i) -> TCCro_new                 (f i) 


  | TInt_ZeroVirtual (i) -> TInt_ZeroVirtual (f i)

  | Tchar_Constr                 (i) -> Tchar_Constr                 (f i) 
  | Tint_Constr                 (i) -> Tint_Constr                 (f i) 
  | Tfloat_Constr                 (i) -> Tfloat_Constr                 (f i) 
  | Tdouble_Constr                 (i) -> Tdouble_Constr                 (f i) 
  | Twchar_t_Constr                 (i) -> Twchar_t_Constr                 (f i) 

  | Tshort_Constr  (i) -> Tshort_Constr (f i)
  | Tlong_Constr   (i) -> Tlong_Constr (f i)
  | Tbool_Constr  (i) -> Tbool_Constr (f i)

  | Tsigned_Constr  (i) -> Tsigned_Constr (f i)
  | Tunsigned_Constr  (i) -> Tunsigned_Constr (f i)

  | TAt_interface i -> TAt_interface (f i)
  | TAt_implementation i -> TAt_implementation (f i)
  | TAt_protocol i  -> TAt_protocol (f i)
  | TAt_class i -> TAt_class (f i)
  | TAt_selector i -> TAt_selector (f i)
  | TAt_encode i -> TAt_encode (f i)
  | TAt_defs i -> TAt_defs (f i)
  | TAt_end i -> TAt_end (f i)
  | TAt_public i -> TAt_public (f i)
  | TAt_private i -> TAt_private (f i)
  | TAt_protected i -> TAt_protected (f i)

  | TAt_throw i -> TAt_throw (f i)
  | TAt_catch i -> TAt_catch (f i)
  | TAt_try i -> TAt_try (f i)
  | TAt_finally i -> TAt_finally (f i)
  | TAt_synchronized i -> TAt_synchronized (f i)

  | TAt_property i -> TAt_property (f i)

  | TAt_synthesize i -> TAt_synthesize (f i)
  | TAt_autoreleasepool i -> TAt_autoreleasepool (f i)
  | TAt_dynamic i -> TAt_dynamic (f i)
  | TAt_YES i -> TAt_YES (f i)
  | TAt_NO i -> TAt_NO (f i)
  | TAt_optional i -> TAt_optional (f i)
  | TAt_required i -> TAt_required (f i)
  | TAt_compatibility_alias i -> TAt_compatibility_alias (f i)
  | TAt_Misc i -> TAt_Misc (f i)
  | TAt i -> TAt (f i)
  | EOF                  (i) -> EOF                  (f i) 


(*****************************************************************************)
(* Accessors *)
(*****************************************************************************)

let linecol_of_tok tok =
  let info = info_of_tok tok in
  Ast.line_of_info info, Ast.col_of_info info

let col_of_tok x = snd (linecol_of_tok x)
let line_of_tok x = fst (linecol_of_tok x)

let str_of_tok tok = Parse_info.str_of_info (info_of_tok tok)
let pos_of_tok tok = Parse_info.pos_of_info (info_of_tok tok)
let file_of_tok tok = Parse_info.file_of_info (info_of_tok tok)
(*****************************************************************************)
(* For unparsing *)
(*****************************************************************************)

open Lib_unparser

let elt_of_tok tok =
  let info = info_of_tok tok in
  let str = Parse_info.str_of_info info in
  match tok with
  | TComment _ | TComment_Pp _ | TComment_Cpp _ -> Esthet (Comment str)
  | TCommentSpace _ -> Esthet (Space str)
  | TCommentNewline _ -> Esthet Newline
  (* just after a ?>, the newline are not anymore TNewline but that *)
  (*| T_INLINE_HTML ("\n", _) -> Esthet Newline *)
  | _ -> OrigElt str
