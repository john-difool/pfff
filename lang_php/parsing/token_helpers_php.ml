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

open Parser_php
module PI = Parse_info

(*****************************************************************************)
(* Token Helpers *)
(*****************************************************************************)

let is_eof = function
  | EOF _ -> true
  | _ -> false

let is_comment = function
  | T_COMMENT _ | T_DOC_COMMENT _
  | TSpaces _ | TNewline _ -> true
  | TCommentPP _ -> true
  | _ -> false

let is_just_comment = function
  | T_COMMENT _ -> true
  | _ -> false


(*****************************************************************************)
(* Visitors *)
(*****************************************************************************)

(* Ugly repetitive code but ocamlyacc force us to do it that way.
 * Indeed the ocamlyacc token  cant be a pair of a sum type, it must be
 * directly a sum type. Fortunately most of the code was generated via an
 * emacs macro working on the type definition of token in parser_php.mli
 *)

let info_of_tok = function
  | TUnknown ii -> ii
  | TSpaces ii -> ii
  | TNewline ii -> ii
  | TCommentPP ii -> ii
  | T_LNUMBER (s, ii) -> ii
  | T_DNUMBER (s, ii) -> ii
  | T_IDENT (s, ii) -> ii
  | T_STRING_VARNAME (s, ii) -> ii
  | T_VARIABLE (s, ii) -> ii
  | T_NUM_STRING (s, ii) -> ii
  | T_INLINE_HTML (s, ii) -> ii
  | T_ENCAPSED_AND_WHITESPACE (s, ii) -> ii
  | T_CONSTANT_ENCAPSED_STRING (s, ii) -> ii
  | T_ECHO ii -> ii
  | T_PRINT ii -> ii
  | T_DO ii -> ii
  | T_WHILE ii -> ii
  | T_ENDWHILE ii -> ii
  | T_FOR ii -> ii
  | T_ENDFOR ii -> ii
  | T_FOREACH ii -> ii
  | T_ENDFOREACH ii -> ii
  | T_SWITCH ii -> ii
  | T_ENDSWITCH ii -> ii
  | T_CASE ii -> ii
  | T_DEFAULT ii -> ii
  | T_BREAK ii -> ii
  | T_CONTINUE ii -> ii
  | T_RETURN ii -> ii
  | T_TRY ii -> ii
  | T_CATCH ii -> ii
  | T_THROW ii -> ii
  | T_DECLARE ii -> ii
  | T_ENDDECLARE ii -> ii
  | T_USE ii -> ii
  | T_GLOBAL ii -> ii
  | T_AS ii -> ii
  | T_FUNCTION ii -> ii
  | T_CONST ii -> ii
  | T_STATIC ii -> ii
  | T_ABSTRACT ii -> ii
  | T_FINAL ii -> ii
  | T_ASYNC ii -> ii
  | T_PRIVATE ii -> ii
  | T_PROTECTED ii -> ii
  | T_PUBLIC ii -> ii
  | T_VAR ii -> ii
  | T_UNSET ii -> ii
  | T_ISSET ii -> ii
  | T_EMPTY ii -> ii
  | T_CLASS ii -> ii
  | T_INTERFACE ii -> ii
  | T_EXTENDS ii -> ii
  | T_IMPLEMENTS ii -> ii
  | T_OBJECT_OPERATOR ii -> ii
  | T_DOUBLE_ARROW ii -> ii
  | T_LIST ii -> ii
  | T_ARRAY ii -> ii
  | T_CLASS_C ii -> ii
  | T_METHOD_C ii -> ii
  | T_FUNC_C ii -> ii
  | T_LINE ii -> ii
  | T_FILE ii -> ii
  | T_DIR ii -> ii
  | T_COMMENT ii -> ii
  | T_DOC_COMMENT ii -> ii
  | T_OPEN_TAG ii -> ii
  | T_OPEN_TAG_WITH_ECHO ii -> ii
  | T_CLOSE_TAG_OF_ECHO ii -> ii
  | T_CLOSE_TAG ii -> ii
  | T_START_HEREDOC ii -> ii
  | T_END_HEREDOC ii -> ii
  | T_DOLLAR_OPEN_CURLY_BRACES ii -> ii
  | T_CURLY_OPEN ii -> ii
  | TCOLCOL ii -> ii
  | T_EXIT ii -> ii
  | T_IF ii -> ii
  | TCOLON ii -> ii
  | TCOMMA ii -> ii
  | TDOT ii -> ii
  | TBANG ii -> ii
  | TTILDE ii -> ii
  | TQUESTION ii -> ii
  | TOBRA ii -> ii
  | TPLUS ii -> ii
  | TMINUS ii -> ii
  | TMUL ii -> ii
  | TDIV ii -> ii
  | TMOD ii -> ii
  | TAND ii -> ii
  | TOR ii -> ii
  | TEQ ii -> ii
  | TSMALLER ii -> ii
  | TGREATER ii -> ii
  | T_PLUS_EQUAL ii -> ii
  | T_MINUS_EQUAL ii -> ii
  | T_MUL_EQUAL ii -> ii
  | T_DIV_EQUAL ii -> ii
  | T_CONCAT_EQUAL ii -> ii
  | T_MOD_EQUAL ii -> ii
  | T_AND_EQUAL ii -> ii
  | T_OR_EQUAL ii -> ii
  | T_XOR_EQUAL ii -> ii
  | T_SL_EQUAL ii -> ii
  | T_SR_EQUAL ii -> ii
  | T_INC ii -> ii
  | T_DEC ii -> ii
  | T_BOOLEAN_OR ii -> ii
  | T_BOOLEAN_AND ii -> ii
  | T_LOGICAL_OR ii -> ii
  | T_LOGICAL_AND ii -> ii
  | T_LOGICAL_XOR ii -> ii
  | T_SL ii -> ii
  | T_SR ii -> ii
  | T_IS_SMALLER_OR_EQUAL ii -> ii
  | T_IS_GREATER_OR_EQUAL ii -> ii
  | T_BOOL_CAST ii -> ii
  | T_INT_CAST ii -> ii
  | T_DOUBLE_CAST ii -> ii
  | T_STRING_CAST ii -> ii
  | T_ARRAY_CAST ii -> ii
  | T_OBJECT_CAST ii -> ii
  | T_UNSET_CAST ii -> ii
  | T_IS_IDENTICAL ii -> ii
  | T_IS_NOT_IDENTICAL ii -> ii
  | T_IS_EQUAL ii -> ii
  | T_IS_NOT_EQUAL ii -> ii
  | TXOR ii -> ii
  | T__AT ii -> ii
  | T_NEW ii -> ii
  | T_CLONE ii -> ii
  | T_INSTANCEOF ii -> ii
  | T_INCLUDE ii -> ii
  | T_INCLUDE_ONCE ii -> ii
  | T_REQUIRE ii -> ii
  | T_REQUIRE_ONCE ii -> ii
  | T_EVAL ii -> ii
  | T_ELSE ii -> ii
  | T_ELSEIF ii -> ii
  | T_ENDIF ii -> ii
  | TOPAR ii -> ii
  | TCPAR ii -> ii
  | TOBRACE ii -> ii
  | TCBRACE ii -> ii
  | TCBRA ii -> ii
  | TBACKQUOTE ii -> ii
  | TSEMICOLON ii -> ii
  | TDOLLAR ii -> ii
  | TGUIL ii -> ii

  | TDOTS (ii) -> ii
  | T_CLASS_XDEBUG (ii) -> ii
  | T_RESOURCE_XDEBUG (ii) -> ii

  | T_XHP_COLONID_DEF (s, ii) -> ii
  | T_XHP_PERCENTID_DEF (s, ii) -> ii

  | T_XHP_OPEN_TAG (xs, ii) -> ii
  | T_XHP_CLOSE_TAG (xs, ii) -> ii

  | T_XHP_GT (ii) -> ii
  | T_XHP_SLASH_GT (ii) -> ii

  | T_XHP_ATTR (s, ii) -> ii
  | T_XHP_TEXT (s, ii) -> ii

  | T_XHP_ATTRIBUTE (ii) -> ii
  | T_XHP_CHILDREN (ii) -> ii
  | T_XHP_CATEGORY (ii) -> ii


  | T_XHP_ENUM (ii) -> ii
  | T_XHP_REQUIRED (ii) -> ii

  | T_XHP_ANY (ii) -> ii
  | T_XHP_PCDATA (ii) -> ii

  | T_YIELD (ii) -> ii
  | T_AWAIT (ii) -> ii
  | T_SELF(ii) -> ii
  | T_PARENT(ii) -> ii

  | T_TRAIT(ii) -> ii
  | T_INSTEADOF(ii) -> ii
  | T_TRAIT_C(ii) -> ii

  | T_TYPE(ii) -> ii
  | T_NEWTYPE(ii) -> ii
  | T_SHAPE(ii) -> ii

  | T_NAMESPACE(ii) -> ii
  | TANTISLASH(ii) -> ii
  | T_NAMESPACE_C(ii) -> ii

  | EOF ii -> ii


