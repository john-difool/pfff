(* Yoann Padioleau
 *
 * Copyright (C) 2012 Facebook
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
module G = Graph

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* 
 * A program can be seen as a hierarchy of entities
 * (directory/package/module/file/class/function/method/field/...)
 * linked to each other through different mechanisms
 * (import/reference/extend/implement/instantiate/call/access/...).
 * This module is the basis for 'codegraph', a tool to help
 * visualize code dependencies or code relationships. 
 * It provides one of the core data structure of codegraph
 * an (hyper)graph of all the entities in a program linked
 * either via a 'has-a' relation, which represent the
 * hierarchies (in the sense of containment, not inheritance), or
 * 'use-a', which represent the dependencies
 * (the other core data structure of codegraph is in
 * dependencies_matrix_code.ml).
 * 
 * Is this yet another code database? For PHP we already have
 * database_php.ml, tags_php.ml, database_light_php.ml, 
 * and now even a Prolog database, ... that's a lot of code database.
 * They all have things in common, but by focusing here on one thing,
 * by just having a single graph, it's then
 * easier to reason and implement certain features.
 * I could have probably done the DSM using database_php.ml
 * but it was not made for that. Here the graph is
 * the core and simplest data structure that is needed.
 * 
 * This graph also unifies many things. For instance there is no
 * special code to handle directories or files, they are
 * just considered regular entities like module or classes 
 * and can have sub-entities. Moreover like database_light.ml,
 * this file is language independent so one can have one tool
 * that can handle ML, PHP, C++, etc.
 * 
 * todo:
 *  - how to handle duplicate entities (e.g. we can have two different
 *    files with the same module name, or two functions with the same
 *    name but one in a library and the other in a script).
 *    prepend a ___number suffix?
 *    Or just have one node with multiple parents :) But having
 *    multiple parents would not solve the problem because then
 *    an edge will increment unrelated cells in the DSM.
 * 
 *  - change API to allow by default to automatically create nodes
 *    when create edges with unexisting nodes? After all graphviz
 *    allow to specify graphs like this, which shorten graph
 *    description significantly. Can still have a 
 *    add_edge_throw_exn_if_not_present for the cases where we
 *    want extra security.
 * 
 *  - maybe I can generate the light database from this graph_code.ml
 *    (I already do a bit for prolog with graph_code_prolog.ml)
 * 
 *  - opti: faster implem of parent? have a lock_graph() that forbid any
 *    further modifications on Has but then provide optimized operations 
 *    like parent the precompute or memoize the parent relation
 * 
 * related work:
 *  - grok: by steve yegge http://www.youtube.com/watch?v=KTJs-0EInW8
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

type node = string * E.entity_kind

type edge =
  (* a package Has subpackages, a subpackage Has classes, a class Has members,
   * etc *)
  | Has
  (* A class Use(extends) another class, a method Use(calls) another method,
   * etc.
   * todo? refine by having different cases? Use of `Call|`Extend|...? *)
  | Use

type nodeinfo = { 
  pos: Parse_info.token_location;
  props: E.property list;
}

(* 
 * We use an imperative, directed, without intermediate node-index, graph.
 * 
 * We use two different graphs because we need an efficient way to
 * go up in the hierarchy to increment cells in the dependency matrix
 * so it's better to separate the two usages.
 * 
 * note: file information are in readable path format in Dir and File
 * nodes (and should also be in readable format in the nodeinfo).
 *)
type graph = {
  (* Actually the Has graph should really be a tree, but we need convenient
   * access to the children or parent of a node, which are provided
   * by the graph API so let's reuse that.
   *)
  has: node G.graph;
  (* The source and target should be enough information to understand
   * the kind of Use. For instance a class referencing another class
   * has to be an 'extends'. A class referencing an Interface has to
   * be an 'implements'.
   *)
  use: node G.graph;

  info: (node, nodeinfo) Hashtbl.t;
}

type error =
 | NodeAlreadyPresent of node

exception Error of error

(* we sometimes want to collapse unimportant directories under a "..."
 * fake intermediate directory. So one can create an adjust file with
 * for instance:
 *   api -> extra/
 * and we will delete the current parent of 'api' and relink it to the
 * extra/ entity (possibly newly created)
 *)
type adjust = (string * string)

(* skip certain edges that are marked as ok regarding backward dependencies *)
type dependency = (node * node)
type whitelist = dependency list

(*****************************************************************************)
(* Constants *)
(*****************************************************************************)
let root = ".", E.Dir
let pb = "PB", E.Dir
 let not_found = "NOT_FOUND", E.Dir
 let dupe = "DUPE", E.Dir
let _stdlib = "STDLIB", E.Dir

(*****************************************************************************)
(* Debugging *)
(*****************************************************************************)

let string_of_node (s, kind) =
  E.string_of_entity_kind kind ^ ": " ^ s

let string_of_error = function
  | NodeAlreadyPresent n -> ("Node already present: " ^ string_of_node n)

