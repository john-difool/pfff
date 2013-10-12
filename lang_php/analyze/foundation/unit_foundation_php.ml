open Common
open OUnit

module Ast = Ast_php
module A = Annotation_php
module Db = Database_code
module E = Database_code
module G = Graph_code

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*****************************************************************************)
(* Unit tests *)
(*****************************************************************************)

(*---------------------------------------------------------------------------*)
(* Ast simple *)
(*---------------------------------------------------------------------------*)

let ast_simple_unittest =
  "ast_simple regression files" >:: (fun () ->
    let dir1 = Filename.concat Config_pfff.path "/tests/php/parsing" in
    let dir2 = Filename.concat Config_pfff.path "/tests/php/semantic" in
    let files =
      (Common2.glob (spf "%s/*.php" dir1) ++ Common2.glob (spf "%s/*.php" dir2))
      (* TODO: fix those ! *)
      +> Common.exclude (fun file -> file =~ ".*/namespace_test*")
    in
    files +> List.iter (fun file ->
      try
        let cst = Parse_php.parse_program file in
        let _ast = Ast_php_simple_build.program cst in
        ()
      with exn ->
        assert_failure (spf "it should correctly parse %s, exn = %s"
                           file (Common.exn_to_s exn))
      )
    )

(*---------------------------------------------------------------------------*)
(* Defs/uses *)
(*---------------------------------------------------------------------------*)

let defs_uses_unittest =
  "defs_uses" >::: [
    "functions uses" >:: (fun () ->
      let file_content = "
foo1();
" in
      let ast = Parse_php.program_of_string file_content in
      let uses = Defs_uses_php.uses_of_any (Ast.Program ast) in
      let uses_strings =
        uses +> List.map (fun (name, kind) -> Ast.str_of_name name) in
      assert_equal
        (sort ["foo1"])
        (sort uses_strings);
    );

    "classes uses" >:: (fun () ->
      let file_content = "
new Foo1();
if($x instanceof Foo2) { }

echo Foo3::Cst;
echo Foo4::$var;
Foo5::method();
Foo6::$f();

class X1 extends Foo7 { }
class X2 implements Foo8 { }
try { } catch(Foo9 $x) { }
function foo1(Foo10 $x) { }

$x = <x:xhp1></x:xhp1>;
$x = <x:xhp2/>;
" in
      let ast = Parse_php.program_of_string file_content in
      let uses = Defs_uses_php.uses_of_any (Ast.Program ast) in
      let str_of_name = function
        | Ast.XName [Ast.QI (Ast.Name (s, _))] -> s
        | Ast.XName [Ast.QI (Ast.XhpName (xhp_tag, _))] ->
            Common.join ":" xhp_tag
        | _ -> raise Impossible
      in
      let uses_strings =
        uses +> List.map (fun (name, kind) -> str_of_name name) in

      let classes =
        (Common2.enum 1 10) +> List.map (fun i -> spf "Foo%d" i) in
      let xhp_classes =
        (Common2.enum 1 2) +> List.map (fun i -> spf "x:xhp%d" i) in
      assert_equal
        (sort (classes ++ xhp_classes))
        (sort uses_strings);
    );
  ]

