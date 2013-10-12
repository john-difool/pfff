
val is_space               : Parser_cpp.token -> bool
val is_comment_or_space    : Parser_cpp.token -> bool
val is_just_comment        : Parser_cpp.token -> bool
val is_comment             : Parser_cpp.token -> bool
val is_real_comment        : Parser_cpp.token -> bool
val is_fake_comment        : Parser_cpp.token -> bool
val is_not_comment         : Parser_cpp.token -> bool

val is_pp_instruction     : Parser_cpp.token -> bool
val is_eof                 : Parser_cpp.token -> bool
val is_statement           : Parser_cpp.token -> bool
val is_start_of_something  : Parser_cpp.token -> bool
val is_binary_operator     : Parser_cpp.token -> bool
val is_stuff_taking_parenthized : Parser_cpp.token -> bool
val is_static_cast_like    : Parser_cpp.token -> bool
val is_basic_type          : Parser_cpp.token -> bool
val is_binary_operator_except_star     : Parser_cpp.token -> bool
val is_struct_like_keyword : Parser_cpp.token -> bool
val is_classkey_keyword : Parser_cpp.token -> bool

val is_cpp_keyword : Parser_cpp.token -> bool
val is_objectivec_keyword: Parser_cpp.token -> bool
val is_really_cpp_keyword : Parser_cpp.token -> bool
val is_maybenot_cpp_keyword : Parser_cpp.token -> bool
val is_privacy_keyword: Parser_cpp.token -> bool

val is_opar : Parser_cpp.token -> bool
val is_cpar : Parser_cpp.token -> bool
val is_obrace : Parser_cpp.token -> bool
val is_cbrace : Parser_cpp.token -> bool

val is_ident_like: Parser_cpp.token -> bool

val info_of_tok : 
  Parser_cpp.token -> Ast_cpp.info
val visitor_info_of_tok : 
  (Ast_cpp.info -> Ast_cpp.info) -> Parser_cpp.token -> Parser_cpp.token

val linecol_of_tok : Parser_cpp.token -> int * int
val col_of_tok     : Parser_cpp.token -> int
val line_of_tok    : Parser_cpp.token -> int
val str_of_tok     : Parser_cpp.token -> string
val pos_of_tok     : Parser_cpp.token -> int
val file_of_tok    : Parser_cpp.token -> Common.filename

(* for unparsing *)
val elt_of_tok: Parser_cpp.token -> Lib_unparser.elt
