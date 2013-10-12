
open Ast_cpp

(* the hooks *)
type visitor_in = {
  kexpr: expression vin;
  kstmt: statement vin;

  kclass_member: class_member vin;
  kfieldkind: fieldkind vin;

  ktypeC: typeC vin;
  kparameter: parameter vin;
  kcompound: compound vin;

  kclass_def: class_definition vin;
  kfunc_def: func_definition vin;
  kcpp: cpp_directive vin;
  kblock_decl: block_declaration vin;
  ktoplevel: toplevel vin;
  
  kinfo: info vin;
}
and visitor_out = any -> unit
and 'a vin = ('a  -> unit) * visitor_out -> 'a  -> unit

val default_visitor : visitor_in

val mk_visitor: visitor_in -> visitor_out
