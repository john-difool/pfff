(* Yoann Padioleau
 *
 * Copyright (C) 2012, 2013 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
open Common

module E = Database_code
module G = Graph_code
module H = Graph_code_cmt_helpers

open Cmt_format
open Typedtree

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
 * Graph of dependencies for OCaml typed AST files (.cmt). See graph_code.ml
 * and main_codegraph.ml for more information.
 * 
 * See also notes_cmt.txt.
 * 
 * schema:
 *  Root -> Dir -> Module -> Function
 *                        -> Type -> Constructor
 *                                -> Field
 *                        -> Exception (with .exn as prefix)
 *                        -> Constant
 *                        -> Global
 *                        -> SubModule -> ...
 * 
 * note that ocaml allows to have multiple entities with the same name
 * inside the same module, so we have to merge them; see the 'dupe_ok'
 * parameter below.
 * 
 * related:
 *  - typerex
 *  - ocamlspotter
 *  - oug/odb http://odb-serv.forge.ocamlcore.org/
 *  - merlin
 *  - whole program analysis done by ocamlpro recently?
 * 
 * todo: nested let module X = Y in, ocaml 4.00 feature
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

type env = {
  g: Graph_code.graph;

  phase: phase;
  (* the .cmt, used mostly for error reporting, in readable path format *)
  file: Common.filename;
  (* the file the .cmt is supposed to come from, in readable path format *)
  source_file: Common.filename;
  
  current: Graph_code.node;
  current_entity: name;

  mutable locals: string list;

  (* see notes_cmt.txt, the cmt files do not contain the full path
   * for locally referenced functions, types, or modules, so we have to resolve
   * them. Each time you add an Ident.t, add it there, and each
   * time you use a Path.t, use path_resolve_locals().
   * We use 3 different fields because those are different namespaces; we
   * don't want a value to shadow a type.
   *)
  full_path_local_type: (string * name) list ref;
  full_path_local_value: (string * name) list ref;
  (* this is less necessary as by convention module use uppercase and
   * value/types only lowercase and so there is no shadowing risk.
   *)
  full_path_local_module: (string * name) list ref;

  (* global to the whole project, populated in Defs and used in Uses,
   * see path_resolve_aliases().
   *)
  module_aliases: (name * name) list ref;
  type_aliases: (name * name) list ref;
}
 (* todo: what about names which are applications of functor? 
  * See Longident.t
  *)
 and name = string list
 and phase = Defs | Uses

let s_of_n xs = Common.join "." xs

(*****************************************************************************)
(* Parsing *)
(*****************************************************************************)
let _hmemo = Hashtbl.create 101
let parse file =
  Common.memoized _hmemo file (fun () ->
    try 
      Cmt_format.read_cmt file
    with
      (Cmi_format.Error _) as exn ->
        failwith (spf "PB with %s, exn = %s" file (Common.exn_to_s exn))
  )

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let unwrap x = 
  x.Asttypes.loc

let (name_of_longident_loc: Longident.t Asttypes.loc -> name) = fun lidloc ->
  let lid = lidloc.Asttypes.txt in
  Longident.flatten lid

let (name_of_path: Path.t -> name) = fun path ->
  let s = Path.name path in
  Common.split "\\." s

(*****************************************************************************)
(* Add edges *)
(*****************************************************************************)

let add_use_edge env dst =
  let src = env.current in
  match () with
  | _ when G.has_node dst env.g -> 
      G.add_edge (src, dst) G.Use env.g
  | _ -> 
      let (str, kind) = dst in
      (match kind with
      | _ ->
          let kind_original = kind in
          let dst = (str, kind_original) in
          
          G.add_node dst env.g;
          let parent_target = G.not_found in
          pr2 (spf "PB: lookup fail on %s (in %s)" 
                  (G.string_of_node dst) (G.string_of_node src));
          
          env.g +> G.add_edge (parent_target, dst) G.Has;
          env.g +> G.add_edge (src, dst) G.Use;
      )

let full_path_local_of_kind env kind =
  match kind with
  | E.Function | E.Global | E.Constant
  | E.TopStmts
    -> env.full_path_local_value
  | E.Type | E.Exception -> env.full_path_local_type
  | E.Module -> 
      (* todo: why cant put env.full_path_local_module ? *)
      env.full_path_local_type
  | E.Field | E.Constructor -> ref []
  | _ -> raise Impossible

let add_full_path_local env (s, name) kind =
  Common.push2 (s, name) (full_path_local_of_kind env kind)

let add_node_and_edge_if_defs_mode ?(dupe_ok=false) env name_node loc =
  let (name, kind) = name_node in
  let node = (s_of_n name, kind) in
  if env.phase = Defs then begin
    if G.has_node node env.g && dupe_ok
    then () (* pr2 "already present entity" *)
    else begin
      env.g +> G.add_node node;
      env.g +> G.add_edge (env.current, node) G.Has;

      let lexing_pos = loc.Location.loc_start in
      let file = env.source_file in
      let nodeinfo = { Graph_code.
         pos = { Parse_info.
            str ="";
            line = lexing_pos.Lexing.pos_lnum; 
            charpos = lexing_pos.Lexing.pos_cnum;
            column = lexing_pos.Lexing.pos_cnum - lexing_pos.Lexing.pos_bol;
            file;
         };
         props = [];
      } in
      env.g +> G.add_nodeinfo node nodeinfo
    end
  end;
  add_full_path_local env (Common2.list_last name, name) kind;
  { env with 
    current = node; 
    current_entity = name; 
  }

(*****************************************************************************)
(* Path resolution, locals *)
(*****************************************************************************)

(* f --> A.f,  and Nested.f -> A.Nested.f *)
let rec path_resolve_locals env name kind =
(*
  let s = Path.name p in
  let xs = n_of_s s in
*)
  let rec aux xs =
    match xs with
    | [] -> raise Impossible
    | [x] -> 
        let table = full_path_local_of_kind env kind in
        if List.mem_assoc x !table
        then List.assoc x !table
        else [x]
    | x::xs ->
        let kind = E.Module in
        let table = full_path_local_of_kind env kind in
        if List.mem_assoc x !table
        then List.assoc x !table ++ xs
        else x::xs
  in
  aux name

(*****************************************************************************)
(* Path resolution, aliases *)
(*****************************************************************************)

(* algo: first resolve module aliases, then once have a full path for
 * a type, look for a type alias, and recurse.
 * opti: ?
 *)
let rec path_type_resolve_aliases env pt =
  let rec aux module_aliases_candidates acc pt =
  match pt with
  | [] -> raise Impossible
  (* didn't found any module alias => canonical name module-wise *)
  | [t] -> List.rev (t::acc)
  | x::xs ->
      let reduced_candidates = 
        module_aliases_candidates +> Common.map_filter (function
        | (y::ys, v) when x =$= y -> Some (ys, v)
        | _ -> None
        )
      in
      (match reduced_candidates with
      | [] -> aux [] (x::acc) xs
      (* found a unique alias *)
      | [[], v] -> 
          (* restart from the top *)
          aux !(env.module_aliases) [] (v ++ xs)
      | _ ->
          aux reduced_candidates (x::acc) xs
      )
  in
  let pt = aux !(env.module_aliases) [] pt in
  if List.mem_assoc pt !(env.type_aliases)
  then path_type_resolve_aliases env (List.assoc pt !(env.type_aliases))
  else pt

let rec path_resolve_aliases env p =
  let rec aux module_aliases_candidates acc pt =
  match pt with
  | [] -> raise Impossible
  (* didn't found any module alias => canonical name *)
  | [x] -> List.rev (x::acc)
  | x::xs ->
      let reduced_candidates = 
        module_aliases_candidates +> Common.map_filter (function
        | (y::ys, v) when x =$= y -> Some (ys, v)
        | _ -> None
        )
      in
      (match reduced_candidates with
      | [] -> aux [] (x::acc) xs
      (* found a unique alias *)
      | [[], v] -> 
          (* restart from the top *)
          aux !(env.module_aliases) [] (v ++ xs)
      | _ ->
          aux reduced_candidates (x::acc) xs
      )
  in
  let p = aux !(env.module_aliases) [] p in
  p

(*****************************************************************************)
(* Kind of entity *)
(*****************************************************************************)
    
let rec kind_of_type_desc x =
  (* pr2 (Ocaml.string_of_v (Meta_ast_cmt.vof_type_desc x)); *)
  match x with
  | Types.Tarrow _ -> 
      E.Function
  | Types.Tconstr (path, _, _) when 
        List.mem (Path.name path) ["Pervasives.ref";"Hashtbl.t"] ->
      (* less: potentially anything with a mutable field *)
      E.Global
  (* todo: what if it is an alias to a function type? need resolve here? *)
  | Types.Tconstr (path, xs, aref) -> 
      E.Constant
  | Types.Ttuple _ | Types.Tvariant _ -> 
      E.Constant
  (* ? *)
  | Types.Tvar _ -> E.Constant
  | Types.Tlink x -> kind_of_type_expr x
  | _ -> 
      pr2 (Ocaml.string_of_v (Meta_ast_cmt.vof_type_desc x));
      raise Todo
      
and kind_of_type_expr x =
  kind_of_type_desc x.Types.desc
    
(* used only for primitives *)
let rec kind_of_core_type x =
  match x.ctyp_desc with
  | Ttyp_arrow _ -> E.Function
  | Ttyp_any  | Ttyp_var _
      -> raise Todo
  | _ -> raise Todo

let kind_of_value_descr vd =
  kind_of_core_type vd.val_desc

(*****************************************************************************)
(* Uses with name resolution *)
(*****************************************************************************)

let rec typename_of_texpr x =
  (* pr2 (Ocaml.string_of_v (Meta_ast_cmt.vof_type_expr_show_all x)); *)
  let rec aux x = 
    match x.Types.desc with
    | Types.Tconstr(path, xs, aref) -> path
    | Types.Tlink t -> aux t
    | _ ->
      pr2 (Ocaml.string_of_v (Meta_ast_cmt.vof_type_expr_show_all x));
      raise Todo
  in
  let path = aux x in
  name_of_path path

let add_use_edge_lid env (lid: Longident.t Asttypes.loc) texpr kind =
 if env.phase = Uses then begin
  (* the typename already contains the qualifier *)
  let name = name_of_longident_loc lid in
  let str = Common2.list_last (path_resolve_locals env name kind) in
  let tname = path_resolve_locals env (typename_of_texpr texpr) E.Type in
  let tname = path_type_resolve_aliases env tname in
  let full_ident = tname ++ [str] in
  let node = (s_of_n full_ident, kind) in
  if G.has_node node env.g
  then add_use_edge env node
  else begin
    (match tname with
    | ("unit" | "bool" | "list" | "option" | "exn")::_ -> ()
      (* todo: pfff specific, tofix *)
    | _ when tname +> List.exists (function 
      "LIST" | "Array_id" | "dbty" -> true |_->false) -> ()
    | _ -> pr2 (spf "%s in %s" (Common.dump node) env.file)
    )
  end
 end

let add_use_edge_name_bis env name texpr =
  if env.phase = Uses then begin
    let kind = kind_of_type_expr texpr in
    let name = path_resolve_locals env name kind in
    let name = path_resolve_aliases env name in
    let node = (s_of_n name, kind) in
    if G.has_node node env.g
    then add_use_edge env node
    else 
      (match kind with
      (* ugly: the right fix is to resolve texpr *)
      | E.Constant when G.has_node (s_of_n name, E.Function) env.g ->
          add_use_edge env (s_of_n name, E.Function)
      | _ ->
          (* pfff specific *)
          if name +> List.exists (function
          (* todo: need better n_of_s, or avoid n_of_s and have n_of_path *)
          | "ArithFloatInfix" | "|" -> true
          (* todo: need handle functor *)
          | "Set" | "Map"
          | "SMap" | "IMap" | "ISet" | "SSet" 
          | "StringSetOrig" | "IntMap" | "IntIntMap" | "StringSet" | "StrMap"
          | "SetTestPath" | "Elt_Set"  | "AMap"
          | "Build" | "PMap"
          (* in dataflow_php.ml *)
          | "VarMap" | "VarSet" | "NodeiSet"
              -> true
          | s when s =~ ".*Set" -> true
          | s when s =~ ".*Map" -> true
          (* todo: need handle argument to functor *)
          | "MODEL" | "column_list"
          | "Taint"  | "MATCH" | "X" | "PHP_VS_PHP" | "Interp"
          (* todo: handle pack *)
          | "Digraph"
          (* todo: misc *)
          | "LIST" | "M_01_01"
              -> true

          | _ -> false
          ) then ()
          else pr2 (spf "%s IN %s" (Common.dump node) env.file)
      )
  end

(*****************************************************************************)
(* Empty wrappers *)
(*****************************************************************************)

open Graph_code_cmt_helpers

(*****************************************************************************)
(* Defs/Uses *)
(*****************************************************************************)
let rec extract_defs_uses 
   ~phase ~g ~ast ~readable ~root
   ~module_aliases ~type_aliases =
  let current =
    (* Module names are supposed to be unique for the ocaml linker,
     * but it's common to have multiple main.ml files that are linked
     * separately. But for codegraph we want to have a graph of all
     * those files, and so to avoid conflicts we use the filename
     * instead of the module. Anyway there should be no external
     * reference to those modules so we should be safe to not use
     * a E.Module.
     * less: could also mark those as a dupe module and generate a File 
     *)
    if ast.cmt_modname =~ "Main.*"
    then (readable, E.File)
    else (ast.cmt_modname, E.Module)
  in
  let env = {
    g; phase;
    current;
    current_entity = [fst current];
    file = readable;
    (* we want a readable format here *)
    source_file =
      (let fullpath =
         Filename.concat ast.cmt_builddir
           (match ast.cmt_sourcefile with
           | None -> failwith (spf "no cmt_source_file for %s" readable)
           | Some file -> file
           )
       in
       (* ugly: the OCaml distribution does not comes with .cmt for
        * its standard library, so I had to generate them manually 
        * and put them in pfff/external/stdlib. The problem is that
        * those cmt files have hardcoded paths to my ocaml installation
        * for their source, hence this hack below to reconvert
        * those paths.
        *)
       if fullpath =~ ".*/ocaml-4.01.0" || fullpath =~ ".*/ocaml-4.00.1"
       then spf "external/stdlib/%s" (Filename.basename fullpath)
       else 
         let readable = Common.filename_without_leading_path root fullpath in
         if readable =~ "_build/\\(.*\\)"
         then Common.matched1 readable
         else readable
      );
    locals = [];
    full_path_local_value = ref [];
    full_path_local_type = ref [];
    full_path_local_module = ref [];
    module_aliases; type_aliases;
  }
  in
  if phase = Defs then begin
    let dir = Common2.dirname readable in
    G.create_intermediate_directories_if_not_present g dir;
    g +> G.add_node env.current;
    g +> G.add_edge ((dir, E.Dir), env.current) G.Has;
  end;
  if phase = Uses then begin
    ast.cmt_imports +> List.iter (fun (s, digest) ->
      (* old: add_use_edge env (s, E.Module)
       * actually ocaml list as dependencies many things which are not.
       * Most modules will have in their import for instance Sexp,
       * even though they don't use anything from Sexp, not sure why ...
       *)
      ()
    );
  end;
  binary_annots env ast.cmt_annots

and binary_annots env = function
  | Implementation s -> 
      structure env s
  (* sometimes we have just the .cmti, no .cmt, so we need to process those,
   * e.g. asttypes.cmti in ocaml source 
   * todo? also for core lib we actually may prefer to process the .mli?
   *)
  | Interface s ->
     signature env s

  | Packed _ 
  | Partial_implementation _ | Partial_interface _ ->
      pr2_gen env.current;
      raise Todo

and structure env 
 { str_items = v_str_items;  str_type = _v_str_type; str_final_env = _env } =
  List.iter (structure_item env) v_str_items
and structure_item env 
 { str_desc = v_str_desc; str_loc = loc; str_env = _ } =
  structure_item_desc env loc v_str_desc

and  pattern env
  { pat_desc = v_pat_desc; pat_type = v_pat_type; 
    pat_loc = v_pat_loc; pat_extra = _v_pat_extra; pat_env = v_pat_env } =
  pattern_desc v_pat_type env v_pat_desc

and expression env
    { exp_desc = v_exp_desc; exp_loc = v_exp_loc;  exp_extra = __v_exp_extra;
      exp_type = v_exp_type; exp_env = v_exp_env } =
  expression_desc v_exp_type env v_exp_desc
and module_expr env
    { mod_desc = v_mod_desc; mod_loc = v_mod_loc;
      mod_type = v_mod_type; mod_env = v_mod_env  } =
  module_expr_desc env v_mod_desc;
  Types.module_type env v_mod_type

and signature env
  { sig_items = v_sig_items; sig_type = _v_sig_type; sig_final_env = _env } =
  List.iter (sig_item env) v_sig_items
and sig_item env
    { sig_desc = v_sig_desc; sig_env = _; sig_loc = loc } =
  sig_item_desc env loc v_sig_desc

(* ---------------------------------------------------------------------- *)
(* Structure *)
(* ---------------------------------------------------------------------- *)
and structure_item_desc env loc = function
  | Tstr_eval v1 -> 
    let full_ident = env.current_entity ++ ["__toplevel__"] in
    let node = (full_ident, E.TopStmts) in
    let env = 
      add_node_and_edge_if_defs_mode ~dupe_ok:true env node loc in
    expression env v1

  | Tstr_value ((rec_flag, xs)) ->
      (* first pass *)
      if rec_flag = Asttypes.Recursive then begin
        List.iter (fun (v1, v2) ->
          match v1.pat_desc with
          | Tpat_var(id, _loc) | Tpat_alias (_, id, _loc) ->
              let full_ident = env.current_entity ++ [Ident.name id] in
              add_full_path_local env (Ident.name id, full_ident) 
                (kind_of_type_expr v2.exp_type)
          | _ -> ()
        ) xs;
      end;

      (* second pass *)
      List.iter (fun (v1, v2) ->
        match v1.pat_desc with
        | Tpat_var(id, loc) | Tpat_alias (_, id, loc) ->
            let full_ident = env.current_entity ++ [Ident.name id] in
            let node = (full_ident, kind_of_type_expr v2.exp_type) in
            (* some people do let foo = ... let foo = ... in the same file *)
            let env = 
              add_node_and_edge_if_defs_mode ~dupe_ok:true env node 
                (unwrap loc) in
            expression env v2
        | Tpat_tuple xs ->
            let xdone = ref false in
            xs +> List.iter (fun p ->
              match p.pat_desc with
              | Tpat_var(id, loc) | Tpat_alias (_, id, loc) ->
                  let full_ident = env.current_entity ++ [Ident.name id] in
                  let node = (full_ident, kind_of_type_expr p.pat_type) in
                  let env = 
                    add_node_and_edge_if_defs_mode ~dupe_ok:true env node 
                      (unwrap loc) in

                  (* arbitrarily choose the first one as the source for v2 *)
                  if not !xdone then begin
                    xdone := true;
                    expression env v2
                  end
              | _ -> 
                  pattern env p
            );
            if not !xdone then expression env v2
      
        | _ ->
            let env = {env with locals = env.locals } in
            pattern env v1;
            expression env v2 
      ) xs
  | Tstr_primitive ((id, loc, vd)) ->
      let full_ident = env.current_entity ++ [Ident.name id] in
      let node = (full_ident, kind_of_value_descr vd) in
      let env = add_node_and_edge_if_defs_mode env node (unwrap loc) in
      value_description env vd
  | Tstr_type xs ->
      List.iter (fun (id, loc, td) ->
        let full_ident = env.current_entity ++ [Ident.name id] in
        let node = (full_ident, E.Type) in
        let env = add_node_and_edge_if_defs_mode env node (unwrap loc) in

        (match td.typ_kind, td.typ_manifest with
        | Ttype_abstract, Some ({ctyp_desc=Ttyp_constr (path, lid, _xs); _}) ->
          if env.phase = Defs then
            let name = name_of_path path in
            Common.push2 (full_ident, path_resolve_locals env name E.Type)
              env.type_aliases
        | _ -> ()
        );
        type_declaration env td
      ) xs
  | Tstr_exception ((id, loc, v3)) ->
      let full_ident = env.current_entity ++ ["exn";Ident.name id] in
      let node = (full_ident, E.Exception) in
      let env = 
        add_node_and_edge_if_defs_mode ~dupe_ok:true env node (unwrap loc) in
      exception_declaration env v3
  | Tstr_exn_rebind ((id, loc, v3, _loc2)) ->
      let full_ident = env.current_entity ++ ["exn";Ident.name id] in
      let node = (full_ident, E.Exception) in
      let env = add_node_and_edge_if_defs_mode env node (unwrap loc) in
      path_t env v3
  | Tstr_module ((id, loc, modexpr)) ->
      let full_ident = env.current_entity ++ [Ident.name id] in
      let node = (full_ident, E.Module) in
      (match modexpr.mod_desc with
      | Tmod_ident (path, lid) ->
          (* do not add nodes for module aliases in the graph, just *)
          if env.phase = Defs then begin
            let name = name_of_path path in
            Common.push2 (full_ident, path_resolve_locals env name E.Module) 
              env.module_aliases
          end;
          add_full_path_local env (Ident.name id, full_ident) E.Module
      | _ -> 
          let env = add_node_and_edge_if_defs_mode env node (unwrap loc) in
          module_expr env modexpr
      )
  | Tstr_recmodule xs ->
      List.iter (fun (id, loc, v3, v4) ->
        let full_ident = env.current_entity ++ [Ident.name id] in
        let node = (full_ident, E.Module) in
        let env = add_node_and_edge_if_defs_mode env node (unwrap loc) in
        module_type env v3;
        module_expr env v4;
      ) xs
  | Tstr_modtype ((v1, _loc, v3)) ->
      let _ = Ident.t env v1
      and _ = module_type env v3
      in ()

  (* opened names are resolved, no need to handle that I think *)
#if OCAML_VERSION >= 4010
  | Tstr_open ((_override, v1, _loc)) ->
      path_t env v1 
#else
  | Tstr_open ((v1, _loc)) ->
      path_t env v1 
#endif
  | Tstr_include ((v1, v2)) ->
      let _ = module_expr env v1 and _ = List.iter (Ident.t env) v2 in ()

  | (Tstr_class _|Tstr_class_type _) -> 
    (*pr2_once (spf "TODO: str_class, %s" env.file)*)
    ()

and type_declaration env
    { typ_params = __v_typ_params; typ_type = v_typ_type;
      typ_cstrs = v_typ_cstrs; typ_kind = v_typ_kind;
      typ_private = _v_typ_private; typ_manifest = v_typ_manifest;
      typ_variance = v_typ_variance; typ_loc = v_typ_loc
    } =
  let _ = Types.type_declaration env v_typ_type in
  let _ =
    List.iter
      (fun (v1, v2, _loc) ->
         let _ = core_type env v1
         and _ = core_type env v2
         in ())
      v_typ_cstrs in
  let _ = type_kind env v_typ_kind in
  let _ = v_option (core_type env) v_typ_manifest in
  List.iter (fun (_bool, _bool2) -> ()) v_typ_variance;
  ()
and type_kind env = function
  | Ttype_abstract -> ()
  | Ttype_variant xs ->
      List.iter (fun (id, loc, v3, _loc2) ->
        let full_ident = env.current_entity ++ [Ident.name id] in
        let node = (full_ident, E.Constructor) in
        let env = add_node_and_edge_if_defs_mode env node (unwrap loc) in
        List.iter (core_type env) v3;
      ) xs
  | Ttype_record xs ->
      List.iter  (fun (id, loc, _mutable_flag, v4, _loc2) ->
        let full_ident = env.current_entity ++ [Ident.name id] in
        let node = (full_ident, E.Field) in
        let env = add_node_and_edge_if_defs_mode env node (unwrap loc) in
        core_type env v4;
      ) xs

and exception_declaration env 
 { exn_params = v_exn_params; exn_exn = v_exn_exn; exn_loc = _v_exn_loc } =
  let _ = List.iter (core_type env) v_exn_params in
  let _ = Types.exception_declaration env v_exn_exn in
  ()

(* ---------------------------------------------------------------------- *)
(* Signature *)
(* ---------------------------------------------------------------------- *)
and sig_item_desc env loc = function
  | Tsig_type xs -> structure_item_desc env loc (Tstr_type xs)
  | _ -> pr2_once "TODO: sig_item_desc"

(* ---------------------------------------------------------------------- *)
(* Pattern *)
(* ---------------------------------------------------------------------- *)
and pattern_desc t env = function
  | Tpat_any -> ()
  | Tpat_var ((id, _loc)) ->
      env.locals <- Ident.name id :: env.locals
  | Tpat_alias ((v1, id, _loc)) ->
      pattern env v1;
      env.locals <- Ident.name id :: env.locals
  | Tpat_constant v1 -> 
      constant env v1
  | Tpat_tuple xs -> 
      List.iter (pattern env) xs
#if OCAML_VERSION >= 4010
  | Tpat_construct (lid, v3, v4, v5)
#else
  | Tpat_construct (_path, lid, v3, v4, v5) 
#endif
    ->
      add_use_edge_lid env lid t E.Constructor;
      let _ = constructor_description env v3
      and _ = List.iter (pattern env) v4
      in ()
  | Tpat_variant ((v1, v2, v3)) ->
      let _ = label env v1
      and _ = v_option (pattern env) v2
      and _ = v_ref (row_desc env) v3
      in ()
  | Tpat_record ((xs, _closed_flag)) ->
      List.iter (fun 
#if OCAML_VERSION >= 4010
        (lid, v2, v3) 
#else
       (_path, lid, v2, v3)
#endif
      ->
        add_use_edge_lid env lid t E.Field;
        let _ = label_description env v3
        and _ = pattern env v3
        in ()
      ) xs
  | Tpat_array xs -> 
      List.iter (pattern env) xs
  | Tpat_or ((v1, v2, v3)) ->
      let _ = pattern env v1
      and _ = pattern env v2
      and _ = v_option (row_desc env) v3
      in ()
  | Tpat_lazy v1 -> 
      pattern env v1

(* ---------------------------------------------------------------------- *)
(* Expression *)
(* ---------------------------------------------------------------------- *)
and expression_desc t env =
  function
  | Texp_ident (path, lid, vd) ->
      let name = name_of_path path in
      let str = s_of_n name in
      if List.mem str env.locals
      then ()
      else add_use_edge_name_bis env name t
  | Texp_constant v1 -> 
      constant env v1
  | Texp_let ((rec_flag, xs, v3)) ->
      (* first pass *)
      if rec_flag = Asttypes.Recursive then begin
        xs +> List.iter (fun (v1, v2) ->
          match v1.pat_desc with
          | Tpat_var (id, _loc) | Tpat_alias (_, id, _loc) ->
              env.locals <- Ident.name id:: env.locals
          | _ -> ()
        );
      end;
      (* second pass *)
      xs +> List.iter (fun (v1, v2) ->
        pattern env v1;
        expression env v2;
      );
      expression env v3
  | Texp_function ((v1, v2, v3)) ->
      let _ = label env v1
      and _ =
        List.iter
          (fun (v1, v2) ->
             let _ = pattern env v1 and _ = expression env v2 in ())
          v2
      and _ = partial env v3
      in ()
  | Texp_apply ((v1, v2)) ->
      let _ = expression env v1
      and _ =
        List.iter
          (fun (v1, v2, v3) ->
             let _ = label env v1
             and _ = v_option (expression env) v2
             and _ = optional env v3
             in ())
          v2
      in ()
  | Texp_match ((v1, v2, v3)) ->
      let _ = expression env v1
      and _ =
        List.iter
          (fun (v1, v2) ->
             let _ = pattern env v1 and _ = expression env v2 in ())
          v2
      and _ = partial env v3
      in ()
  | Texp_try ((v1, v2)) ->
      let _ = expression env v1
      and _ =
        List.iter
          (fun (v1, v2) ->
             let _ = pattern env v1 and _ = expression env v2 in ())
          v2
      in ()
  | Texp_tuple v1 -> let _ = List.iter (expression env) v1 in ()
#if OCAML_VERSION >= 4010
  | Texp_construct (lid, v2, v3, _bool) 
#else
  | Texp_construct (_path, lid, v2, v3, _bool) 
#endif
    ->
      add_use_edge_lid env lid t E.Constructor;
      constructor_description env v2;
      List.iter (expression env) v3;

  | Texp_variant ((v1, v2)) ->
      let _ = label env v1 and _ = v_option (expression env) v2 in ()
  (* ?? *)
  | Texp_record ((v1, v2)) ->
      List.iter (fun 
#if OCAML_VERSION >= 4010
        (lid, v2, v3) 
#else
        (_path, lid, v2, v3) 
#endif
      ->
        path_t env lid;
        let _ = label_description env v2
        and _ = expression env v3
        in ()
      ) v1;
      v_option (expression env) v2
#if OCAML_VERSION >= 4010
  | Texp_field ((v1, lid, v2)) 
#else
  | Texp_field ((v1, _path, lid, v2)) 
#endif
    ->
      expression env v1;
      add_use_edge_lid env lid v1.exp_type E.Field;
      label_description env v2

#if OCAML_VERSION >= 4010
  | Texp_setfield ((v1, lid, v3, v4)) 
#else
  | Texp_setfield ((v1, _path, lid, v3, v4)) 
#endif
    ->
      expression env v1;
      add_use_edge_lid env lid v1.exp_type E.Field;
      label_description env v3;
      expression env v4;

  | Texp_array xs -> 
      List.iter (expression env) xs

  | Texp_ifthenelse ((v1, v2, v3)) ->
      let _ = expression env v1
      and _ = expression env v2
      and _ = v_option (expression env) v3
      in ()
  | Texp_sequence ((v1, v2)) ->
      let _ = expression env v1 and _ = expression env v2 in ()
  | Texp_while ((v1, v2)) ->
      let _ = expression env v1 and _ = expression env v2 in ()
  | Texp_for ((id, _loc_string, v3, v4, _direction_flag, v6)) ->
      expression env v3;
      expression env v4;
      let env = { env with locals = Ident.name id::env.locals } in
      expression env v6
  | Texp_when ((v1, v2)) ->
      let _ = expression env v1 and _ = expression env v2 in ()

  | Texp_send ((v1, v2, v3)) ->
      let _ = expression env v1
      and _ = meth env v2
      and _ = v_option (expression env) v3
      in ()
  | Texp_new ((v1, _loc_longident, v3)) ->
      let _ = path_t env v1
      and _ = Types.class_declaration env v3
      in ()
  | Texp_instvar ((v1, v2, _loc)) ->
      let _ = path_t env v1
      and _ = path_t env v2
      in ()
  | Texp_setinstvar ((v1, v2, _loc, v4)) ->
      let _ = path_t env v1
      and _ = path_t env v2
      and _ = expression env v4
      in ()
  | Texp_override ((v1, v2)) ->
      let _ = path_t env v1
      and _ =
        List.iter
          (fun (v1, _loc, v3) ->
             let _ = path_t env v1
             and _ = expression env v3
             in ())
          v2
      in ()
  | Texp_letmodule ((v1, _loc, v3, v4)) ->
      let _ = Ident.t env v1
      and _ = module_expr env v3
      and _ = expression env v4
      in ()
  | Texp_assert v1 -> let _ = expression env v1 in ()
  | Texp_assertfalse -> ()
  | Texp_lazy v1 -> let _ = expression env v1 in ()
  | Texp_object ((v1, v2)) ->
      let _ = class_structure env v1 and _ = List.iter v_string v2 in ()
  | Texp_pack v1 -> let _ = module_expr env v1 in ()

and exp_extra env = function
  | Texp_constraint ((v1, v2)) ->
      let _ = v_option (core_type env) v1
      and _ = v_option (core_type env) v2
      in ()
#if OCAML_VERSION >= 4010
  | Texp_open (_override, path, lid, _env) 
#else
  | Texp_open (path, lid, _env)
#endif
   ->
      path_t env path
  | Texp_poly v1 -> let _ = v_option (core_type env) v1 in ()
  | Texp_newtype v1 -> let _ = v_string v1 in ()

(* ---------------------------------------------------------------------- *)
(* Module *)
(* ---------------------------------------------------------------------- *)
and module_expr_desc env =
  function
  | Tmod_ident ((v1, _loc_longident)) ->
      path_t env v1
  | Tmod_structure v1 -> structure env v1
  | Tmod_functor ((v1, _loc, v3, v4)) ->
      let _ = Ident.t env v1
      and _ = module_type env v3
      and _ = module_expr env v4
      in ()
  | Tmod_apply ((v1, v2, v3)) ->
      let _ = module_expr env v1
      and _ = module_expr env v2
      and _ = module_coercion env v3
      in ()
  | Tmod_constraint ((v1, v2, v3, v4)) ->
      let _ = module_expr env v1
      and _ = Types.module_type env v2
      and _ = module_type_constraint env v3
      and _ = module_coercion env v4
      in ()
  | Tmod_unpack ((v1, v2)) ->
      let _ = expression env v1 
      and _ = Types.module_type env v2 
      in ()
(* ---------------------------------------------------------------------- *)
(* Type *)
(* ---------------------------------------------------------------------- *)
and core_type env
    { ctyp_desc = v_ctyp_desc; ctyp_type = __v_ctyp_type;
      ctyp_env = v_ctyp_env; ctyp_loc = v_ctyp_loc } =
  core_type_desc env v_ctyp_desc
and core_type_desc env =
  function
  | Ttyp_any -> ()
  | Ttyp_var v1 -> let _ = v_string v1 in ()
  | Ttyp_arrow ((v1, v2, v3)) ->
      let _ = label env v1
      and _ = core_type env v2
      and _ = core_type env v3
      in ()
  | Ttyp_tuple v1 -> let _ = List.iter (core_type env) v1 in ()
  | Ttyp_constr ((v1, _loc_longident, v3)) ->
      let _ = path_t env v1
      and _ = List.iter (core_type env) v3
      in ()
  | Ttyp_object v1 -> let _ = List.iter (core_field_type env) v1 in ()
  | Ttyp_class ((v1, _loc_longident, v3, v4)) ->
      let _ = path_t env v1
      and _ = List.iter (core_type env) v3
      and _ = List.iter (label env) v4
      in ()
  | Ttyp_alias ((v1, v2)) ->
      let _ = core_type env v1 and _ = v_string v2 in ()
  | Ttyp_variant ((v1, _bool, v3)) ->
      let _ = List.iter (row_field env) v1
      and _ = v_option (List.iter (label env)) v3
      in ()
  | Ttyp_poly ((v1, v2)) ->
      let _ = List.iter v_string v1 and _ = core_type env v2 in ()
  | Ttyp_package v1 -> 
    pr2_once (spf "TODO: Ttyp_package, %s" env.file)

and core_field_type env { field_desc = v_field_desc; field_loc = v_field_loc }=
  let _ = core_field_desc env v_field_desc in ()
  
and core_field_desc env =
  function
  | Tcfield ((v1, v2)) -> let _ = v_string v1 and _ = core_type env v2 in ()
  | Tcfield_var -> ()
and row_field env =
  function
  | Ttag ((v1, _bool, v3)) ->
      let _ = label env v1
      and _ = List.iter (core_type env) v3
      in ()
  | Tinherit v1 -> let _ = core_type env v1 in ()
and
  value_description env
                    {
                      val_desc = v_val_desc;
                      val_val = v_val_val;
                      val_prim = v_val_prim;
                      val_loc = v_val_loc
                    } =
  let _ = core_type env v_val_desc in
  let _ = Types.value_description env v_val_val in
  let _ = List.iter v_string v_val_prim in
  ()

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let build ?(verbose=false) dir_or_file skip_list =
  let root = Common.realpath dir_or_file in
  let all_files = Lib_parsing_ml.find_cmt_files_of_dir_or_files [root] in

  (* step0: filter noisy modules/files *)
  let files = Skip_code.filter_files skip_list root all_files in

  let g = G.create () in
  G.create_initial_hierarchy g;

  let module_aliases = ref [] in
  let type_aliases = ref [] in

  (* step1: creating the nodes and 'Has' edges, the defs *)
  if verbose then pr2 "\nstep1: extract defs";
  files +> Common_extra.progress ~show:verbose (fun k -> 
    List.iter (fun file ->
      k();
      let ast = parse file in
      let readable = Common.filename_without_leading_path root file in
      extract_defs_uses ~g ~ast ~phase:Defs ~readable ~root
        ~module_aliases ~type_aliases;
      ()
    ));

  (* step2: creating the 'Use' edges *)
  if verbose then pr2 "\nstep2: extract uses";
  files +> Common_extra.progress ~show:verbose (fun k -> 
    List.iter (fun file ->
      k();
      let ast = parse file in
      let readable = Common.filename_without_leading_path root file in
      if readable =~ "^external" || readable =~ "^EXTERNAL"
      then ()
      else extract_defs_uses ~g ~ast ~phase:Uses ~readable ~root
             ~module_aliases ~type_aliases
    ));
  if verbose then begin
    pr2 "";
    pr2 "module aliases";
    !module_aliases +> List.iter pr2_gen;
    pr2 "type aliases";
    !type_aliases +> List.iter pr2_gen;
  end;

  g
