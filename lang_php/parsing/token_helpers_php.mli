(*s: token_helpers_php.mli *)
val is_eof          : Parser_php.token -> bool
val is_comment      : Parser_php.token -> bool
val is_just_comment : Parser_php.token -> bool
(*x: token_helpers_php.mli *)
val info_of_tok : 
  Parser_php.token -> Ast_php.info
val visitor_info_of_tok : 
  (Ast_php.info -> Ast_php.info) -> Parser_php.token -> Parser_php.token
(*x: token_helpers_php.mli *)
val line_of_tok  : Parser_php.token -> int
val str_of_tok   : Parser_php.token -> string
val file_of_tok  : Parser_php.token -> Common.filename
val pos_of_tok   : Parser_php.token -> int
(*x: token_helpers_php.mli *)

(* for unparsing *)
val elt_of_tok: Parser_php.token -> Lib_unparser.elt

(*e: token_helpers_php.mli *)
