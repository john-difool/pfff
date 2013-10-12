(* $Id: netdb.mlp 1003 2006-09-24 15:17:15Z gerd $
 * ----------------------------------------------------------------------
 *
 *)


let net_db_dir = "/home/pad/packages/Linux/stow/ocaml-3.12/lib/ocaml/site-lib/netstring" ;;

let net_db_hash = Hashtbl.create 20 ;;

let file_db_is_enabled = ref true ;;

let read_db name =
  try
    Marshal.from_string (Hashtbl.find net_db_hash name) 0
  with
      Not_found ->
	if !file_db_is_enabled then begin
	  let filename = Filename.concat net_db_dir name ^ ".netdb" in
	  if Sys.file_exists filename then begin
	    let ch = open_in_bin filename in
	    try
	      let v = input_value ch in
	      close_in ch;
	      v
	    with exn ->
	      close_in ch;
	      raise exn
	  end
	  else
	    failwith ("Ocamlnet: Cannot find the lookup table `" ^ name ^ 
		      "' which is supposed to be available as file " ^ 
		      filename)

	end
	else 
	  failwith ("Ocamlnet: The lookup table `" ^ name ^
		    "' is not compiled into the program, and access to " ^
		    "the external file database is disabled")
;;


let exists_db name =
  Hashtbl.mem net_db_hash name || (
    !file_db_is_enabled && (
      let filename = Filename.concat net_db_dir name ^ ".netdb" in
      Sys.file_exists filename
    ))
;;


let set_db name value =
  Hashtbl.replace net_db_hash name value
;;


let disable_file_db () =
  file_db_is_enabled := false
;;
