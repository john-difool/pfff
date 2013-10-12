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

module FT = File_type

(*****************************************************************************)
(* Filenames *)
(*****************************************************************************)

let find_source_files_of_dir_or_files xs = 
  Common.files_of_dir_or_files_no_vcs_nofilter xs 
  +> List.filter (fun filename ->
    match File_type.file_type_of_file filename with
    | FT.PL (FT.C ("l" | "y")) -> false
    | FT.PL (FT.C _) -> true
    | _ -> false
  ) +> Common.sort

