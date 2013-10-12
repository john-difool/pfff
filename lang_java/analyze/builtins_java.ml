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
module G = Graph_code

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
 * Extracing package/class definitions from a set of sources.
 *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

  
let gen_package_file_with_class_defs pr xs g =

  let rec aux depth ((str, kind) as current) =
    let xs = Common.split "\\." str in
    match kind with
    | E.Class _ ->
        let str = Common2.list_last xs in
        pr (spf "%sclass %s {" (Common2.n_space depth) str);
        List.iter (aux (depth + 2)) (G.children current g);
        pr (spf "%s}" (Common2.n_space depth));
    | E.File ->
        List.iter (aux depth) (G.children current g)
    | E.Constant
    | E.Field ->
        let str = Common2.list_last xs in
        pr (spf "%sint %s;" (Common2.n_space depth) str);

    | E.Method _ 
    | E.ClassConstant
        -> ()
        
    | _ -> ()
  in
  List.iter (aux 0) xs

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let extract_from_sources ~skip_list ~src ~dst =
  let g = Graph_code_java.build ~verbose:false ~only_defs:true src skip_list in

  Common.command2("mkdir -p " ^ dst);

  let rec aux current = 
    let xs = G.children current g in
    
    let classes_or_files =
      xs +> List.filter (function 
      | _, E.Class _ -> true
      | _, E.File -> true
      | _ -> false 
      )
    in
    let subpackages = 
      xs +> List.filter (function 
      | _, E.Package -> true
      | _ -> false 
      )
    in
    (match current, classes_or_files with
    | _, [] -> ()
    | (str, E.Package), xs ->
        let filename = Filename.concat dst (str ^ ".java") in
        pr2 (spf "generating %s" filename);
        Common.with_open_outfile filename (fun (pr, _chan) ->
          let pr s = pr (s ^ "\n") in
          pr (spf "package %s;" str);
          gen_package_file_with_class_defs pr xs g
        )
    | _ ->
        ()
    );
    List.iter aux subpackages;

  in
  aux G.root
