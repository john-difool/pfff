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

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*
 * - zamcov
 * - mlcov
 * - #trace
 * - ocamldebug?
 * - ?
 *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(*****************************************************************************)
(* API *)
(*****************************************************************************)

let basename_coverage_to_readable_coverage xs root =
  
  let files = Lib_parsing_ml.find_ml_files_of_dir_or_files [root] in
  let files = files +> List.map (Common.filename_without_leading_path root) in
  (* use the Hashtbl.find_all property of this hash *)
  let h = Hashtbl.create 101 in
  files +> List.iter (fun file ->
    Hashtbl.add h (Filename.basename file) file
  );

  xs +> List.map (fun (file, cover) ->
    match Hashtbl.find_all h file with
    | [] ->
      failwith (spf "could not find basename %s in directory %s" file root)
    | [x] -> x, cover
    | x::y::xs ->
      failwith (spf "ambiguity on %s (%s, %s, ...)" file x y)
  )

