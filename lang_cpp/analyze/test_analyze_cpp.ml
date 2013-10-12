open Common

module Ast = Ast_cpp


module V = Visitor_cpp

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(*****************************************************************************)
(* Subsystem testing, no db *)
(*****************************************************************************)

let test_highlight_cpp file =

  let (ast2, _stat) = Parse_cpp.parse file in

  let h = Hashtbl.create 101 in

  ast2 +> List.iter (fun (ast, toks) ->
    (* computing the token attributes *)
    let prefs = Highlight_code.default_highlighter_preferences in

    Highlight_cpp.visit_toplevel 
      ~tag_hook:(fun info categ -> Hashtbl.add h info categ)
      prefs
      (ast, toks)
    ;

        (* getting the text *)
        let _ = toks +> Common.map_filter (fun tok -> 
          let info = Token_helpers_cpp.info_of_tok tok in
          let s = Token_helpers_cpp.str_of_tok tok in

          if not (Ast_cpp.is_origintok info)
          then None
          else 
            let categ = Common2.hfind_option info h in
            let categ = categ +> Common2.fmap (fun categ ->
              (*
                rewrite_categ_using_entities s categ file hentities
              *)
              categ
              )
            in
            Some (s, categ,
                 { Common2.l = Ast_cpp.line_of_info info;
                   c = Ast_cpp.col_of_info info;
                 })
        )
        in
        ()

  );
  ()

(*****************************************************************************)
(* Main entry for Arg *)
(*****************************************************************************)

let actions () = [
    "-test_highlight_cpp",  " <file>",
    Common.mk_action_1_arg test_highlight_cpp;
]
