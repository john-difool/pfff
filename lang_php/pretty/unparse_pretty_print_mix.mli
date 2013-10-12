
(* Will overwrite newfile with a better pretty printing when needs it.
 * This function takes the content of the oldfile to detect which parts in
 * the newfile have changed, which are parts for instance modified by spatch
 * that we want to pretty print. When nothing has changed we can just
 * print the code in its original style.
 *)
val pretty_print_when_need_it:
  oldfile:Common.filename -> newfile:Common.filename ->
  unit

(* internals *)

(* A union of Ast.toplevel and Ast.class_stmt *)
type chunk =
  (* toplevel *)
  | Stmts of Ast_php.stmt list
  | Func of Ast_php.func_def
  | ClassHeader of Ast_php.class_def
  | ClassFooter of Ast_php.info
  | FinalDef of Ast_php.info
  (* class_stmt *)
  | ClassStmt of Ast_php.class_stmt

type chunks = (chunk * Parser_php.token list) list

val split_chunks:
  Parser_php.token list -> Ast_php.program -> chunks

(* julien's pretty printer *)
val pretty_print: 
  Buffer.t -> Pretty_print_code.env -> (chunk * Parser_php.token list) -> unit

(* pad's dumb unparser *)
val unparse:
  Buffer.t -> (chunk * Parser_php.token list) -> unit
