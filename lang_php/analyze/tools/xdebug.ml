(*s: xdebug.ml *)
(*s: Facebook copyright *)
(* Yoann Padioleau
 * 
 * Copyright (C) 2009, 2010, 2011 Facebook
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
open Common2
open Common

open Ast_php

module Ast = Ast_php

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(* 
 * Wrappers around the really good debugger/profiler/tracer for PHP:
 * 
 *  http://xdebug.org/
 * 
 * To enable xdebug, you need to add the loading of xdebug.so in one
 * of the php config .ini file, for instance add in php.ini:
 * 
 *    zend_extension=/usr/local/php/lib/php/extensions/no-debug-non-zts-20060613/xdebug.so
 * 
 * Then php -v should display something like:
 * 
 *   Zend Engine v2.2.0, Copyright (c) 1998-2007 Zend Technologies
 *     with Xdebug v2.0.3.fb1, Copyright (c) 2002-2007, by Derick Rethans
 * 
 * php -d xdebug.collect_params=3
 *  => full variable contents with the limits respected by
 *   xdebug.var_display_max_children, max_data, max_depth
 * 
 * But the dumped file can be huge:
 *  - for unit tested flib/core/ 1.8 Go 
 *  - for unit tested flib/ 5Go ...
 * 
 * so had to optimize a few things:
 * 
 * - use compiled regexp, 
 * - fast-path parser for expression. 
 * - use iterator interface instead of using lists.
 * 
 * See -index_db_xdebug and Database_php_build for the code using
 * this module.
 * See also dynamic_analysis.ml.
 * 
 *)

(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

type kind_call = 
    | FunCall of string
    | ObjectCall of string (* class *) * string (* method *)
    | ClassCall of string (* module *) * string

(* Depending on config below, some of the fields may be incomplete
 * (e.g. f_return will be None when cfg.collect_return = false *)
type call_trace = {
  f_call: kind_call;
  f_file: Common.filename;
  f_line: int;
  f_params: Ast_php.expr list;
  f_return: Ast_php.expr option;

(* f_type: *)
}

let xdebug_main_name = "xdebug_main"

type config = {
  auto_trace: int;
  trace_options: int;

  trace_format: int;
  collect_params: params_mode;
  collect_return: bool;

  var_display_max_children: int;
  val_display_max_data: int;
  var_display_max_depth: int;
}
 (* see http://xdebug.org/docs/all_settings *)
 and params_mode = 
   | NoParam
   | TypeAndArity
   | TypeAndArityAndTooltip
   | FullParam
   | FullParamAndVar
 (* with tarzan *)


let default_config = {

  auto_trace = 1;
  trace_options = 1;

  trace_format = 0;

  collect_params = FullParam;
  collect_return = true;

  var_display_max_children = 20; (* default = 128 *)
  val_display_max_data = 200; (* default = 512 *)
  var_display_max_depth = 2; (* default = 3 *)
}


(*****************************************************************************)
(* String of *)
(*****************************************************************************)

let s_of_kind_call = function
  | FunCall s -> s
  | ObjectCall (s1, s2) -> s1 ^ "->" ^ s2
  | ClassCall (s1, s2) -> s1 ^ "::" ^ s2

let string_of_call_trace x = 
  spf "%s:%d: call = %s"
    x.f_file x.f_line (s_of_kind_call x.f_call)

let intval_of_params_mode = function
  | NoParam -> 0
  | TypeAndArity -> 1
  | TypeAndArityAndTooltip -> 2
  | FullParam -> 3
  | FullParamAndVar -> 4


let hash_of_config cfg = 
  match cfg with
  {
    auto_trace = v_auto_trace;
    trace_options = v_trace_options;
    trace_format = v_trace_format;
    collect_params = v_collect_params;
    collect_return = v_collect_return;
    var_display_max_children = v_var_display_max_children;
    val_display_max_data = v_val_display_max_data;
    var_display_max_depth = v_var_display_max_depth
  } ->
    (* emacs macro generated *)
    Common.hash_of_list [
      "auto_trace", i_to_s v_auto_trace;
      "trace_options", i_to_s v_trace_options;
      "trace_format", i_to_s v_trace_format;
      "collect_params", i_to_s (intval_of_params_mode v_collect_params);
      "collect_return", if v_collect_return then "1" else "0";
      "var_display_max_children", i_to_s v_var_display_max_children;
      "val_display_max_data", i_to_s v_val_display_max_data;
      "var_display_max_depth", i_to_s v_var_display_max_depth
    ]

let cmdline_args_of_config cfg =
  hash_of_config cfg 
  +> Common.hash_to_list 
  +> List.map (fun (s, d) -> spf "-d xdebug.%s=%s" s d) 
  +> Common.join " "

(*****************************************************************************)
(* Small wrapper over php interpreter *)
(*****************************************************************************)
let php_cmd_with_xdebug_on ?(config = default_config) ~trace_file () = 
  let (d, b, e) = Common2.dbe_of_filename trace_file in

  if e <> "xt" 
  then failwith "the xdebug trace file must end in .xt";
  if Sys.file_exists trace_file && Common2.filesize trace_file > 0
  then pr2 (spf "WARNING: %s already exists, xdebug will concatenate data"
               trace_file);

  let options = cmdline_args_of_config config in
  spf "php %s -d xdebug.trace_output_dir=%s -d xdebug.trace_output_name=%s"
    options
    d
    b (* xdebug will automatically appends a ".xt" to the filename *)


let php_has_xdebug_extension () = 
  let xs = Common.cmd_to_list "php -v 2>&1" in
  xs +> List.exists (fun s -> s =~ ".*with Xdebug v.*")

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let sanitize_xdebug_expr_for_parser2 str = 

(* Str is buggy 
  let str = Str.global_replace 
    (Str.regexp "class\b") "class_xdebug" str
  in
  (* bug in xdebug output *)
  let str = Str.global_replace 
    (Str.regexp ")[ \t]*}") ");}" str
  in
  str
  *)  
(*
  let str = Pcre.replace ~pat:"\\?\\?\\?"  ~templ:"..." str in
  let str = Pcre.replace ~pat:"class"  ~templ:"class_xdebug" str in
  let str = Pcre.replace 
    ~pat:"resource\\([^)]*\\) of type \\([^)]*\\)"  
    ~templ:"resource_xdebug" str
  in

  (* bug in xdebug output *)
  let str = Pcre.replace ~pat:"([^{ \t])[ \t]+}"   ~itempl:(Pcre.subst "$1;}") str in
  str
*)
  failwith "TODO: deprecated code, we removed the dependencies to PCRE"

let sanitize_xdebug_expr_for_parser a = 
  Common.profile_code "sanitize" (fun () -> sanitize_xdebug_expr_for_parser2 a)


(* bench:
 * on toy.xt:
 *  - 0.157s with regular expr parser
 *  - 0.002 with in memory parser that dont call xhp, tag file info, etc
 * on flib_core.xt: 44s in native mode
 *)
let parse_xdebug_expr2 s = 
  (* Parse_php.expr_of_string s *)
  Parse_php.xdebug_expr_of_string s

let parse_xdebug_expr a = 
  Common.profile_code "Xdebug.parse" (fun () -> parse_xdebug_expr2 a)


(*****************************************************************************)
(* Parsing regexps *)
(*****************************************************************************)

(* examples:
 *   0.0009      99800   -> {main}() /home/pad/mobile/project-facebook/pfff/tests/xdebug/basic_values.php:0
 *   0.0009      99800     -> main() /home/pad/mobile/project-facebook/pfff/tests/xdebug/basic_values.php:41
 *   0.0006      97600     -> A->__construct(4) /home/pad/mobile/project-facebook/pfff/tests/xdebug/object_values.php:24
 * TODO               ModuleStack::current()
 * 
 * update: can also get:
 * 
 * 1.9389  140618888 -> strtolower() /data/users/pad/www-git/flib/web/haste/transform.php(77) : regexp code:1
 *
 *)
let regexp_in = 
  Str.regexp 
    ("\\(" ^ (* 1, everything before the arrow *)
       "[ \t]+" ^
       "\\([0-9]+\\.[0-9]+\\)[ \t]+\\([0-9]+\\)" ^ (* 2 3, time and nbcall? *)
       "[ \t]+" ^
        "\\)" ^ (* end of before arrow *) 
       "->[ \t]+" ^
       "\\([^(]+\\)" ^ (* 4, funcname or methodcall *)
       "(\\(.*\\)) " ^ (* 5, arguments *)
       "\\(/[^:]*\\)" ^ (* 6, filename. was /.* but can get weird lines
                         * such as above with the 'regexp code:1' which 
                         * then got ':' matched at the wrong place.
                         *)
       ":" ^
       "\\([0-9]+\\)" ^ (* 7, line *)
       "")
          

(* examples:
 *         >=> 8
 *)

let regexp_out = 
  Str.regexp 
    ("\\([ \t]+\\)" ^ (* 1, spacing *)
     ">=> " ^
     "\\(.*\\)" (* 2, returned expression *)
    )

(* example:
 *   0.0009      99800   -> {main}() /home/pad/mobile/project-facebook/pfff/tests/xdebug/basic_values.php:0
 *)
let regexp_special_main = 
  Str.regexp ".*-> {main}()"


let regexp_last_time = 
  Str.regexp (
    "^[ \t]+[0-9]+\\.[0-9]+[ \t]+[0-9]+$"
  )

let regexp_meth_call = 
   Str.regexp (
   "\\([A-Za-z_0-9]+\\)->\\(.*\\)"
   )

let regexp_class_call = 
   Str.regexp (
   "\\([A-Za-z_0-9]+\\)::\\(.*\\)"
   )
let regexp_fun_call =
   Str.regexp (
   "[A-Za-z_0-9]+$"
   )

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

(* Can not have a parse_dumpfile, because it is usually too big *)
let iter_dumpfile2 
    ?(config=default_config) 
    ?(show_progress=true) 
    ?(fatal_when_exn=false)
   callback file = 

  pr2 (spf "computing number of lines of %s" file);
  let nblines = Common2.nblines_with_wc file in
 
  pr2 (spf "nb lines = %d" nblines);
  let nb_fails = ref 0 in

  Common2.execute_and_show_progress ~show:show_progress nblines (fun k ->
  Common.with_open_infile file (fun (chan) ->

    let stack = ref [] in
    let line_no = ref 0 in

    try 
      while true do
        let line = input_line chan in
        incr line_no;

        k ();
        
        match line with
        (* most common case first *)
        | _ when line ==~ regexp_in -> 
            (* pr2 "IN:"; *)
            let (before_arrow, _time, _nbcall, call, args, file, lineno) = 
              Common.matched7 line 
            in

            let trace_opt = 
            (try 
              let kind_call = 
                match () with
                | _ when call ==~ regexp_meth_call ->
                    let (sclass, smethod) = Common.matched2 call in
                    ObjectCall(sclass, smethod)
                | _ when call ==~ regexp_class_call -> 
                    let (sclass, smethod) = Common.matched2 call in
                    ClassCall(sclass, smethod)
                | _ when call ==~ regexp_fun_call -> 
                    FunCall(call)

                (* We do not want to expose such funcall to the callback,
                 * but we to parse it and match its return. It will be
                 * filtered later.
                 *)
                | _ when call = "{main}" -> 
                    FunCall(xdebug_main_name)
                | _ -> 
                    failwith ("not a funcall: " ^ call)
              in
              (* require/include calls have not a valid PHP syntax in xdebug 
               * ouput, e.g. require_once(/data/users/pad/www-git/foo.php) 
               * which do not contain enclosing '"' so have to 
               * filter them here.
               *)
              (match kind_call with
              | FunCall "require_once" 
              | FunCall "include_once" 
              | FunCall "include" 
              | FunCall "require" 
                -> None

              | _ ->

                  let args = 
                    if config.collect_params = NoParam
                    then []
                    else 
                      let str = sanitize_xdebug_expr_for_parser args in
                      let str = "foo(" ^ str ^ ")" in
                      let expr = parse_xdebug_expr str in

                      match expr with
                      | Call (Id name, args_paren) ->
                        assert(Ast.str_of_name name = "foo");
                        Ast.unparen args_paren 
                        +> Ast.uncomma 
                        +> List.map (function
                        | Arg e -> e
                        | _ -> raise Impossible
                        )
                      | _ -> raise Impossible
                  in

                  let trace = {
                    f_call = kind_call;
                    f_file = file;
                    f_line = s_to_i lineno;
                    f_params = args;
                    f_return = None; (* filled later for regexp_out *)
                  }
                  in
                  Some trace
              )
            with 
            | Timeout -> raise Timeout
            | exn ->
               pr2(spf "php parsing pb: exn = %s, s = %s" 
                      (Common.exn_to_s exn) args);
               incr nb_fails;
               if fatal_when_exn then raise exn 
               else 
                 None
            )
            in
            trace_opt +> Common.do_option (fun trace -> 
              if not config.collect_return then
                (try 
                    if trace.f_call = FunCall(xdebug_main_name) 
                    then ()
                    else 
                      callback trace

                  with 
                  | Timeout -> raise Timeout
                  | exn ->
                    pr2(spf "callback pb: exn = %s, line = %s" 
                           (Common.exn_to_s exn) line);
                    raise exn
                )
              else 
                Common.push2 (String.length before_arrow, trace) stack;
            )
              


        | _ when line ==~ regexp_out -> 
            (* pr2 "OUT:"; *)
            let (before_arrow, return_expr) = Common.matched2 line in
            let str = sanitize_xdebug_expr_for_parser return_expr in

            (* the return line is indented with an extra space, so have
             * to correct it here with the -1 *)
            let depth_here = String.length before_arrow - 1 in
            (try 
              let expr = parse_xdebug_expr str  in

              match !stack with
              | [] -> failwith "empty call stack"
              | (depth_call, trace)::rest -> 
                  (match depth_call <=> depth_here with
                  | Common2.Equal ->
                      stack := rest;

                      let caller = trace.f_call in
                      if caller = FunCall(xdebug_main_name) 
                      then ()
                      else 
                        (try 
                            let trace = { trace with f_return = Some expr } in
                            callback trace
                          with 
                          | Timeout -> raise Timeout
                          | exn ->
                            pr2(spf "callback pb: exn = %s, line = %s" 
                                   (Common.exn_to_s exn) line);
                            raise exn
                        )
                  | Common2.Inf ->
                      raise Todo
                  | Common2.Sup -> 
                      raise Todo
                  )
              with
              | Timeout -> raise Timeout
              | exn ->
                pr2(spf "php parsing pb: exn = %s, str = %s, line = %d " 
                       (Common.exn_to_s exn) str !line_no);
                incr nb_fails;
                if fatal_when_exn then raise exn;
            )


        | _ when line =~ "^TRACE" -> ()
        | _ when line ==~ regexp_last_time -> ()


        | _ when line = "" -> ()
        | _ -> 
            (* TODO error recovery ? *)
            pr2 ("parsing pb: " ^ line);
            incr nb_fails;

      done
    with End_of_file -> ()

  ));
  pr2 (spf "nb xdebug parsing fails = %d" !nb_fails);
  ()


let iter_dumpfile ?config ?show_progress ?fatal_when_exn a b = 
  Common.profile_code "Xdebug.iter_dumpfile" (fun () -> 
    iter_dumpfile2 ?config ?show_progress ?fatal_when_exn a b)
(*e: xdebug.ml *)