let visitor_info_of_tok f = function
  | TUnknown ii -> TUnknown(f ii)
  | TSpaces ii -> TSpaces(f ii)
  | TNewline ii -> TNewline(f ii)
  | TCommentPP ii -> TCommentPP(f ii)
  | T_LNUMBER (s,ii) -> T_LNUMBER(s, f ii)
  | T_DNUMBER (s,ii) -> T_DNUMBER(s, f ii)
  | T_IDENT (s, ii) -> T_IDENT(s, f ii)
  | T_STRING_VARNAME (s, ii) -> T_STRING_VARNAME(s, f ii)
  | T_VARIABLE (s, ii) -> T_VARIABLE(s, f ii)
  | T_NUM_STRING (s, ii) -> T_NUM_STRING(s, f ii)
  | T_INLINE_HTML (s, ii) -> T_INLINE_HTML(s, f ii)
  | T_ENCAPSED_AND_WHITESPACE (s, ii) -> T_ENCAPSED_AND_WHITESPACE(s, f ii)
  | T_CONSTANT_ENCAPSED_STRING (s,ii) -> T_CONSTANT_ENCAPSED_STRING(s, f ii)
  | T_ECHO ii -> T_ECHO(f ii)
  | T_PRINT ii -> T_PRINT(f ii)
  | T_DO ii -> T_DO(f ii)
  | T_WHILE ii -> T_WHILE(f ii)
  | T_ENDWHILE ii -> T_ENDWHILE(f ii)
  | T_FOR ii -> T_FOR(f ii)
  | T_ENDFOR ii -> T_ENDFOR(f ii)
  | T_FOREACH ii -> T_FOREACH(f ii)
  | T_ENDFOREACH ii -> T_ENDFOREACH(f ii)
  | T_SWITCH ii -> T_SWITCH(f ii)
  | T_ENDSWITCH ii -> T_ENDSWITCH(f ii)
  | T_CASE ii -> T_CASE(f ii)
  | T_DEFAULT ii -> T_DEFAULT(f ii)
  | T_BREAK ii -> T_BREAK(f ii)
  | T_CONTINUE ii -> T_CONTINUE(f ii)
  | T_RETURN ii -> T_RETURN(f ii)
  | T_TRY ii -> T_TRY(f ii)
  | T_CATCH ii -> T_CATCH(f ii)
  | T_THROW ii -> T_THROW(f ii)
  | T_DECLARE ii -> T_DECLARE(f ii)
  | T_ENDDECLARE ii -> T_ENDDECLARE(f ii)
  | T_USE ii -> T_USE(f ii)
  | T_GLOBAL ii -> T_GLOBAL(f ii)
  | T_AS ii -> T_AS(f ii)
  | T_FUNCTION ii -> T_FUNCTION(f ii)
  | T_CONST ii -> T_CONST(f ii)
  | T_STATIC ii -> T_STATIC(f ii)
  | T_ABSTRACT ii -> T_ABSTRACT(f ii)
  | T_FINAL ii -> T_FINAL(f ii)
  | T_ASYNC ii -> T_ASYNC(f ii)
  | T_PRIVATE ii -> T_PRIVATE(f ii)
  | T_PROTECTED ii -> T_PROTECTED(f ii)
  | T_PUBLIC ii -> T_PUBLIC(f ii)
  | T_VAR ii -> T_VAR(f ii)
  | T_UNSET ii -> T_UNSET(f ii)
  | T_ISSET ii -> T_ISSET(f ii)
  | T_EMPTY ii -> T_EMPTY(f ii)
  | T_CLASS ii -> T_CLASS(f ii)
  | T_INTERFACE ii -> T_INTERFACE(f ii)
  | T_EXTENDS ii -> T_EXTENDS(f ii)
  | T_IMPLEMENTS ii -> T_IMPLEMENTS(f ii)
  | T_OBJECT_OPERATOR ii -> T_OBJECT_OPERATOR(f ii)
  | T_DOUBLE_ARROW ii -> T_DOUBLE_ARROW(f ii)
  | T_LIST ii -> T_LIST(f ii)
  | T_ARRAY ii -> T_ARRAY(f ii)
  | T_CLASS_C ii -> T_CLASS_C(f ii)
  | T_METHOD_C ii -> T_METHOD_C(f ii)
  | T_FUNC_C ii -> T_FUNC_C(f ii)
  | T_LINE ii -> T_LINE(f ii)
  | T_FILE ii -> T_FILE(f ii)
  | T_DIR ii -> T_DIR (f ii)
  | T_COMMENT ii -> T_COMMENT(f ii)
  | T_DOC_COMMENT ii -> T_DOC_COMMENT(f ii)
  | T_OPEN_TAG ii -> T_OPEN_TAG(f ii)
  | T_OPEN_TAG_WITH_ECHO ii -> T_OPEN_TAG_WITH_ECHO(f ii)
  | T_CLOSE_TAG_OF_ECHO ii -> T_CLOSE_TAG_OF_ECHO(f ii)
  | T_CLOSE_TAG ii -> T_CLOSE_TAG(f ii)
  | T_START_HEREDOC ii -> T_START_HEREDOC(f ii)
  | T_END_HEREDOC ii -> T_END_HEREDOC(f ii)
  | T_DOLLAR_OPEN_CURLY_BRACES ii -> T_DOLLAR_OPEN_CURLY_BRACES(f ii)
  | T_CURLY_OPEN ii -> T_CURLY_OPEN(f ii)
  | TCOLCOL ii -> TCOLCOL (f ii)
  | T_EXIT ii -> T_EXIT(f ii)
  | T_IF ii -> T_IF(f ii)
  | TCOLON ii -> TCOLON(f ii)
  | TCOMMA ii -> TCOMMA(f ii)
  | TDOT ii -> TDOT(f ii)
  | TBANG ii -> TBANG(f ii)
  | TTILDE ii -> TTILDE(f ii)
  | TQUESTION ii -> TQUESTION(f ii)
  | TOBRA ii -> TOBRA(f ii)
  | TPLUS ii -> TPLUS(f ii)
  | TMINUS ii -> TMINUS(f ii)
  | TMUL ii -> TMUL(f ii)
  | TDIV ii -> TDIV(f ii)
  | TMOD ii -> TMOD(f ii)
  | TAND ii -> TAND(f ii)
  | TOR ii -> TOR(f ii)
  | TEQ ii -> TEQ(f ii)
  | TSMALLER ii -> TSMALLER(f ii)
  | TGREATER ii -> TGREATER(f ii)
  | T_PLUS_EQUAL ii -> T_PLUS_EQUAL(f ii)
  | T_MINUS_EQUAL ii -> T_MINUS_EQUAL(f ii)
  | T_MUL_EQUAL ii -> T_MUL_EQUAL(f ii)
  | T_DIV_EQUAL ii -> T_DIV_EQUAL(f ii)
  | T_CONCAT_EQUAL ii -> T_CONCAT_EQUAL(f ii)
  | T_MOD_EQUAL ii -> T_MOD_EQUAL(f ii)
  | T_AND_EQUAL ii -> T_AND_EQUAL(f ii)
  | T_OR_EQUAL ii -> T_OR_EQUAL(f ii)
  | T_XOR_EQUAL ii -> T_XOR_EQUAL(f ii)
  | T_SL_EQUAL ii -> T_SL_EQUAL(f ii)
  | T_SR_EQUAL ii -> T_SR_EQUAL(f ii)
  | T_INC ii -> T_INC(f ii)
  | T_DEC ii -> T_DEC(f ii)
  | T_BOOLEAN_OR ii -> T_BOOLEAN_OR(f ii)
  | T_BOOLEAN_AND ii -> T_BOOLEAN_AND(f ii)
  | T_LOGICAL_OR ii -> T_LOGICAL_OR(f ii)
  | T_LOGICAL_AND ii -> T_LOGICAL_AND(f ii)
  | T_LOGICAL_XOR ii -> T_LOGICAL_XOR(f ii)
  | T_SL ii -> T_SL(f ii)
  | T_SR ii -> T_SR(f ii)
  | T_IS_SMALLER_OR_EQUAL ii -> T_IS_SMALLER_OR_EQUAL(f ii)
  | T_IS_GREATER_OR_EQUAL ii -> T_IS_GREATER_OR_EQUAL(f ii)
  | T_BOOL_CAST ii -> T_BOOL_CAST(f ii)
  | T_INT_CAST ii -> T_INT_CAST(f ii)
  | T_DOUBLE_CAST ii -> T_DOUBLE_CAST(f ii)
  | T_STRING_CAST ii -> T_STRING_CAST(f ii)
  | T_ARRAY_CAST ii -> T_ARRAY_CAST(f ii)
  | T_OBJECT_CAST ii -> T_OBJECT_CAST(f ii)
  | T_UNSET_CAST ii -> T_UNSET_CAST(f ii)
  | T_IS_IDENTICAL ii -> T_IS_IDENTICAL(f ii)
  | T_IS_NOT_IDENTICAL ii -> T_IS_NOT_IDENTICAL(f ii)
  | T_IS_EQUAL ii -> T_IS_EQUAL(f ii)
  | T_IS_NOT_EQUAL ii -> T_IS_NOT_EQUAL(f ii)
  | TXOR ii -> TXOR(f ii)
  | T__AT ii -> T__AT(f ii)
  | T_NEW ii -> T_NEW(f ii)
  | T_CLONE ii -> T_CLONE(f ii)
  | T_INSTANCEOF ii -> T_INSTANCEOF(f ii)
  | T_INCLUDE ii -> T_INCLUDE(f ii)
  | T_INCLUDE_ONCE ii -> T_INCLUDE_ONCE(f ii)
  | T_REQUIRE ii -> T_REQUIRE(f ii)
  | T_REQUIRE_ONCE ii -> T_REQUIRE_ONCE(f ii)
  | T_EVAL ii -> T_EVAL(f ii)
  | T_ELSE ii -> T_ELSE(f ii)
  | T_ELSEIF ii -> T_ELSEIF(f ii)
  | T_ENDIF ii -> T_ENDIF(f ii)
  | TOPAR ii -> TOPAR(f ii)
  | TCPAR ii -> TCPAR(f ii)
  | TOBRACE ii -> TOBRACE(f ii)
  | TCBRACE ii -> TCBRACE(f ii)
  | TCBRA ii -> TCBRA(f ii)
  | TBACKQUOTE ii -> TBACKQUOTE(f ii)
  | TSEMICOLON ii -> TSEMICOLON(f ii)
  | TDOLLAR ii -> TDOLLAR(f ii)
  | TGUIL ii -> TGUIL(f ii)

  | TDOTS (ii) -> TDOTS (f ii)
  | T_CLASS_XDEBUG (ii) -> T_CLASS_XDEBUG (f ii)
  | T_RESOURCE_XDEBUG (ii) -> T_RESOURCE_XDEBUG (f ii)

  | T_XHP_COLONID_DEF (s, ii) -> T_XHP_COLONID_DEF (s, f ii)
  | T_XHP_PERCENTID_DEF (s, ii) -> T_XHP_PERCENTID_DEF (s, f ii)

  | T_XHP_OPEN_TAG (xs, ii) -> T_XHP_OPEN_TAG (xs, f ii)
  | T_XHP_CLOSE_TAG (xs, ii) -> T_XHP_CLOSE_TAG (xs, f ii)

  | T_XHP_GT (ii) -> T_XHP_GT (f ii)
  | T_XHP_SLASH_GT (ii) -> T_XHP_SLASH_GT (f ii)

  | T_XHP_ATTR (s, ii) -> T_XHP_ATTR (s, f ii)
  | T_XHP_TEXT (s, ii) -> T_XHP_TEXT (s, f ii)

  | T_XHP_ATTRIBUTE (ii) -> T_XHP_ATTRIBUTE (f ii)
  | T_XHP_CHILDREN (ii) -> T_XHP_CHILDREN (f ii)
  | T_XHP_CATEGORY (ii) -> T_XHP_CATEGORY (f ii)

  | T_XHP_ENUM (ii) -> T_XHP_ENUM (f ii)
  | T_XHP_REQUIRED (ii) -> T_XHP_REQUIRED (f ii)

  | T_XHP_ANY (ii) -> T_XHP_ANY (f ii)
  | T_XHP_PCDATA (ii) -> T_XHP_PCDATA (f ii)

  | T_YIELD (ii) -> T_YIELD (f ii)
  | T_AWAIT (ii) -> T_AWAIT (f ii)
  | T_SELF (ii) -> T_SELF (f ii)
  | T_PARENT (ii) -> T_PARENT (f ii)

  | T_TRAIT(ii) -> T_TRAIT(f ii)
  | T_INSTEADOF(ii) -> T_INSTEADOF(f ii)
  | T_TRAIT_C(ii) -> T_TRAIT_C(f ii)

  | T_TYPE(ii) -> T_TYPE(f ii)
  | T_NEWTYPE(ii) -> T_TYPE(f ii)
  | T_SHAPE(ii) -> T_SHAPE(f ii)

  | T_NAMESPACE(ii) -> T_NAMESPACE(f ii)
  | TANTISLASH(ii) -> TANTISLASH(f ii)
  | T_NAMESPACE_C(ii) -> T_NAMESPACE_C(f ii)

  | EOF ii -> EOF(f ii)


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
let pos_of_tok  x = PI.pos_of_info  (info_of_tok x)

(*****************************************************************************)
(* For unparsing *)
(*****************************************************************************)

open Lib_unparser

let elt_of_tok tok =
  let str = str_of_tok tok in
  match tok with
  | T_COMMENT _ | T_DOC_COMMENT _ | TCommentPP _ -> Esthet (Comment str)
  | TSpaces _ -> Esthet (Space str)
  | TNewline _ -> Esthet Newline
  | _ -> OrigElt str