let node_of_string s =
  if s =~ "\\([^:]*\\):\\(.*\\)"
  then 
    let (s1, s2) = Common.matched2 s in
    s2, E.entity_kind_of_string s1
  else 
    failwith (spf "node_of_string: wrong format '%s'" s)

let display_with_gv g =
  (* TODO? use different colors for the different kind of edges? *)
  G.display_with_gv g.has

(*****************************************************************************)
(* Graph construction *)
(*****************************************************************************)
let create () =
  { has = G.create ();
    use = G.create ();
    info = Hashtbl.create 101;
  }

let add_node n g =
  if G.has_node n g.has
  then begin 
    pr2_gen n;
    raise (Error (NodeAlreadyPresent n))
  end;
  if G.has_node n g.use
  then begin 
    pr2_gen n;
    raise (Error (NodeAlreadyPresent n))
  end;

  G.add_vertex_if_not_present n g.has;
  G.add_vertex_if_not_present n g.use;
  ()

let add_edge (n1, n2) e g =
  match e with
  | Has -> G.add_edge n1 n2 g.has
  | Use -> G.add_edge n1 n2 g.use

let remove_edge (n1, n2) e g =
  match e with
  | Has -> G.remove_edge n1 n2 g.has
  | Use -> G.remove_edge n1 n2 g.use

let add_nodeinfo n info g =
  if not (G.has_node n g.has)
  then failwith "unknown node";

  Hashtbl.replace g.info n info

(*****************************************************************************)
(* IO *)
(*****************************************************************************)
(* todo: what when have a .opti? cache_computation will shortcut us *)
let version = 2

let save g file =
  (* see ocamlgraph FAQ *)
  Common2.write_value (g, !Ocamlgraph.Blocks.cpt_vertex, version) file

let load file =
  let (g, serialized_cpt_vertex, version2) = Common2.get_value file in
  if version != version2
  then failwith (spf "your marshalled file has an old version, delete it");
  Ocamlgraph.Blocks.after_unserialization serialized_cpt_vertex;
  g

let default_graphcode_filename =
  "graph_code.marshall"

(*****************************************************************************)
(* Graph access *)
(*****************************************************************************)

let has_node n g =
  G.has_node n g.has

let pred n e g =
  match e with
  | Has -> G.pred n g.has
  | Use -> G.pred n g.use

let succ n e g =
  match e with
  | Has -> G.succ n g.has
  | Use -> G.succ n g.use


let parent n g =
  let xs = G.pred n g.has in
  Common2.list_to_single_or_exn xs

let parents n g =
  G.pred n g.has

let children n g =
  G.succ n g.has

let rec all_children n g =
  let xs = G.succ n g.has in
  if null xs 
  then [n]
  else 
    n::(xs +> List.map (fun n -> all_children n g) +> List.flatten)


let nb_nodes g = 
  G.nb_nodes g.has
let nb_use_edges g =
  G.nb_edges g.use

let nodeinfo n g =
  Hashtbl.find g.info n

(* todo? assert it's a readable path? graph_code_php.ml is using readable
 * path now but the other might not yet or it can be sometimes convenient
 * also to have absolute path here, so not sure if can assert anything.
 *)
let file_of_node n g =
  try 
    let info = nodeinfo n g in
    info.pos.Parse_info.file
  with Not_found ->
    raise Not_found
(*
    (match n with
    | str, (E.Dir | E.File) -> str
    | _ -> 
      (* todo: BAD no? *)
      spf "NOT_FOUND_FILE (for node %s)" (string_of_node n)
    )
*)

(*****************************************************************************)
(* Iteration *)
(*****************************************************************************)
let iter_use_edges f g =
  G.iter_edges f g.use

let iter_nodes f g =
  G.iter_nodes f g.has

let all_use_edges g =
  let res = ref [] in
  G.iter_edges (fun n1 n2 -> Common.push2 (n1, n2) res) g.use;
  !res

let all_nodes g =
  let res = ref [] in
  G.iter_nodes (fun n -> Common.push2 n res) g.has;
  !res

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let create_intermediate_directories_if_not_present g dir =
  let dirs = Common2.inits_of_relative_dir dir in

  let rec aux current xs =
    match xs with
    | [] -> ()
    | x::xs ->
        let entity = x, E.Dir in
        if has_node entity g
        then aux entity xs
        else begin
          g +> add_node entity;
          g +> add_edge (current, entity) Has;
          aux entity xs
        end
  in
  aux root dirs


let create_initial_hierarchy g =
  g +> add_node root;
  g +> add_node pb;
  g +> add_node not_found;
  g +> add_node dupe;
(*  g +> add_node stdlib;*)
  g +> add_edge (root, pb) Has;
  g +> add_edge (pb, dupe) Has;
  g +> add_edge (pb, not_found) Has;
(*  g +> add_edge (root, stdlib) Has;*)
  ()

(*****************************************************************************)
(* Misc *)
(*****************************************************************************)