(*---------------------------------------------------------------------------*)
(* Tags *)
(*---------------------------------------------------------------------------*)
let tags_unittest =
    "tags_php" >::: [

      "basic tags" >:: (fun () ->
        let file_content = "
            function foo() { }
            class A { }
            interface B { }
            trait C { }
            const CST = 1;
            define('OldCst',1);
            type T = int;
        "
        in
        let tmpfile = Parse_php.tmp_php_file_from_string file_content in
        let tags =
          Tags_php.php_defs_of_files_or_dirs ~verbose:false [tmpfile] in
        (match tags with
        | [file, tags_in_file] ->
            assert_equal tmpfile file;
            let xs = tags_in_file +> List.map (fun x ->
              x.Tags_file.tagname, x.Tags_file.kind
            ) in
            assert_equal ~msg:"it should contain the right entries" [
              "foo", Db.Function;
              "A", Db.Class Db.RegularClass;
              "B", Db.Class Db.Interface;
              "C", Db.Class Db.Trait;
              "CST", Db.Constant;
              "OldCst", Db.Constant;
              "T", Db.Type;
            ]
            xs
        | _ ->
            assert_failure "The tags should contain only one entry for one file"
        )
      );

      "method tags" >:: (fun () ->
        let file_content = "
           class A {
              function a_method() { }
              function ambiguous_with_function() { }
              function ambiguous_with_another_class() { }
           }
           class B {
              function ambiguous_with_another_class() { }
           }
           function ambiguous_with_function() { }
        " in
        let tmpfile = Parse_php.tmp_php_file_from_string file_content in
        let tags =
          Tags_php.php_defs_of_files_or_dirs ~verbose:false [tmpfile] in
        (match tags with
        | [file, tags_in_file] ->
            assert_equal tmpfile file;
            let xs = tags_in_file +> List.map (fun x ->
              x.Tags_file.tagname, x.Tags_file.kind
            ) in
            (* we now generate two tags per method, one for 'a_method',
             * and one for 'A::a_method', but only if there is not somewhere
             * a function called a_method() or another class with the same
             * method name.
             *)
            assert_equal ~msg:"The tags should contain the right entries" [
              "A", Db.Class Db.RegularClass;
              "A::a_method", Db.Method Db.RegularMethod;
              (* this tag is safe to generate, no ambiguity *)
              "a_method", Db.Method Db.RegularMethod;
              "A::ambiguous_with_function", Db.Method Db.RegularMethod;
              "A::ambiguous_with_another_class", Db.Method Db.RegularMethod;
              "B", Db.Class Db.RegularClass;
              "B::ambiguous_with_another_class", Db.Method Db.RegularMethod;
              "ambiguous_with_function", Db.Function;
            ]
            xs

        | _ ->
            assert_failure "The tags should contain only one entry for one file"
        )
      );

      "magic tags" >:: (fun () ->
        let file_content = "
           class A {
              function yieldSomething() { }
              function prepareSomethingElse() { }
           }
        " in
        let tmpfile = Parse_php.tmp_php_file_from_string file_content in
        let tags =
          Tags_php.php_defs_of_files_or_dirs ~verbose:false [tmpfile] in
        (match tags with
        | [file, tags_in_file] ->
            assert_equal tmpfile file;
            let xs = tags_in_file +> List.map (fun x ->
              x.Tags_file.tagname, x.Tags_file.kind
            ) in
            let desired = [
              "A", Db.Class Db.RegularClass;
              "A::yieldSomething", Db.Method Db.RegularMethod;
              "yieldSomething", Db.Method Db.RegularMethod;
              "A::genSomething", Db.Method Db.RegularMethod;
              "genSomething", Db.Method Db.RegularMethod;
              "A::prepareSomething", Db.Method Db.RegularMethod;
              "prepareSomething", Db.Method Db.RegularMethod;
              "A::getSomething", Db.Method Db.RegularMethod;
              "getSomething", Db.Method Db.RegularMethod;
              "A::prepareSomethingElse", Db.Method Db.RegularMethod;
              "prepareSomethingElse", Db.Method Db.RegularMethod;
              "A::genSomethingElse", Db.Method Db.RegularMethod;
              "genSomethingElse", Db.Method Db.RegularMethod;
            ]
            in
            assert_equal ~msg:"Tags should contain entries for the right magic methods"
              desired
              xs

        | _ ->
            assert_failure "The tags should contain only one entry for one file"
        )
      );

      "xhp tags" >:: (fun () ->
        let file_content = "class :x:foo { }" in
        let tmpfile = Parse_php.tmp_php_file_from_string file_content in
        let tags =
          Tags_php.php_defs_of_files_or_dirs ~verbose:false [tmpfile] in
        let all_tags = tags +> List.map snd +> List.flatten in
        assert_bool
          ~msg:"it should contain an entry for the :x:... classname form"
          (all_tags +> List.exists (fun t ->
            t.Tags_file.tagname =$= ":x:foo"));
        assert_bool
          ~msg:"it should contain an entry for the x:... classname form"
          (all_tags +> List.exists (fun t ->
            t.Tags_file.tagname =$= "x:foo"));
      );
    ]

