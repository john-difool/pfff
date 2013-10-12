(*s: show_function_calls1.ml *)
(*s: basic pfff modules open *)
open Common
open Ast_php
(*e: basic pfff modules open *)

(*s: show_function_calls v1 *)
let show_function_calls file = 
  let ast = Parse_php.parse_program file in

  (*s: iter on asts manually *)
    ast +> List.iter (fun toplevel ->
      match toplevel with
      | StmtList stmts ->
          (*s: iter on stmts *)
          stmts +> List.iter (fun stmt ->
            (match stmt with
            | ExprStmt (e, _ptvirg) ->
      
                (match e with
                | Call(Id (funcname), args) ->
                  (*s: print funcname *)
                  let s = Ast_php.str_of_name funcname in
                  let info = Ast_php.info_of_name funcname in
                  let line = Parse_info.line_of_info info in
                  pr2 (spf "Call to %s at line %d" s line);
                    (*e: print funcname *)
                | _ -> ()
                )
            | _ -> ()
            )
          )
        (*e: iter on stmts *)

      | (ConstantDef _|FuncDef _|ClassDef _ |TypeDef _
        |NotParsedCorrectly _| FinalDef _
        )
        -> ()
    )
  (*e: iter on asts manually *)
(*e: show_function_calls v1 *)

let main = 
  show_function_calls Sys.argv.(1)
(*e: show_function_calls1.ml *)
