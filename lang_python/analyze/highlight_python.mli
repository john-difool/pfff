

val visit_toplevel :
  tag_hook:
    (Ast_python.info -> Highlight_code.category -> unit) ->
  Highlight_code.highlighter_preferences ->
  (*(Database_php.id * Common.filename * Database_php.database) option -> *)
  Ast_python.toplevel * Parser_python.token list ->
  unit
