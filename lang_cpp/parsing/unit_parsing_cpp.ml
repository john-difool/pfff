open Common
open OUnit

open Ast_cpp
module Ast = Ast_cpp
module Flag = Flag_parsing_cpp

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let parse file = 
  Common.save_excursion Flag.error_recovery false (fun () ->
  Common.save_excursion Flag.show_parsing_error false (fun () ->
  Common.save_excursion Flag.verbose_parsing false (fun () ->
    Parse_cpp.parse file
  )))
(*****************************************************************************)
(* Unit tests *)
(*****************************************************************************)

let unittest =
 "parsing_cpp" >::: [

   (*-----------------------------------------------------------------------*)
   (* Lexing *)
   (*-----------------------------------------------------------------------*)
   (* todo: 
    * - make sure parse int correctly, and float, and that actually does
    *   not return multiple tokens for 42.42
    * - ...
    *)

   (*-----------------------------------------------------------------------*)
   (* Parsing *)
   (*-----------------------------------------------------------------------*)
   "regression files" >:: (fun () ->
     let dir = Filename.concat Config_pfff.path "/tests/cpp/parsing" in
     let files = 
       Common2.glob (spf "%s/*.cpp" dir) ++ Common2.glob (spf "%s/*.h" dir) in
     files +> List.iter (fun file ->
       try
         let _ast = parse file in
         ()
       with Parse_cpp.Parse_error _ ->
         assert_failure (spf "it should correctly parse %s" file)
     )
   );
   
   "rejecting bad code" >:: (fun () ->
     let dir = Filename.concat Config_pfff.path "/tests/cpp/parsing_errors" in
     let files = 
       Common2.glob (spf "%s/*.cpp" dir) in
     files +> List.iter (fun file ->
       try 
         let _ast = parse file in
         assert_failure (spf "it should have thrown a Parse_error %s" file)
       with
       | Parse_cpp.Parse_error _ -> ()
       | exn -> assert_failure (spf "throwing wrong exn %s on %s"
                                   (Common.exn_to_s exn) file)
     )
   );
   
 (* todo: parsing C files (and not C++ files) containing C++ keywords 
 *)

 (*-----------------------------------------------------------------------*)
 (* Misc *)
 (*-----------------------------------------------------------------------*)
 ]
