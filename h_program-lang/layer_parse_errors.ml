(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
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

open Statistics_parsing

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(* todo: do some generic red_green_and_heatmap helpers? so can factorize
 * code with layer_coverage.ml
 *)

(*****************************************************************************)
(* Helper *)
(*****************************************************************************)

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let gen_red_green_layer ~root ~output stats =
  let root = Common2.relative_to_absolute root in

  let layer = { Layer_code.
    title = "Parsing errors (red/green)";
    description = "";
    files = stats +> List.map (fun stat ->
     let file = 
       stat.filename +> Common2.relative_to_absolute
         +> Common.filename_without_leading_path root
     in
      
      file,
      { Layer_code.
        micro_level = []; (* TODO use problematic_lines *)
        macro_level = [
          (if stat.bad > 0
          then "bad"
          else "ok"
          ), 1.
        ];
      }
    );
    kinds = Layer_code.red_green_properties;
  }
  in
  Layer_code.save_layer layer output

let gen_heatmap_layer ~root ~output stats =
  let root = Common2.relative_to_absolute root in

  let layer = { Layer_code.
    title = "Parsing errors (heatmap)";
    description = "lower is better";
    files = stats +> List.map (fun stat ->
     let file = 
       stat.filename +> Common2.relative_to_absolute
         +> Common.filename_without_leading_path root
     in
     let covered = stat.correct in
     let not_covered = stat.bad in

     let percent = 
        try 
          Common2.pourcent_good_bad not_covered covered
       with Division_by_zero -> 0
     in
      
      file,
      { Layer_code.
        micro_level =
          stat.problematic_lines +> List.map (fun (_strs, lineno) ->
            lineno, "bad"
          );
        macro_level = [
          (let percent_round = (percent / 10) * 10 in
          spf "cover %d%%" percent_round
          ),
          1.
        ];
      }
    );
    kinds = Layer_code.heat_map_properties;
  }
  in
  Layer_code.save_layer layer output


