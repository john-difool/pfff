(*s: ui_layers.ml *)
(*s: Facebook copyright *)
(* Yoann Padioleau
 * 
 * Copyright (C) 2010-2012 Facebook
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
(*e: Facebook copyright *)
open Common

open Model2
module M = Model2
module Controller = Controller2

module L = Layer_code

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

let choose_layer ~root layer_title_opt dw_ref =
  pr2 "choose_layer()";
  let dw = !dw_ref in

  let original_layers = dw.M.layers.L.layers +> List.map fst in
  let layers_idx = 
    Layer_code.build_index_of_layers 
      ~root
      (original_layers +> List.map (fun layer ->
        layer, 
        match layer_title_opt with
        | None -> false
        | Some title -> title =$= layer.L.title
      ))
  in
  dw_ref := 
    Model2.init_drawing 
      ~width:dw.width
      ~height:dw.height
      ~width_minimap:dw.width_minimap
      ~height_minimap:dw.height_minimap
      dw.treemap_func 
      dw.dw_model 
      layers_idx
      [root]
      root;
  View_mainmap.paint !dw_ref;
  !Controller._refresh_da ();
  !Controller._refresh_legend ();
  ()

(*e: ui_layers.ml *)
