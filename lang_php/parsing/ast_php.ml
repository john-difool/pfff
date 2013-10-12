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
open Common

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
 * This module defines an Abstract Syntax Tree for PHP 5.2 with
 * a few PHP 5.3 (e.g. closures, namespace, const) and 5.4 (e.g. traits) 
 * extensions as well as support for many Facebook extensions (XHP, generators,
 * annotations, generics, collections, type definitions, implicit fields
 * via constructor parameters).
 *
 * This is actually more a concrete syntax tree (CST) than an AST. This
 * is convenient in a refactoring context or code visualization
 * context, but if you need to do some heavy static analysis, consider
 * instead lang_php/analyze/foundation/pil.ml which defines a
 * PHP Intermediate Language a la CIL.
 *
 * todo:
 *  - unify toplevel statement vs statements? hmmm maybe not
 *  - maybe even in a refactoring context a PIL+comment
 *    (see pretty/ast_pp.ml) would make more sense.
 *
 * NOTE: data from this type are often marshalled in berkeley DB tables
 * which means that if you add a new constructor or field in the types below,
 * you must erase the berkeley DB databases otherwise pfff
 * will probably ends with a segfault (OCaml serialization is not
 * type-safe). A hacky solution is to add new constructors only at the end
 * of a type definition.
 *
 * COUPLING: some programs in other languages (e.g. Python) may
 * use some of the pfff binding, or JSON/sexp exporters, so if you
 * change the name of constructors in this file, don't forget
 * to regenerate the JSON/sexp exporters, but also to modify the
 * dependent programs !!!! An easier solution is to not change this
 * file, or to only add new constructors.
 *
 *)

(*****************************************************************************)
(* The AST related types *)
(*****************************************************************************)

(* ------------------------------------------------------------------------- *)
(* Token/info *)
(* ------------------------------------------------------------------------- *)
(* Contains among other things the position of the token through
 * the Parse_info.parse_info embedded inside it, as well as the
 * transformation field that makes possible spatch.
 *)
type tok = Parse_info.info
and info = tok

