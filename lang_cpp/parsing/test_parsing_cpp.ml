open Common

open Ast_cpp
module Ast = Ast_cpp
module Flag = Flag_parsing_cpp
module TH = Token_helpers_cpp

module Stat = Statistics_parsing

(*****************************************************************************)
(* Subsystem testing *)
(*****************************************************************************)

let test_tokens_cpp file = 
  Flag.verbose_lexing := true;
  Flag.verbose_parsing := true;
  let toks = Parse_cpp.tokens file in
  toks +> List.iter (fun x -> pr2_gen x);
  ()

let test_parse_cpp ?lang xs  =
  let fullxs = Lib_parsing_cpp.find_source_files_of_dir_or_files xs in
  let fullxs =
    match xs with
    | [dir] when Common2.is_directory dir ->
      let file = Filename.concat dir "skip_list.txt" in
      if Sys.file_exists file
      then 
        let skip_list = Skip_code.load file in
        Skip_code.filter_files skip_list dir fullxs
      else fullxs
    | _ -> fullxs
  in

  Parse_cpp.init_defs !Flag.macros_h;

  let stat_list = ref [] in
  let newscore  = Common2.empty_score () in

  fullxs +> List.iter (fun file -> 
    pr2 ("PARSING: " ^ file);
    
    let (xs, stat) = Parse_cpp.parse ?lang file in

    Common.push2 stat stat_list;

    let s = spf "bad = %d" stat.Stat.bad in
    if stat.Stat.bad = 0
    then Hashtbl.add newscore file (Common2.Ok)
    else Hashtbl.add newscore file (Common2.Pb s)
  );

  Stat.print_recurring_problematic_tokens !stat_list;
  (match xs with 
  | [dirname] when Common2.is_directory dirname ->
      pr2 "--------------------------------";
      pr2 "regression testing  information";
      pr2 "--------------------------------";
      let score_path = Filename.concat !Flag.path "tmp" in
      let str = Str.global_replace (Str.regexp "/") "__" dirname in
      Common2.regression_testing newscore 
        (Filename.concat score_path
            ("score_parsing__" ^str ^ "cpp" ^ ".marshalled"));


      let layer_file = "/tmp/layer_parse_errors_red_green.json" in
      pr2 (spf "generating parse error layer in %s" layer_file);
      Layer_parse_errors.gen_red_green_layer ~root:dirname ~output:layer_file
        !stat_list;

      let layer_file = "/tmp/layer_parse_errors_heatmap.json" in
      pr2 (spf "generating parse error layer in %s" layer_file);
      Layer_parse_errors.gen_heatmap_layer ~root:dirname ~output:layer_file
        !stat_list;
  | _ -> ()
  );
  Stat.print_parsing_stat_list !stat_list;
  ()

let test_dump_cpp file =
  Parse_cpp.init_defs !Flag.macros_h;
  let ast = Parse_cpp.parse_program file in
  let v = Meta_ast_cpp.vof_program ast in
  let s = Ocaml.string_of_v v in
  pr s

let test_dump_cpp_full file =
  Parse_cpp.init_defs !Flag.macros_h;
  let ast = Parse_cpp.parse_program file in
  let toks = Parse_cpp.tokens file in
  let precision = { Meta_ast_generic.
     full_info = true; type_info = false; token_info = true;
  }
  in
  let v = Meta_ast_cpp.vof_program ~precision ast in
  let s = Ocaml.string_of_v v in
  pr s;
  toks +> List.iter (fun tok ->
    match tok with
    | Parser_cpp.TComment (ii) ->
        let v = Parse_info.vof_info ii in
        let s = Ocaml.string_of_v v in
        pr s
    | _ -> ()
  );
  ()

let test_dump_cpp_fuzzy file =
  let fuzzy, _toks = Parse_cpp.parse_fuzzy file in
  let v = Ast_fuzzy.vof_trees fuzzy in
  let s = Ocaml.string_of_v v in
  pr2 s

let test_parse_cpp_fuzzy dir_or_file =
  let fullxs = Lib_parsing_cpp.find_source_files_of_dir_or_files [dir_or_file]in

  let file = Filename.concat dir_or_file "skip_list.txt" in
  let fullxs = 
    if Sys.file_exists file
    then 
      let skip_list = Skip_code.load file in
      Skip_code.filter_files skip_list dir_or_file fullxs
    else fullxs
  in

  fullxs +> Common_extra.progress (fun k -> List.iter (fun file -> 
     k ();
    Common.save_excursion Flag_parsing_cpp.strict_lexer true (fun () ->
      try 
        let _fuzzy = Parse_cpp.parse_fuzzy file in
        ()
      with exn ->
        pr2 (spf "PB with: %s, exn = %s" file (Common.exn_to_s exn)); 
    )
  ));
  ()
  

(*****************************************************************************)
(* Unit tests *)
(*****************************************************************************)

(*****************************************************************************)
(* Main entry for Arg *)
(*****************************************************************************)

let actions () = [
    "-parse_cpp", "   <file or dir>", 
    Common.mk_action_n_arg test_parse_cpp;
    "-tokens_cpp", "   <file>", 
    Common.mk_action_1_arg test_tokens_cpp;
    "-dump_cpp", "   <file>", 
    Common.mk_action_1_arg test_dump_cpp;
    "-dump_cpp_ml", "   <file>", 
    Common.mk_action_1_arg test_dump_cpp;
    "-dump_cpp_full", "   <file>", 
    Common.mk_action_1_arg test_dump_cpp_full;

    "-parse_cpp_fuzzy", "   <file or dir>", 
    Common.mk_action_1_arg test_parse_cpp_fuzzy;
    "-dump_cpp_fuzzy", "   <file>", 
    Common.mk_action_1_arg test_dump_cpp_fuzzy;

]