(*---------------------------------------------------------------------------*)
(* Codegraph *)
(*---------------------------------------------------------------------------*)
let codegraph_unittest = 
  "codegraph_php" >::: [

    "basic class def/uses" >:: (fun () ->
      let file_content = "
class A {
 public $fld;
 public function test_field() {
   return $this->fld;
 }
}"
      in
      let tmpfile = Parse_php.tmp_php_file_from_string file_content in
      let g = Graph_code_php.build 
        ~verbose:false ~logfile:"/dev/null" (Right [tmpfile]) [] in
      let src = ("A.$fld", E.Field) in
      let pred = G.pred src G.Use g in
      assert_equal
        ~msg:"it should link the use of a PHP field to its def"
        pred
        ["A.test_field", E.Method E.RegularMethod];
    );

    "required xhp field" >:: (fun () ->
      let file_content = "
        class :x:required {
          attribute
          int req_int @required;
}
"
      in
      let tmpfile = Parse_php.tmp_php_file_from_string file_content in
      let g = Graph_code_php.build 
        ~verbose:false ~logfile:"/dev/null" (Right [tmpfile]) [] in
      let field = (":x:required.req_int=", E.Field) in
      let nodeinfo = G.nodeinfo field g in
      let props = nodeinfo.G.props in
      assert_equal
        ~msg:"it should annotate xhp required field"
        props
        [Db.Required]
    );

    "regression files" >:: (fun () ->
      let dir = Filename.concat Config_pfff.path "/tests/php/codegraph" in
      let skip_list = Skip_code.load (Filename.concat dir "skip_list.txt") in
      let logfile = Filename.concat dir "pfff_test.log" in
      let expected_logfile = Filename.concat dir "pfff_test.exp" in
      let g = Graph_code_php.build 
        ~verbose:false ~readable_file_format:true ~logfile
        (Left dir) skip_list in

      let xs = Common2.unix_diff logfile expected_logfile in
      assert_bool
        ~msg:("it should generate the right errors in pfff_test.log, diff = "^
                 (Common.join "\n" xs))
        (null xs);

      let src = (":x:misc.xstr=", E.Field) in
      let pred = G.pred src G.Use g in
      assert_equal
        ~msg:"it should link the use of an xhp attribute to its def"
        pred
        ["xhp_use.php", E.File];

      let src = (":x:super.superstr=", E.Field) in
      let pred = G.pred src G.Use g in
      assert_equal
        ~msg:"it should link the use of an xhp attribute to its def"
        pred
        ["xhp_use.php", E.File];


    )
  ]
(*---------------------------------------------------------------------------*)
(* Annotations *)
(*---------------------------------------------------------------------------*)

let annotation_unittest =
  "annotation_php" >::: [
    "data provider annotations" >:: (fun () ->
      let file_content = "
        class A {
          // @dataProvider provider
          public function foo() { }
          public function provider() { }
          // @dataProvider B::provider2
          public function foo2() { }
          /**
           * @dataProvider provider3
           */
          public function foo3() { }
          /*
           * @dataProvider provider4
           */
          public function foo4() { }
}
"
      in
      let tmpfile = Parse_php.tmp_php_file_from_string file_content in
      let (ast_with_comments, _stat) = Parse_php.parse tmpfile in
      let annots =
        Annotation_php.annotations_of_program_with_comments ast_with_comments
          +> List.map fst
      in
      assert_equal ~msg:"should have the DataProvider annotations"
        (sort [A.DataProvider (A.Method "provider");
               A.DataProvider (A.MethodExternal ("B", "provider2"));
               A.DataProvider (A.Method "provider3");
               A.DataProvider (A.Method "provider4");
        ])
        (sort annots);
    );
  ]

(*---------------------------------------------------------------------------*)
(* Include use/def *)
(*---------------------------------------------------------------------------*)

let include_unittest =
  "include_require" >::: (
      let env = {
        Env_php.global_arrays = Common.hash_of_list [
          "_SERVER", Common.hash_of_list [
            "PHP_ROOT", "/home/foo/www";
          ];
        ];
        Env_php.constants = Common.hash_of_list [];
        Env_php.globals = Common.hash_of_list [];
        Env_php.globals_specials = (fun s dir -> None);
      }
      in [
      (* I was previously using Filename.concat in include_require_php.ml
       * which generate paths like a/b//c/foo.php which is annoying
       * and can confuse some of our analysis. Check that no regression
       * on this issue.
       *)
      "resolving path" >:: (fun () ->
        let file = "
        require_once $_SERVER['PHP_ROOT'].'/lib/alerts/alerts.php';
        "
        in
        let ast = Parse_php.program_of_string file in
        let incs = Include_require_php.top_increq_of_program ast in
        match incs with
        | [(_inc_kind,_tok, incexpr)] ->
            let path =
              Include_require_php.resolve_path (env, "/") incexpr in
            assert_equal
              (Some "/home/foo/www/lib/alerts/alerts.php")
              path;

        | _ ->
            assert_failure
              "wrong number of elements returned by increq_of_program"
      );

      ])

(*---------------------------------------------------------------------------*)
(* Final suite *)
(*---------------------------------------------------------------------------*)

let unittest =
  "foundation_php" >::: [
    ast_simple_unittest;
    defs_uses_unittest;
    tags_unittest;
    codegraph_unittest;
    annotation_unittest;
    include_unittest;
  ]