(* shortcuts to annotate some information with token/position information *)
and 'a wrap = 'a * tok
and 'a paren   = tok * 'a * tok
and 'a brace   = tok * 'a * tok
and 'a bracket = tok * 'a * tok
and 'a angle = tok * 'a * tok
and 'a single_angle = tok * 'a * tok
and 'a comma_list = ('a, tok (* the comma *)) Common.either list
and 'a comma_list_dots =
  ('a, tok (* ... in parameters *), tok (* the comma *)) Common.either3 list
  (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* Ident/Name/LongName   *)
(* ------------------------------------------------------------------------- *)
(* See also analyze_php/namespace_php.ml *)

(* Why not factorize Name and XhpName together? Because I was not
 * sure originally some analysis should also be applied on Xhp
 * classes. Moreover there is two syntax for xhp: :x:base for 'defs'
 * and <x:base for 'uses', so having this xhp_tag allow us to easily do
 * comparison between xhp identifiers.
 * (was called T_STRING in Zend, which are really just LABEL, see the lexer)
 *)
type ident =
    | Name of string wrap
    (* xhp: for :x:foo the list is ["x";"foo"] *)
    | XhpName of xhp_tag wrap
 (* for :x:foo the list is ["x";"foo"] *)
 and xhp_tag = string list

(* The string does not contain the '$'. The info itself will usually
 * contain it, but not always! Indeed if the variable we build comes
 * from an encapsulated strings as in  echo "${x[foo]}" then the 'x'
 * will be parsed as a T_STRING_VARNAME, and eventually lead to a DName,
 * even if in the text it appears as a name.
 * So this token is kind of a FakeTok sometimes.
 *
 * So if at some point you want to do some program transformation,
 * you may have to normalize this string wrap before moving it
 * in another context !!!
 * 
 * (D for dollar. Was called T_VARIABLE in the original PHP parser/lexer)
 *)
type dname =
   | DName of string wrap

(* The antislash is a separator but it can also be in the leading position.
 * The keyword 'namespace' can also be in a leading position.
 *)
type qualified_ident = qualified_ident_element list
  and qualified_ident_element =
  | QI of ident (* the ident can be 'namespace' *)
  | QITok of tok (* '\' *)
 (* with tarzan *)

type name =
   | XName of qualified_ident
   (* Could also transform at parsing time all occurences of self:: and
    * parent:: by their respective names. But I prefer to have all the
    * PHP features somehow explicitely represented in the AST.
    *)
   | Self   of tok
   | Parent of tok
   (* php 5.3 late static binding (no idea why it's useful ...) *)
   | LateStatic of tok
 (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* Types *)
(* ------------------------------------------------------------------------- *)

type hint_type =
 | Hint of name (* only self/parent, no static *) * type_args option
 | HintArray of tok
 | HintQuestion of (tok * hint_type)
 | HintTuple of hint_type comma_list paren
 | HintCallback of
     (tok                                 (* "function" *)
      * (hint_type comma_list_dots paren) (* params *)
      * (tok * hint_type) option                  (* return type *)
     ) paren
 | HintShape of tok (* "shape" *) * 
                (string wrap * tok (* '=>' *) * hint_type) comma_list paren

 and type_args = hint_type comma_list single_angle

 and type_params = type_param comma_list single_angle
  and type_param =
  | TParam of ident
  | TParamConstraint of ident * tok (* as *) * class_name

and class_name = hint_type

(* This is used in Cast. For type analysis see type_php.ml *)
and ptype =
  | BoolTy
  | IntTy
  | DoubleTy (* float *)

  | StringTy

  | ArrayTy
  | ObjectTy

(* ------------------------------------------------------------------------- *)
(* Expression *)
(* ------------------------------------------------------------------------- *)
(* I used to have a 'type expr = exprbis * exp_type_info' but it complicates
 * many patterns when working on expressions, and it turns out I never
 * implemented the type annotater. It's easier to do such annotater on
 * a real AST like the PIL. So just have this file be a simple concrete
 * syntax tree and no more.
 *)
and expr =
  (* cst/function/class/method/field/class_cst name.
   *  
   * Now that we've unified lvalue and expr, the use of Id is more
   * ambiguous; it can refer to a classname, a function name,
   * a constant, etc. You need to match the context of use of Id
   * to know in which situation you are (and take care if you use a visitor
   * to not always call recursively the visitor/continuation):
   * 
   * - function: Call (Id, _)
   * - method: Call (ObjGet (_, Id), _),   Call (ClassGet (_, Id), _)
   * - class: ClassGet (Id, _), New (Id, _), AssignNew(Id,_, InstanceOf(_, Id)
   *   and also extends, implements, catch, type
   * - class_constant: ClassGet (_, Id)
   * - field: ObjGet(_, Id)
   * - constant: Id 
   * 
   * todo: just like we annotate IdVar with scope info, we could annotate
   * Id with a kind info.
   *)
  | Id of name

  (* less: maybe could unify 
   * note that IdVar is used not only for local variables
   * but also globals, class variables, parameters, etc.
   *)
  | IdVar of dname * Scope_php.phpscope ref
  | This of tok

  | Call of expr * argument comma_list paren
  | ObjGet of expr * tok (* -> *) * expr
  | ClassGet of class_name_reference * tok (* :: *) * expr
  | ArrayGet of expr * expr option bracket
  | HashGet of expr * expr brace
  | BraceIdent of expr brace
  | Deref of tok (* $ *) * expr

  (* start of expr_without_variable in original PHP lexer/parser terminology *)
  | Sc of scalar

  | Binary  of expr * binaryOp wrap * expr
  | Unary   of unaryOp wrap * expr
  (* should be a statement ... *)
  | Assign    of lvalue * tok (* = *) * expr
  | AssignOp  of lvalue * assignOp wrap * expr
  | Postfix of rw_variable   * fixOp wrap
  | Infix   of fixOp wrap    * rw_variable
  (* PHP 5.3 allow 'expr ?: expr' hence the 'option' type below
   * from www.php.net/manual/en/language.operators.comparison.php#language.operators.comparison.ternary:
   * "Since PHP 5.3, it is possible to leave out the middle part of the
   * ternary operator. Expression
   * expr1 ?: expr3 returns expr1 if expr1 evaluates to TRUE, and expr3
   * otherwise."
   *)
  | CondExpr of expr * tok (* ? *) * expr option * tok (* : *) * expr
  | AssignList  of tok (* list *)  * list_assign comma_list paren *
        tok (* = *) * expr

  | ArrayLong of tok (* array | shape *) * array_pair  comma_list paren
  (* php 5.4: https://wiki.php.net/rfc/shortsyntaxforarrays *)
  | ArrayShort of array_pair comma_list bracket
  (* facebook-ext: *)
  | Collection of name * array_pair comma_list brace

  | New of tok * class_name_reference * argument comma_list paren option
  | Clone of tok * expr
  | AssignRef of lvalue * tok (* = *) * tok (* & *) * lvalue
  | AssignNew of lvalue * tok (* = *) * tok (* & *) * tok (* new *) *
        class_name_reference *
        argument comma_list paren option
  | Cast of castOp wrap * expr
  | CastUnset of tok * expr (* ??? *)
  | InstanceOf of expr * tok * class_name_reference
  (* !The evil eval! *)
  | Eval of tok * expr paren
  (* Woohoo, viva PHP 5.3 *)
  | Lambda of lambda_def
  (* should be a statement ... *)
  | Exit of tok * (expr option paren) option
  | At of tok (* @ *) * expr
  | Print of tok * expr
  | BackQuote of tok * encaps list * tok
  (* should be at toplevel *)
  | Include     of tok * expr | IncludeOnce of tok * expr
  | Require     of tok * expr | RequireOnce of tok * expr
  | Empty of tok * lvalue paren
  | Isset of tok * lvalue comma_list paren

  (* xhp: *)
  | XhpHtml of xhp_html
  (* php-facebook-ext:
   *
   * todo: this should be at the statement level as there are only a few
   * forms of yield that hphp support (e.g. yield <expr>; and
   * <lval> = yield <expr>). One could then have a YieldReturn and YieldAssign
   * but this may change and none of the analysis in pfff need to
   * understand yield so for now just make it simple and add yield
   * at the expression level.
   *)
  | Yield of tok * expr
  | YieldBreak of tok * tok
  (* php-facebook-ext:
   *
   * Just like yield, this should be at the statement level 
   *)
  | Await of tok * expr

  (* only appear when process sgrep patterns *)
  | SgrepExprDots of tok
  (* unparser: *)
  | ParenExpr of expr paren

    and scalar =
      | C of constant
      | Guil    of tok (* '"' or b'"' *) * encaps list * tok (* '"' *)
      | HereDoc of
          tok (* < < < EOF, or b < < < EOF *) *
          encaps list *
          tok  (* EOF; *)
      (* | StringVarName??? *)

       and constant =
        | Int of string wrap
        | Double of string wrap
        (* see also Guil for interpolated strings
         * The string does not contain the enclosing '"' or "'".
         * It does not contain either the possible 'b' prefix
         *)
        | String of string wrap
        | PreProcess of cpp_directive wrap
        (* only appear when process xdebug coverage file *)
        | XdebugClass of name * class_stmt list
        | XdebugResource
        (* http://php.net/manual/en/language.constants.predefined.php *)
          and cpp_directive =
              | Line  | File | Dir
              | ClassC | TraitC
              | MethodC  | FunctionC
              | NamespaceC
       and encaps =
          | EncapsString of string wrap
          | EncapsVar of lvalue
          (* for "xx {$beer}s" *)
          | EncapsCurly of tok * lvalue * tok
          (* for "xx ${beer}s" *)
          | EncapsDollarCurly of tok (* '${' *) * lvalue * tok
          | EncapsExpr of tok * expr * tok

   and fixOp    = Dec | Inc
   and binaryOp    = Arith of arithOp | Logical of logicalOp
      | BinaryConcat (* . *)
         and arithOp   =
           | Plus | Minus | Mul | Div | Mod
           | DecLeft | DecRight
           | And | Or | Xor

         and logicalOp =
           | Inf | Sup | InfEq | SupEq
           | Eq | NotEq
           | Identical (* === *) | NotIdentical (* !== *)
           | AndLog | OrLog | XorLog
           | AndBool | OrBool (* diff with AndLog ? short-circuit operators ? *)
   and assignOp = AssignOpArith of arithOp
     | AssignConcat (* .= *)
   and unaryOp =
     | UnPlus | UnMinus
     | UnBang | UnTilde

   and castOp = ptype

   and list_assign =
     | ListVar of lvalue
     | ListList of tok * list_assign comma_list paren
     | ListEmpty
   and array_pair =
     | ArrayExpr of expr
     | ArrayRef of tok (* & *) * lvalue
     | ArrayArrowExpr of expr * tok (* => *) * expr
     | ArrayArrowRef of expr * tok (* => *) * tok (* & *) * lvalue
   and vector_elt =
     | VectorExpr of expr
     | VectorRef of tok (* & *) * lvalue
   and map_elt =
     | MapArrowExpr of expr * tok (* => *) * expr
     | MapArrowRef of expr * tok (* => *) * tok (* & *) * lvalue

 and xhp_html =
   | Xhp of xhp_tag wrap * xhp_attribute list * tok (* > *) *
       xhp_body list * xhp_tag option wrap
   | XhpSingleton of xhp_tag wrap * xhp_attribute list * tok (* /> *)

   and xhp_attribute = xhp_attr_name * tok (* = *) * xhp_attr_value
    and xhp_attr_name = string wrap (* e.g. task-bar *)
    and xhp_attr_value =
      | XhpAttrString of tok (* '"' *) * encaps list * tok (* '"' *)
      | XhpAttrExpr of expr brace
      (* sgrep: *)
      | SgrepXhpAttrValueMvar of string wrap
   and xhp_body =
     | XhpText of string wrap
     | XhpExpr of expr brace
     | XhpNested of xhp_html

    and argument =
      | Arg    of expr
      | ArgRef of tok * w_variable

(* now unified with expr *)
and lvalue = expr
and class_name_reference = expr
(* semantic: those grammar rule names were used in the original PHP
 * lexer/parser but not enforced. It's just comments. *)
and rw_variable = lvalue
and r_variable = lvalue
and w_variable = lvalue
(* static_scalar used to be a special type allowing constants and
 * a restricted form of expressions. But it was yet
 * another type and it turned out it was making things like spatch
 * and visitors more complicated because stuff like "+ 1" could
 * be an expr or a static_scalar. We don't need this "isomorphism".
 * I never leveraged the specificities of static_scalar (maybe a compiler
 * would, but my checker/refactorers/... don't).
 *
 * Note that it's not 'type static_scalar = scalar' because static_scalar
 * actually allows arrays (why the heck they called it a scalar then ....)
 * and plus/minus which are only in expr.
 *)
 and static_scalar = expr

(* ------------------------------------------------------------------------- *)
(* Statement *)
(* ------------------------------------------------------------------------- *)
(* By introducing Lambda, expr and stmt are now mutually recursive *)
and stmt =
    | ExprStmt of expr * tok (* ; *)
    | EmptyStmt of tok  (* ; *)
    | Block of stmt_and_def list brace
    | If      of tok * expr paren * stmt *
        (* elseif *) if_elseif list *
        (* else *)   if_else option
    | IfColon of tok * expr paren *
          tok * stmt_and_def list * new_elseif list * new_else option *
          tok * tok
      (* if(cond):
       *   stmts; defs;
       * elseif(cond):
       *   stmts;..
       * else(cond):
       *   defs; stmst;
       * endif; *)
    | While of tok * expr paren * colon_stmt
    | Do of tok * stmt * tok * expr paren * tok
    | For of tok * tok *
        for_expr * tok *
        for_expr * tok *
        for_expr *
        tok *
        colon_stmt
    | Switch of tok * expr paren * switch_case_list
    (* if it's a expr_without_variable, the second arg must be a Right variable,
     * otherwise if it's a variable then it must be a foreach_variable
     *)
    | Foreach of tok * tok (*'('*) * expr * tok (* as *) * foreach_pattern *
        tok (*')'*) * colon_stmt
      (* example: foreach(expr as $lvalue) { ... }
       *          foreach(expr as $foreach_varialbe => $lvalue) { ... }
       *          foreach(expr as list($x, $y)) { ... }
       *)
    | Break    of tok * expr option * tok
    | Continue of tok * expr option * tok
    | Return of tok * expr option * tok
    | Throw of tok * expr * tok
    | Try of tok * stmt_and_def list brace * catch * catch list
    | Echo of tok * expr comma_list * tok
    | Globals    of tok * global_var comma_list * tok
    | StaticVars of tok * static_var comma_list * tok
    | InlineHtml of string wrap
    | Use of tok * use_filename * tok
    | Unset of tok * lvalue comma_list paren * tok
    | Declare of tok * declare comma_list paren * colon_stmt

    (* nested funcs and classes are mostly used inside if() where the
     * if() actually behaves like an ifdef in C.
     *)
    (* was in stmt_and_def before *)
    | FuncDefNested of func_def
    (* traits are actually not allowed here *)
    | ClassDefNested of class_def

    and switch_case_list =
      | CaseList      of
          tok (* { *) * tok option (* ; *) * case list * tok (* } *)
      | CaseColonList of
          tok (* : *) * tok option (* ; *) * case list *
          tok (* endswitch *) * tok (* ; *)
      and case =
        | Case    of tok * expr * tok * stmt_and_def list
        | Default of tok * tok * stmt_and_def list

   and if_elseif = tok * expr paren * stmt
   and if_else = (tok * stmt)
    and for_expr = expr comma_list (* can be empty *)
    and foreach_pattern =
     | ForeachVar of foreach_variable
     | ForeachArrow of foreach_pattern * tok * foreach_pattern
     | ForeachList of tok (* list *)  * list_assign comma_list paren
     and foreach_variable = is_ref * lvalue
    and catch =
      tok * (class_name * dname) paren * stmt_and_def list brace
    and use_filename =
      | UseDirect of string wrap
      | UseParen  of string wrap paren
    and declare = ident * static_scalar_affect
    and colon_stmt =
      | SingleStmt of stmt
      | ColonStmt of tok (* : *) * stmt_and_def list * tok (* endxxx *) * tok (* ; *)
    and new_elseif = tok * expr paren * tok * stmt_and_def list
    and new_else = tok * tok * stmt_and_def list
(* ------------------------------------------------------------------------- *)
(* Function (and method) definition *)
(* ------------------------------------------------------------------------- *)
and func_def = {
  f_attrs: attributes option;
  f_tok: tok; (* function *)
  f_type: function_type;
  (* only valid for methods *)
  f_modifiers: modifier wrap list;
  f_ref: is_ref;
  (* can be a Name("__lambda", f_tok) when used for lambdas *)
  f_name: ident;
  f_tparams: type_params option;
  (* the dots should be only at the end (unless in sgrep mode) *)
  f_params: parameter comma_list_dots paren;
  (* static-php-ext: *)
  f_return_type: (tok (* : *) * hint_type) option;
  (* the opening/closing brace can be (fakeInfo(), ';') for abstract methods *)
  f_body: stmt_and_def list brace;
}
    and function_type =
      | FunctionRegular
      | FunctionLambda
      | MethodRegular
      | MethodAbstract

    and parameter = {
      p_attrs: attributes option;
      (* php-facebook-ext: implicit field via constructor parameter,
       * this is always None except for constructors and the modifier
       * can be only Public or Protected or Private (but never Static, etc).
       *)
      p_modifier: modifier wrap option;
      (* php-facebook-ext: to not generate runtine errors if wrong type hint *)
      p_soft_type: tok (* @ *) option;
      p_type: hint_type option;
      p_ref: is_ref;
      p_name: dname;
      p_default: static_scalar_affect option;
    }
    and is_ref = tok (* bool wrap ? *) option
(* the f_name in func_def should be a fake name *)
and lambda_def = (lexical_vars option * func_def)
  and lexical_vars = tok (* use *) * lexical_var comma_list paren
  and lexical_var = LexicalVar of is_ref * dname

(* ------------------------------------------------------------------------- *)
(* Constant definition *)
(* ------------------------------------------------------------------------- *)
and constant_def = {
  cst_toks: tok (* const *) * tok (* = *) * tok (* ; *);
  cst_name: ident;
  cst_type: hint_type option;
  cst_val: static_scalar;
}

(* ------------------------------------------------------------------------- *)
(* Class (and interface/trait) definition *)
(* ------------------------------------------------------------------------- *)
(* I used to have a class_def and interface_def because interface_def
 * didn't allow certain forms of statements (methods with a body), but
 * with the introduction of traits, it does not make that much sense
 * to be so specific, so I factorized things. Classes/interfaces/traits
 * are not that different. Interfaces are really just abstract traits.
 *)
and class_def = {
  c_attrs: attributes option;
  c_type: class_type;
  c_name: ident;
  c_tparams: type_params option;
  (* PHP uses single inheritance. Interfaces can also use 'extends'
   * but we use the c_implements field for that (because it can be a list).
   *)
  c_extends: extend option;
  (* For classes it's a list of interfaces, for interface a list of other
   * interfaces it extends. Traits can also now implement interfaces.
   *)
  c_implements: interface option;
  (* The class_stmt for interfaces are restricted to only abstract methods.
   * The class_stmt seems to be unrestricted for traits; can even
   * have some 'use' *)
  c_body: class_stmt list brace;
}
    and class_type =
      | ClassRegular  of tok (* class *)
      | ClassFinal    of tok * tok (* final class *)
      | ClassAbstract of tok * tok (* abstract class *)

      | Interface of tok (* interface *)
      (* PHP 5.4 traits: http://php.net/manual/en/language.oop5.traits.php
       * Allow to mixin behaviors and data so it's really just
       * multiple inheritance with a cooler name.
       *
       * note: traits are allowed only at toplevel.
       *)
      | Trait of tok (* trait *)
    and extend =    tok * class_name
    and interface = tok * class_name comma_list
  and class_stmt =
    | ClassConstants of tok (* const *) * class_constant comma_list * tok (*;*)
    | ClassVariables of
        class_var_modifier *
         (* static-php-ext: *)
          hint_type option *
        class_variable comma_list * tok (* ; *)
    | Method of method_def

    | XhpDecl of xhp_decl
    (* php 5.4, 'use' can appear in classes/traits (but not interface) *)
    | UseTrait of tok (*use*) * class_name comma_list *
        (tok (* ; *), trait_rule list brace) Common.either

        and class_constant = ident * static_scalar_affect
        and class_variable = dname * static_scalar_affect option
        and class_var_modifier =
          | NoModifiers of tok (* 'var' *)
          | VModifiers of modifier wrap list
        (* a few special names: __construct, __call, __callStatic
         * ugly: f_body is an empty stmt_and_def for abstract method
         * and the ';' is put for the info of the closing brace
         * (and the opening brace is a fakeInfo).
         *)
        and method_def = func_def
          and modifier =
            | Public  | Private | Protected
            | Static  | Abstract | Final | Async
 and xhp_decl =
    | XhpAttributesDecl of
        tok (* attribute *) * xhp_attribute_decl comma_list * tok (*;*)
    (* there is normally only one 'children' declaration in a class *)
    | XhpChildrenDecl of
        tok (* children *) * xhp_children_decl * tok (*;*)
    | XhpCategoriesDecl of
        tok (* category *) * xhp_category_decl comma_list * tok (*;*)

 and xhp_attribute_decl =
   | XhpAttrInherit of xhp_tag wrap
   | XhpAttrDecl of xhp_attribute_type * xhp_attr_name *
       xhp_value_affect option * tok option (* is required *)
   and xhp_attribute_type =
     | XhpAttrType of hint_type
     | XhpAttrVar of tok
     | XhpAttrEnum of tok (* enum *) * constant comma_list brace
  and xhp_value_affect = tok (* = *) * static_scalar

 (* Regexp-like syntax. The grammar actually restricts what kinds of
  * regexps can be written. For instance pcdata must be nested. But
  * here I simplified the type.
  *)
 and xhp_children_decl =
   | XhpChild of xhp_tag wrap (* :x:frag *)
   | XhpChildCategory of xhp_tag wrap (* %x:frag *)

   | XhpChildAny of tok
   | XhpChildEmpty of tok
   | XhpChildPcdata of tok

   | XhpChildSequence    of xhp_children_decl * tok (*,*) * xhp_children_decl
   | XhpChildAlternative of xhp_children_decl * tok (*|*) * xhp_children_decl

   | XhpChildMul    of xhp_children_decl * tok (* * *)
   | XhpChildOption of xhp_children_decl * tok (* ? *)
   | XhpChildPlus   of xhp_children_decl * tok (* + *)

   | XhpChildParen of xhp_children_decl paren

 and xhp_category_decl = xhp_tag wrap (* %x:frag *)

(* those are bad features ... noone should use them. *)
and trait_rule = 
  | InsteadOf of name * tok * ident * tok (* insteadof *) * 
                class_name comma_list * tok (* ; *)
  | As of (ident, name * tok * ident) Common.either * tok (* as *) *
          modifier wrap list * ident option * tok (* ; *)


(* ------------------------------------------------------------------------- *)
(* Type definition *)
(* ------------------------------------------------------------------------- *)
and type_def = {
  t_tok: tok; (* type/newtype *)
  t_name: ident;
  t_tparams: type_params option;
  t_tokeq: tok; (* = *)
  t_kind: type_def_kind;
  t_sc: tok; (* ; *)
}
  and type_def_kind =
  | Alias of hint_type
  | Newtype of hint_type

(* ------------------------------------------------------------------------- *)
(* Other declarations *)
(* ------------------------------------------------------------------------- *)
and global_var =
  | GlobalVar of dname
  | GlobalDollar of tok * r_variable
  | GlobalDollarExpr of tok * expr brace
and static_var = dname * static_scalar_affect option
   and static_scalar_affect = tok (* = *) * static_scalar
(* stmt_and_def used to be a special type allowing Stmt or nested functions
 * or classes but it was introducing yet another, not so useful, intermediate
 * type.
 *)
and stmt_and_def = stmt

(* the qualified_ident can have a leading '\' *)
and namespace_use_rule =
 | ImportNamespace of qualified_ident
 | AliasNamespace of qualified_ident * tok (* as *) * ident

(* ------------------------------------------------------------------------- *)
(* phpext: *)
(* ------------------------------------------------------------------------- *)
(* HPHP extension similar to http://en.wikipedia.org/wiki/Java_annotation *)
and attribute =
  | Attribute of string wrap
  | AttributeWithArgs of string wrap * static_scalar comma_list paren

and attributes = attribute comma_list angle

(* ------------------------------------------------------------------------- *)
(* The toplevels elements *)
(* ------------------------------------------------------------------------- *)
(* For parsing reasons and estet I think it's better to differentiate
 * nested functions and toplevel functions. 
 * update: sure? ast_php_simple simplify things.
 * Also it's better to group the toplevel statements together (StmtList below),
 * so that in the database later they share the same id.
 *
 * Note that nested functions are usually under a if(defined(...)) at
 * the toplevel. There is no ifdef in PHP so they reuse if.
 *)
and toplevel =
    | StmtList of stmt list
    | FuncDef of func_def
    | ClassDef of class_def
    (* PHP 5.3, see http://us.php.net/const *)
    | ConstantDef of constant_def
    (* facebook extension *)
    | TypeDef of type_def
    (* PHP 5.3, see http://www.php.net/manual/en/language.namespaces.rules.php*)
    (* the qualified_ident below can not have a leading '\' *)
    | NamespaceDef of tok * qualified_ident * tok (* ; *)
    | NamespaceBracketDef of tok * qualified_ident option * toplevel list brace
    | NamespaceUse of tok * namespace_use_rule comma_list * tok (* ; *)
    (* old:  | Halt of tok * unit paren * tok (* __halt__ ; *) *)
    | NotParsedCorrectly of tok list (* when Flag.error_recovery = true *)
    | FinalDef of tok (* EOF *)
 and program = toplevel list
  (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* Entity and any *)
(* ------------------------------------------------------------------------- *)
(* The goal of the entity type is to lift up important entities which
 * are originally nested in the AST such as methods.
 *
 * history: was in ast_entity_php.ml before but better to put everything
 * in one file.
 *)
type entity =
  | FunctionE of func_def
  | ClassE of class_def
  | ConstantE of constant_def
  | TypedefE of type_def

  | StmtListE of stmt list

  | MethodE of method_def

  | ClassConstantE of class_constant
  | ClassVariableE of class_variable * modifier list
  | XhpAttrE of xhp_attribute_decl

  | MiscE of tok list
type any =
  | Expr of expr
  | Stmt2 of stmt
  | StmtAndDefs of stmt_and_def list
  | Toplevel of toplevel
  | Program of program
  | Entity of entity

  | Argument of argument
  | Arguments of argument comma_list
  | Parameter of parameter
  | Parameters of parameter comma_list_dots paren
  | Body of stmt_and_def list brace

  | ClassStmt of class_stmt
  | ClassConstant2 of class_constant
  | ClassVariable of class_variable
  | ListAssign of list_assign
  | ColonStmt2 of colon_stmt
  | Case2 of case

  | XhpAttribute of xhp_attribute
  | XhpAttrValue of xhp_attr_value
  | XhpHtml2 of xhp_html
  | XhpChildrenDecl2 of xhp_children_decl

  | Info of tok
  | InfoList of tok list

  | Ident2 of ident
  | Hint2 of hint_type

 (* with tarzan *)

(*****************************************************************************)
(* Some constructors *)
(*****************************************************************************)
let noScope () = ref (Scope_code.NoScope)

let fakeInfo ?(next_to=None) str = { Parse_info.
  token = Parse_info.FakeTokStr (str, next_to);
  transfo = Parse_info.NoTransfo;
  }
(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)

let unwrap = fst

let unparen (a,b,c) = b
let unbrace = unparen
let unbracket = unparen

let uncomma xs = Common.map_filter (function
  | Left e -> Some e
  | Right info -> None
  ) xs

let uncomma_dots xs = Common.map_filter (function
  | Left3 e -> Some e
  | Right3 info | Middle3 info -> None
  ) xs

let map_paren f (lp, x, rp) = (lp, f x, rp)
let map_comma_list f xs = List.map (fun x ->
  match x with
  | Left e -> Left (f e)
  | Right tok -> Right tok
  )
  xs

let unarg arg =
  match arg with
  | Arg e -> e
  | ArgRef _ -> failwith "Found a ArgRef"

let unargs xs =
  uncomma xs +> Common.partition_either (function
  | Arg e -> Left e
  | ArgRef (t, e) -> Right (e)
  )

let unmodifiers class_vars =
  match class_vars with
  | NoModifiers _ -> []
  | VModifiers xs -> List.map unwrap xs

(*****************************************************************************)
(* Abstract line *)
(*****************************************************************************)

(* When we have extended the AST to add some info about the tokens,
 * such as its line number in the file, we can not use anymore the
 * ocaml '=' to compare Ast elements. To overcome this problem, to be
 * able to use again '=', we just have to get rid of all those extra
 * information, to "abstract those line" (al) information.
 *)

let al_info x =
  { x with Parse_info.token = Parse_info.Ab }

(*****************************************************************************)
(* Views *)
(*****************************************************************************)
(* examples:
 * inline more static funcall in expr type or variable type
 *)

(*****************************************************************************)
(* Helpers, could also be put in lib_parsing.ml instead *)
(*****************************************************************************)
let str_of_ident e =
  match e with
  | Name x -> unwrap x
  | XhpName (xs, _tok) ->
      ":" ^ (Common.join ":" xs)
let info_of_ident e =
  match e with
  | (Name (x,y)) -> y
  | (XhpName (x,y)) -> y

let str_of_dname (DName x) = unwrap x
let info_of_dname (DName (x,y)) = y

let info_of_qualified_ident = function
  | [] -> raise Impossible
  | (QI x)::xs -> info_of_ident x
  | (QITok tok)::xs -> tok

exception TodoNamespace of tok

let info_of_name x =
  match x with
  | XName [QI x] -> info_of_ident x
  | Self tok | Parent tok | LateStatic tok -> tok
  | XName qu -> raise (TodoNamespace (info_of_qualified_ident qu))

let str_of_name x =
  match x with
  | XName [QI x] -> str_of_ident x
  | Self tok | Parent tok | LateStatic tok -> Parse_info.str_of_info tok
  | XName qu -> raise (TodoNamespace (info_of_qualified_ident qu))



let str_of_class_name x =
  match x with
  | Hint (name, _targs) -> str_of_name name
  | _ -> raise Impossible

let name_of_class_name x =
  match x with
  | Hint (name, _targs) -> name
  | _ -> raise Impossible

let ident_of_class_name x =
  match x with
  | Hint (XName [QI name], _targs) -> name
  | _ -> raise Impossible
