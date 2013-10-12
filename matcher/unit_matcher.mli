
(* Returns the testsuite for matcher/. To be concatenated by 
 * the caller (e.g. in pfff/main_test.ml ) with other testsuites and 
 * run via OUnit.run_test_tt 
 *)
(*
val unittest: OUnit.test
*)

(* There is a circular dependency right now as lang_cpp/ depends on
 * matcher/ and matcher unit tests needs a fuzzy parser and so
 * needs lang_cpp/. At some point we could have a toy fuzzy parser
 * that simply use GenLex. For now we break the circular dependency
 * by passing arounds the necessary functions in main_sgrep.ml and
 * main_spatch.ml.
 *)

(* subsystems unittest *)
val sgrep_unittest: 
  ast_fuzzy_of_string:(string -> Ast_fuzzy.trees) -> 
  OUnit.test list

val spatch_unittest: 
  ast_fuzzy_of_string:(string -> Spatch_fuzzy.pattern) ->
  parse_file:(string -> Ast_fuzzy.trees * 'tok list) ->
  elt_and_info_of_tok:('tok -> Lib_unparser.elt * Parse_info.info) ->
  OUnit.test list