let group_edges_by_files_edges xs g =
  xs +> Common2.group_by_mapped_key (fun (n1, n2) ->
    (file_of_node n1 g, file_of_node n2 g)
  ) +> List.map (fun (x, deps) -> List.length deps, (x, deps))
    +> Common.sort_by_key_highfirst
    +> List.map snd

(*****************************************************************************)
(* Graph algorithms *)
(*****************************************************************************)
let strongly_connected_components_use_graph g =
  let (scc, hscc) = G.strongly_connected_components g.use in
  scc, hscc

let top_down_numbering g =
  let (scc, hscc) = 
    G.strongly_connected_components g.use in
  let g2 = 
    G.strongly_connected_components_condensation g.use (scc, hscc) in
  let hdepth = 
    G.depth_nodes g2 in
  
  let hres = Hashtbl.create 101 in
  hdepth +> Hashtbl.iter (fun k v ->
    let nodes_at_k = scc.(k) in
    nodes_at_k +> List.iter (fun n -> Hashtbl.add hres n v)
  );
  hres

let bottom_up_numbering g =
  let (scc, hscc) = 
    G.strongly_connected_components g.use in
  let g2 = 
    G.strongly_connected_components_condensation g.use (scc, hscc) in
  let g3 = 
    G.mirror g2 in
  let hdepth = 
    G.depth_nodes g3 in
  
  let hres = Hashtbl.create 101 in
  hdepth +> Hashtbl.iter (fun k v ->
    let nodes_at_k = scc.(k) in
    nodes_at_k +> List.iter (fun n -> Hashtbl.add hres n v)
  );
  hres

(*****************************************************************************)
(* Graph adjustments *)
(*****************************************************************************)
let load_adjust file =
  Common.cat file 
  +> Common.exclude (fun s -> 
    s =~ "#.*" || s =~ "^[ \t]*$"
  )
  +> List.map (fun s ->
    match s with
    | _ when s =~ "\\([^ ]+\\)[ ]+->[ ]*\\([^ ]+\\)" ->
      Common.matched2 s
    | _ -> failwith ("wrong line format in adjust file: " ^ s)
  )

let load_whitelist file =
  Common.cat file +>
  List.map (fun s ->
    if s =~ "\\(.*\\) --> \\(.*\\) "
    then
      let (s1, s2) = Common.matched2 s in
      node_of_string s1, node_of_string s2
    else failwith (spf "load_whitelist: wrong line: %s" s)
  )

let save_whitelist xs file g =
  Common.with_open_outfile file (fun (pr_no_nl, _chan) ->
    xs +> List.iter (fun (n1, n2) ->
      let file = file_of_node n2 g in
      pr_no_nl (spf "%s --> %s (%s)\n"
                  (string_of_node n1) (string_of_node n2) file);
    )
  )


(* Used mainly to collapse many entries under a "..." intermediate fake
 * parent. Maybe this could be done automatically in codegraph at some point,
 * like ndepend does I think.
 *)
let adjust_graph g xs whitelist =
  let mapping = Hashtbl.create 101 in
  g +> iter_nodes (fun (s, kind) ->
    Hashtbl.add mapping s (s, kind)
  );
  xs +> List.iter (fun (s1, s2) ->
    let nodes = Hashtbl.find_all mapping s1 in

    let new_parent = (s2, E.Dir) in
    create_intermediate_directories_if_not_present g s2;
    (match nodes with
    | [n] ->
      let old_parent = parent n g in
      remove_edge (old_parent, n) Has g;
      add_edge (new_parent, n) Has g;
    | [] -> failwith (spf "could not find entity %s" s1)
    | _ -> failwith (spf "multiple entities with %s as a name" s1)
    )
  );
  whitelist +> Common_extra.progress ~show:true (fun k ->
    List.iter (fun (n1, n2) ->
      k();
      remove_edge (n1, n2) Use g;
    )
  )

(*****************************************************************************)
(* Example *)
(*****************************************************************************)
let graph_of_dotfile dotfile =
  let xs = Common.cat dotfile in
  let deps =
    xs +> Common.map_filter (fun s ->
      if s =~ "^\"\\(.*\\)\" -> \"\\(.*\\)\"$"
      then
        let (src, dst) = Common.matched2 s in
        Some (src, dst)
      else begin
        pr2 (spf "ignoring line: %s" s);
        None
      end
    )
  in
  let g = create () in
  create_initial_hierarchy g;
  (* step1: defs *)
  deps +> List.iter (fun (src, dst) ->
    try 
      create_intermediate_directories_if_not_present g src;
      create_intermediate_directories_if_not_present g dst;
    with Assert_failure _ ->
      pr2_gen (src, dst);
  );
  (* step2: use *)
  deps +> List.iter (fun (src, dst) ->
    let src_node = (src, E.Dir) in
    let dst_node = (dst, E.Dir) in
    g +> add_edge (src_node, dst_node) Use;
  );
  g

