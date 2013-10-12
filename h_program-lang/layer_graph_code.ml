(* Yoann Padioleau
 *
 * Copyright (C) 2013 Facebook
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

module G = Graph_code

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
 * Module to help visualize dependencies: is an entity an entry
 * point of the program or one of its leaves.
 * 
 *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let kind_of_rank ~max_total n =
  let percent = Common2.pourcent n max_total in
  let percent_round = (percent / 10) * 10 in
  spf "cover %d%%" percent_round
  

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let gen_heatmap_layer g hentity_to_rank  ~output =

  let group_by_file =
    hentity_to_rank 
    +> Common.hash_to_list
    +> Common.map_filter (fun (node, v) ->
      try 
        let file = G.file_of_node node g in
        Some (file, (node, v))
      with Not_found -> None
    ) 
    +> Common.group_assoc_bykey_eff
  in
  let xs = hentity_to_rank +> Common.hash_to_list +> List.map snd in
  let max_total = Common2.maximum xs in

  let layer = { Layer_code.
    title = "Graph code rank";
    description = "Associate a rank to each entity according to its depth
in the Use graph";
    files = group_by_file +> List.map (fun (file, nodes_and_rank) ->
      let max_file = 
        nodes_and_rank +> List.map snd +> Common2.maximum
      in

      file, 
      { Layer_code.
        micro_level = nodes_and_rank +> List.map (fun (n, v) ->
          let info = G.nodeinfo n g in
          let line = info.Graph_code.pos.Parse_info.line in
          line, kind_of_rank v ~max_total
        );
        macro_level = [
          kind_of_rank max_file ~max_total, 1.
        ];
      }
    );
    kinds = Layer_code.heat_map_properties;
  }
  in
  Layer_code.save_layer layer output

(*****************************************************************************)
(* Actions *)
(*****************************************************************************)

let actions () = [
  "-gen_bottomup_layer", " <graph_file> <output>",
  Common.mk_action_2_arg (fun graph_file output ->
    let g = G.load graph_file in
    let hrank = G.bottom_up_numbering g in
    let (d,_,_) = Common2.dbe_of_filename graph_file in
    let output = Common2.filename_of_dbe (d, "layer_graph_code", "json") in
    gen_heatmap_layer g hrank output;
  );
]
