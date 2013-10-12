open Common

open Ast_php
module Ast = Ast_php
module Flag = Flag_parsing_php
module V = Visitor_php

(*****************************************************************************)
(* Purpose *)
(*****************************************************************************)
(* 
 * To automatically extract all function names from a PHP file. It's useful
 * to show a simple example of a program using the pfff library. It's also
 * useful for my LogicFileSystem to make it possible to do in a shell:
 * 
 *   $ cd function:debug_rlog/ 
 * 
 * and get to the place where this function is defined.
 *)

(*****************************************************************************)
(* Flags *)
(*****************************************************************************)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(*****************************************************************************)
(* Main action *)
(*****************************************************************************)

let visit asts = 
  let props = ref [] in 

  let visitor = V.mk_visitor { V.default_visitor with
    V.ktop = (fun (k, bigf) top -> 
      match top with
      | FuncDef (def) -> 
          let name = Ast.str_of_ident def.f_name in
          Common.push2 ("function:" ^name) props;
      | _ -> 
          ()
    );
  } in
  visitor (Program asts);
  List.rev !props




let transduce  file = 
  Flag.verbose_lexing := false;
  Flag.verbose_parsing := false;
  Flag.show_parsing_error := false;

  let ast = Parse_php.parse_program file in
  let props = visit ast in
  pr (Common.join "/" props);
  ()

(*****************************************************************************)
(* The options *)
(*****************************************************************************)

let options () = 
  [
  (* this can not be factorized in Common *)
  "-version",   Arg.Unit (fun () -> 
    pr2 "version: $Date: 2010/06/08 12:32:06 $";
    raise (Common.UnixExit 0)
  ), 
  "   guess what";
  ]

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)


let main () = 
  let usage_msg = 
    "Usage: " ^ Filename.basename Sys.argv.(0) ^ 
      " [options] <file> " ^ "\n" ^ "Options are:"
  in
  (* does side effect on many global flags *)
  let args = Common.parse_options (options()) usage_msg Sys.argv in

  (* must be done after Arg.parse, because Common.profile is set by it *)
  Common.profile_code "Main total" (fun () -> 

    (match args with
    
    (* --------------------------------------------------------- *)
    (* main entry *)
    (* --------------------------------------------------------- *)
    | [x] -> 
        transduce x

    (* --------------------------------------------------------- *)
    (* empty entry *)
    (* --------------------------------------------------------- *)
    | _  -> 
        Common.usage usage_msg (options()); 
        failwith "too few arguments"
          
    )
  )

(*****************************************************************************)
let _ =
  Common.main_boilerplate (fun () -> 
    main ();
  )
