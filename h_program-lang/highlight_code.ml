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
open Common

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(* 
 * Emacs-like font-lock mode, or Source-insight like display.
 * 
 * This file contains the generic part that is programming language
 * independent. See highlight_xxx.ml for the code specific to the xxx
 * programming language.
 * 
 * This source code viewer is based on good semantic information, 
 * not fragile regexps (as in emacs) or partial parsing 
 * (as in source-insight, probably because they call cpp).
 *  
 * Augmented visual, augmented intellect, see what can not see, like in
 * movies where HUD show invisible things.
 * 
 * history: 
 * Some code such as the visitor code was using Emacs_mode_xxx
 * visitors before, but now we use directly the raw visitor, cos 
 * emacs_mode_xxx was not a big win as we must colorize
 * and so visit and so get hooks for almost every programming constructs.
 * 
 * Moreover there was some duplication, such as for the different
 * categories: I had notes in emacs_mode_xxx and also notes in this file
 * about those categories like yacfe_imprecision, cpp, etc. So
 * better and cleaner to put all related code in the same file.
 * 
 * 
 * Why better to have such visualisation ? cf via_pram_readbyte example:
 * - better see that use global via1, and that global to module
 * - better see local macro
 * - better see that some func are local too, the via_pram_writebyte
 * - better see if local, or parameter
 * - better see in comments that important words such as interrupts, 
 *   and disabled, and must
 * 
 * 
 * SEMI do first like gtk source view
 * SEMI do first like emacs
 * SEMI do like my pad emacs mode extension
 * SEMI do for yacfe specific stuff
 *
 * less: level of font-lock-mode ? so can colorify a lot the current function
 * and less the rest (so maybe avoid some of the bugs of GText ? 
 * 
 * Take more ideas from Source Insight ?
 *  - variable size parens depending on depth of nestedness
 *  - do same for curly braces ?
 * 
 * TODO estet: I often revisit in very similar way the code, and do
 * some matching to know if pointercall, methodcall, to know if
 * prototype or decl extern, to know if typedef inside, or structdef 
 * inside. Could
 * perhaps define helpers so not redo each time same things ?
 * 
 * estet?: redundant with - place_code ?  - entity_c ?
 *)

(*****************************************************************************)
(* Types helpers *)
(*****************************************************************************)

(* will be italic vs non-italic (could be large vs small ? or bolder ? *)
type usedef = 
  | Use 
  | Def

(* colors will be adjusted (degrade de couleurs) (could also do size? *)
type place = 
  | PlaceLocal
  | PlaceSameDir
  | PlaceExternal
  (* | ReallyExternal   | PlaceCloseHeader *)

  (* will be in a lighter color, almost like wheat, so know we don't have
   * information on it. Could highlight in Red because it's
   * quite similar to an error.
   *)
  | NoInfoPlace


(* will be underlined or strikedthrough *)
type def_arity = 
  | UniqueDef
  | DoubleDef
  | MultiDef

  | NoDef

(* will be different colors *)
type use_arity = 
  | NoUse

  | UniqueUse
  | SomeUse
  | MultiUse
  | LotsOfUse
  | HugeUse


type use_info = place * def_arity * use_arity
type def_info = use_arity
type usedef2 = 
  | Use2 of use_info
  | Def2 of def_info

(*****************************************************************************)
(* Main type *)
(*****************************************************************************)

(* coupling: if add constructor, don't forget to add its handling in 2 places
 * below, for its color and associated string representation.
 * 
 * Also if it's a new kind of entity, you'll probably have to
 * extend is_entity_def_category below (which in turn is
 * used for instance in visual/parsing.ml and its
 * rewrite_categ_using_entities function.
 * 
 * If you look at usedef below, you should get all the way C programmer
 * can name things: 
 *   - macro, macrovar
 *   - functions
 *   - variables (global/param/local)
 *   - typedefs, structname, enumname, enum, fields
 *   - labels
 * But at the user site, can see only if
 *  - FunCallOrMacroCall
 *  - VarOrEnumValOrMacroVar
 *  - labels
 *  - field
 *  - tag (struct, union, enum)
 *  - typedef
 *)

(* color, foreground or background will be changed *)
type category =  

  | Comment

  (* pad addons *)
  | Number | Boolean 
  | Null

  | String | Regexp

  (* classic emacs mode *)
  | Keyword  (* SEMI multi *)
  | KeywordConditional
  | KeywordLoop

  | KeywordExn
  | KeywordObject
  | KeywordModule

  | Builtin
  | BuiltinCommentColor (* e.g. for "pr", "pr2", "spf". etc *)
  | BuiltinBoolean (* e.g. "not" *)

  | Operator (* TODO multi *)
  | Punctuation
     
  (* functions, macros. By default global scope (macro can have local
   * but not that used), so no need to like for variables and have a
   * global/local dichotomy of scope. (But even if functions are globals,
   * still can have some global/local dichotomy but at the module level.
   *)
  | Function of usedef2
  | FunctionDecl of def_info

  (* variables *)
  | Global of usedef2

  | Class of usedef2 (* also valid for struct ? *)
  | Field of usedef2
  | Method of usedef2
  | StaticMethod of usedef2

  | Macro of usedef2
  | MacroVar of usedef2

  | StructName of usedef
  (* ClassName of place ... *)

  | EnumName of usedef
  | EnumValue of usedef


  (* types *)
  | TypeDef of usedef

  (* ocaml *)
  | ConstructorDef of def_info
  | ConstructorUse of use_info
  | ConstructorMatch of use_info

  | Module of usedef
  (* misc *)
  | Label of usedef

  (* haskell *)
  | FunctionEquation


  (* semantic information *)
  | BadSmell

  (* could reuse Global (Use2 ...) but the use of refs is not always
   * the use of a global. Moreover using a ref in OCaml is really bad
   * which is why I want to highlight it specially.
   *)
  | UseOfRef 

  | PointerCall (* a.k.a dynamic call *)
  | CallByRef 
  | ParameterRef

  | IdentUnknown

  (* kind of specific case of Global of Local which we know are really 
   * really local. Don't really need a def_arity and place here. *)
  | Local     of usedef
  | Parameter of usedef


  | TypeVoid
  | TypeInt
  | TypeMisc (* e.g. cast expressions *)

  (* module/cpp related *)
  | Ifdef
  | Include
  | IncludeFilePath
  | Define 
  | CppOther

  (* web related *)
  | EmbededHtml (* e.g. xhp *)
  | EmbededHtmlAttr
  | EmbededUrl (* e.g. xhp *)
  | EmbededCode (* e.g. javascript *)
  | EmbededStyle (* e.g. css *)
  | Verbatim (* for latex, noweb, html pre *)

  (* misc *)
  | GrammarRule

  (* Ccomment *)
  | CommentWordImportantNotion
  | CommentWordImportantModal

  (* pad style specific *)
  | CommentSection0
  | CommentSection1
  | CommentSection2
  | CommentSection3 
  | CommentSection4
  | CommentEstet
  | CommentCopyright
  | CommentSyncweb

  (* search and match *)
  | MatchGlimpse
  | MatchSmPL
  | MatchParent

  | MatchSmPLPositif
  | MatchSmPLNegatif


  (* basic *)
  | BackGround | ForeGround 

  (* parsing imprecision *)
  | NotParsed | Passed | Expanded | Error
  | NoType

  (* well, normal code *)
  | Normal


type highlighter_preferences = {
  mutable show_type_error: bool;
  mutable show_local_global: bool;
  
}
let default_highlighter_preferences = {
  show_type_error = false;
  show_local_global = true;
}


(*****************************************************************************)
(* Color and font settings *)
(*****************************************************************************)

(* 
 * capabilities: (cf also pango.ml)
 *  - colors, and can provide semantic information by 
 *    * using opposite colors 
 *    * using close colors, 
 *    * using degrade color
 *    * using tone (darker, brighter)
 *    * can also use background/foreground
 *    
 *  - fontsize
 *  - bold, italic, slanted, normal
 *  - underlined/strikedthrough, pango can even do double underlined
 *  - fontkind, for instance comment could be in a different font
 *    in addition of different colors ?
 *  - casse, smallcaps ? (but can confondre avec macro ?)
 *  - stretch? (condenset)
 * 
 * 
 * 
 * Recurrent conventions, which would be counter productive to change maybe:
 *  - string: green
 *  - keywords: red/orange
 * 
 * Emacs C-mode conventions:
 * 
 *  - entities declarations: light/dark blue 
 *   (dark for param and local, light for func)
 *  - types: green
 *  - keywords: orange/dark-orange, this include:
 *    - control keywords
 *    - declaration keywords (static/register, but also struct, typedef)
 *    - cpp builtin keywords
 *  - labels: cyan
 *  - entities used: basic
 *  - comments: grey
 *  - strings: dark green
 * 
 * pad:
 *  - punctuation: blue
 *  - numbers: yellow
 * 
 * semantic variable:
 *   - global
 *   - parameter
 *   - local
 * semantic function:
 *   - local, defined in file
 *   - global
 *   - global and multidef
 *   - global and utilities, so kind of keyword, like my Common.map or 
 *     like kprintf
 * semantic types:
 *   - local/specific
 *   - globals
 * operators:
 *   - boolean
 *   - arithmetic
 *   - bits
 *   - memory
 * 
 * notions:
 *  declaration vs use (italic vs non italic, or large vs small)
 *  type vs values (use color?)
 *  control vs data (use color?)
 *  local vs global (bold vs non bold, also can use degarde de couleur)
 *  module vs program (use font size ?)
 *  unique vs multi (use underline ? and strikedthrough ?)
 * 
 * more and more distant => darker ?
 * less and less unique => bigger ?
 * (but both notions of distant and unique are strongly correlated ?)
 * 
 * Normally can leverage indentation and place in file. We know when
 * we are not at the toplevel because of the indentation, so can overload
 * some colors.
 * 
 * 
 * 
 * 
 * 
 * 
 * 
 * final:
 *  (total colors)
 *  - blanc
 *      wheat: default (but what remains default??)
 *  - noir
 *      gray: comments
 * 
 * 
 * 
 *  (primary colors)
 *  - rouge: 
 *      control,  conditional vs loop vs jumps, functions
 *  - bleue: 
 *     variables, values
 *  - vert: 
 *       types
 *      - vert-dark: string, chars
 * 
 * 
 * 
 *  (secondary colors) 
 *  - jaune (rouge-vert): 
 *      numbers, value
 *  - magenta (rouge-bleu): 
 *  
 *  - cyan (vert-bleu): 
 * 
 * 
 * 
 *  (tertiary colors)
 *  - orange (rouge-jaune):
 * 
 *  - pourpre (rouge-violet)
 * 
 *  - rose: 
 * 
 *  - turquoise:
 * 
 *  - marron
 * 
 *)

let legend_color_codes = "
The big principles for the colors, fonts, and strikes are: 
  - italic: for definitions, 
    normal: for uses
  - doubleline: double def, 
    singleline: multi def, 
    strike:     no def, 
    normal:     single def
  - big fonts: use of global variables, or function pointer calls
  - lighter: distance of definitions (very light means in same file)

  - gray background: not parsed, no type information, or other tool limitations
  - red background:  expanded code
  - other special backgrounds: search results

  - green:  types
  - purple: fields
  - yellow: functions (and macros)
  - blue:   globals, variables
  - pink:   constants, macros

  - cyan and big:      global, 
    turquoise and big: remote global,
    dark blue:         parameters, 
    blue:              locals
  - yellow and big: function pointer, 
    light yellow:   local call (in same file), 
    dark yellow:    remote module call (in same dir)
  - salmon: many uses, probably a utility function (e.g. printf)

  - red: problem, no definitions
"



let info_of_usedef usedef = 
  match usedef with
  | Def -> [`STYLE `ITALIC]
  | Use -> []


let info_of_def_arity defarity = 
  match defarity with
  | UniqueDef  -> []
  | DoubleDef -> [`UNDERLINE `DOUBLE]
  | MultiDef -> [`UNDERLINE `SINGLE]

  | NoDef -> [`STRIKETHROUGH true] 




let info_of_place defplace = 
  raise Todo


(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

(* pad taste *)
let info_of_category = function

  (* `FAMILY "-misc-*-*-*-*-20-*-*-*-*-*-*"*)
  (* `FONT "-misc-fixed-bold-r-normal--13-100-100-100-c-70-iso8859-1" *)

  (* background *)
  | BackGround -> [`BACKGROUND "DarkSlateGray"]
  | ForeGround -> [`FOREGROUND "wheat";]
      
  | NotParsed -> [`BACKGROUND "grey42" (*"lightgray"*)]
  | NoType ->    [`BACKGROUND "DimGray"]
  | Passed ->    [`BACKGROUND "DarkSlateGray4"]
  | Expanded ->  [`BACKGROUND "red"]
  | Error ->     [`BACKGROUND "red2"]


 (* a flashy one that hurts the eye :) *) 
  | BadSmell -> [`FOREGROUND "magenta"] 

  | UseOfRef -> [`FOREGROUND "magenta"]

  | PointerCall -> 
      [`FOREGROUND "firebrick";
       `WEIGHT `BOLD; 
       `SCALE `XX_LARGE;
      ]

  | ParameterRef -> [`FOREGROUND "magenta"]
  | CallByRef ->   
      [`FOREGROUND "orange"; 
       `WEIGHT `BOLD; 
       `SCALE `XX_LARGE;
      ]
  | IdentUnknown ->   [`FOREGROUND "red";]



  (* searches, background *)
  | MatchGlimpse -> [`BACKGROUND "grey46"]
  | MatchSmPL ->    [`BACKGROUND "ForestGreen"]

  | MatchParent -> [`BACKGROUND "blue"]

  | MatchSmPLPositif -> [`BACKGROUND "ForestGreen"]
  | MatchSmPLNegatif -> [`BACKGROUND "red"]




  (* foreground *)
  | Comment -> [`FOREGROUND "gray";]

  | CommentSection0 -> [`FOREGROUND "coral";]
  | CommentSection1 -> [`FOREGROUND "orange";]
  | CommentSection2 -> [`FOREGROUND "LimeGreen";]
  | CommentSection3 -> [`FOREGROUND "LightBlue3";]
  | CommentSection4 -> [`FOREGROUND "gray";]

  | CommentEstet -> [`FOREGROUND "gray";]
  | CommentCopyright -> [`FOREGROUND "gray";]
  | CommentSyncweb -> [`FOREGROUND "DimGray";]



  (* defs *)
  | Function (Def2 _) -> [`FOREGROUND "gold"; 
                          `WEIGHT `BOLD;
                          `STYLE `ITALIC; 
                          `SCALE `MEDIUM;
                         ]

  | FunctionDecl (_) -> [`FOREGROUND "gold2"; 
                         `WEIGHT `BOLD;
                         `STYLE `ITALIC; 
                         `SCALE `MEDIUM;
    ]
  | Macro (Def2 _) -> [`FOREGROUND "gold"; 
                       `WEIGHT `BOLD;
                       `STYLE `ITALIC; 
                       `SCALE `MEDIUM;
    ]

  | Global (Def2 _) ->   
      [`FOREGROUND "cyan"; 
       `WEIGHT `BOLD; 
       `STYLE `ITALIC;
       `SCALE `MEDIUM;
      ]


  | MacroVar (Def2 _) ->   
      [`FOREGROUND "pink"; 
       `WEIGHT `BOLD; 
       `STYLE `ITALIC;
       `SCALE `MEDIUM;
      ]

      

  | Class (Def2 _) -> 
      [`FOREGROUND "coral"] ++ info_of_usedef (Def)

  | Class (Use2 _) -> 
      [`FOREGROUND "coral"] ++ info_of_usedef (Use)

  | Parameter usedef -> [`FOREGROUND "SteelBlue2";] ++ info_of_usedef usedef
  | Local usedef  ->    [`FOREGROUND "SkyBlue1";] ++ info_of_usedef usedef 


  (* use *)

  | Function (Use2 (defplace,def_arity,use_arity)) -> 
      (match defplace with
      | PlaceLocal -> [`FOREGROUND "gold";]
      | PlaceSameDir -> [`FOREGROUND "goldenrod";]
      | PlaceExternal -> 
          (match use_arity with
          | MultiUse -> [`FOREGROUND "DarkGoldenrod"]

          | LotsOfUse | HugeUse | SomeUse -> [`FOREGROUND "salmon";]

          | UniqueUse -> [`FOREGROUND "yellow"]
          | NoUse -> [`FOREGROUND "IndianRed";]
          )
      | NoInfoPlace -> [`FOREGROUND "LightGoldenrod";]
      ) ++ info_of_def_arity def_arity


  | Global (Use2 (defplace, def_arity, use_arity)) -> 
      [`SCALE `X_LARGE] ++
      (match defplace with
      | PlaceLocal -> [`FOREGROUND "cyan";]
      | PlaceSameDir -> [`FOREGROUND "turquoise3";]
      | PlaceExternal -> 
          (match use_arity with
          | MultiUse -> [`FOREGROUND "turquoise4"]
          | LotsOfUse | HugeUse | SomeUse -> [`FOREGROUND "salmon";]

          | UniqueUse -> [`FOREGROUND "yellow"]
          | NoUse -> [`FOREGROUND "IndianRed";]
          )
      | NoInfoPlace -> [`FOREGROUND "LightCyan";]

      ) ++ info_of_def_arity def_arity


  | MacroVar (Use2 (defplace, def_arity, use_arity)) -> 
      (match defplace with
      | PlaceLocal -> [`FOREGROUND "pink";]
      | PlaceSameDir -> [`FOREGROUND "LightPink";]
      | PlaceExternal -> 
          (match use_arity with
          | MultiUse -> [`FOREGROUND "PaleVioletRed"]

          | LotsOfUse | HugeUse | SomeUse -> [`FOREGROUND "salmon";]

          | UniqueUse -> [`FOREGROUND "yellow"]

          | NoUse -> [`FOREGROUND "IndianRed";]
          )
      | NoInfoPlace -> [`FOREGROUND "pink1";]

      ) ++ info_of_def_arity def_arity


      
  (* copy paste of MacroVarUse for now *)
  | Macro (Use2 (defplace, def_arity, use_arity)) -> 
      (match defplace with
      | PlaceLocal -> [`FOREGROUND "pink";]
      | PlaceSameDir -> [`FOREGROUND "LightPink";]
      | PlaceExternal -> 
          (match use_arity with
          | MultiUse -> [`FOREGROUND "PaleVioletRed"]

          | LotsOfUse | HugeUse | SomeUse -> [`FOREGROUND "salmon";]

          | UniqueUse -> [`FOREGROUND "yellow"]
          | NoUse -> [`FOREGROUND "IndianRed";]
          )
      | NoInfoPlace -> [`FOREGROUND "pink1";]

      ) ++ info_of_def_arity def_arity


  | EnumValue usedef -> 
      [`FOREGROUND "plum";] ++
      info_of_usedef usedef         
  (* | FunCallMultiDef ->[`FOREGROUND "LightGoldenrod";] *)

  | Method (Use2 _) -> 
      [`FOREGROUND "gold3";]

  | Method (Def2 _) -> 
      [`FOREGROUND "gold3";
       `WEIGHT `BOLD; 
       `SCALE `MEDIUM;
      ]

  | StaticMethod (Def2 _) -> 
      [`FOREGROUND "gold3";
       `WEIGHT `BOLD; 
       `SCALE `MEDIUM;
      ]
  | StaticMethod (Use2 _) -> 
      [`FOREGROUND "gold3";
       `WEIGHT `BOLD; 
       `SCALE `MEDIUM;
      ]




  | TypeVoid -> [`FOREGROUND "LimeGreen";]
  | TypeInt ->  [`FOREGROUND "chartreuse";]
  | TypeMisc -> [`FOREGROUND "chartreuse";]

  | ConstructorDef _ -> [`FOREGROUND "tomato1";]
  | ConstructorMatch _ -> [`FOREGROUND "pink1";]
  | ConstructorUse _ -> [`FOREGROUND "pink3";]

  | FunctionEquation -> [`FOREGROUND "LightSkyBlue";]

  | Module (Use) -> [`FOREGROUND "DarkSlateGray4";]

  | Module (Def) -> [`FOREGROUND "chocolate";]

  | StructName usedef -> [`FOREGROUND "YellowGreen"] ++ info_of_usedef usedef 

  | Field (Def2 _) -> 
      [`FOREGROUND "MediumPurple1"] ++ info_of_usedef (Def)

  | Field (Use2 _) -> 
      [`FOREGROUND "MediumPurple2"] ++ info_of_usedef (Use)


  | TypeDef usedef -> [`FOREGROUND "YellowGreen"] ++ info_of_usedef usedef 



  | Ifdef -> [`FOREGROUND "chocolate";]

  | Include -> [`FOREGROUND "DarkOrange2";]
  | IncludeFilePath -> [`FOREGROUND "SpringGreen3";]

  | Define -> [`FOREGROUND "DarkOrange2";]

  | CppOther -> [`FOREGROUND "DarkOrange2";]




  | Keyword -> [`FOREGROUND "orange";]
  | Builtin -> [`FOREGROUND "salmon";]

  | BuiltinCommentColor -> [`FOREGROUND "gray";]
  | BuiltinBoolean -> [`FOREGROUND "pink";]

  | KeywordConditional -> [`FOREGROUND "DarkOrange";]
  | KeywordLoop -> [`FOREGROUND "sienna1";]

  | KeywordExn -> [`FOREGROUND "orchid";]
  | KeywordObject -> [`FOREGROUND "aquamarine3";]
  | KeywordModule -> [`FOREGROUND "chocolate";]


  | Number -> [`FOREGROUND "yellow3";]
  | Boolean -> [`FOREGROUND "pink3";]
  | String -> [`FOREGROUND "MediumSeaGreen";]
  | Regexp -> [`FOREGROUND "green3";]
  | Null -> [`FOREGROUND "cyan3";]




  | CommentWordImportantNotion ->  
      [`FOREGROUND "red";] ++
        [
          `SCALE `LARGE;
          `UNDERLINE `SINGLE;
        ]

  | CommentWordImportantModal ->  
      [`FOREGROUND "green";] ++
        [
          `SCALE `LARGE;
          `UNDERLINE `SINGLE;
        ]


  | Punctuation ->
      [`FOREGROUND "cyan";]

  | Operator ->
      [`FOREGROUND "DeepSkyBlue3";] (* could do better ? *)

  | (Label Def) ->
      [`FOREGROUND "cyan";]
  | (Label Use) ->
      [`FOREGROUND "CornflowerBlue";]

  | EnumName usedef
      -> [`FOREGROUND "YellowGreen"] ++ info_of_usedef usedef 

  | EmbededHtml ->
      (* to be consistent with Archi_code.Ui color *)
      [`FOREGROUND "RosyBrown"] 

  | EmbededHtmlAttr ->
      (* to be consistent with Archi_code.Ui color *)
      [`FOREGROUND "burlywood3"] 

  | EmbededUrl ->
      (* yellow-like color, like function, because it's often
       * used as a method call in method programming
       *)
      [`FOREGROUND "DarkGoldenrod2"] 

  | EmbededCode ->
      [`FOREGROUND "yellow3"] 
  | EmbededStyle ->
      [`FOREGROUND "peru"] 
  | Verbatim ->
      [`FOREGROUND "plum"] 

  | GrammarRule ->
      [`FOREGROUND "plum"] 


  | Normal -> [`FOREGROUND "wheat";]





(*****************************************************************************)
(* Str_of_xxx *)
(*****************************************************************************)


(*****************************************************************************)
(* Generic helpers *)
(*****************************************************************************)

let arity_ids ids  = 
  match ids with
  | [] -> NoDef
  | [x] -> UniqueDef
  | [x;y] -> DoubleDef
  | x::y::z::xs -> MultiDef



(* coupling: if you add a new kind of entity, then 
 * don't forget to modify size_font_multiplier_of_categ in pfff_visual
 * code
 * 
 * How sure this list is exhaustive ? C-c for usedef2
 *)
let is_entity_def_category categ = 
  match categ with
  | Function (Def2 _) 
  (* also ? *)
  | FunctionDecl _ 

  | Global (Def2 _) 

  | Class (Def2 _) 
  | Method (Def2 _) 
  | Field (Def2 _) 
  | StaticMethod (Def2 _) 

  | Macro (Def2 _) 
  | MacroVar (Def2 _) 

  (* Def *)
  | Module (Def)
  | TypeDef Def 

  (* todo: what about other Def ? like Label, Parameter, etc ? *)
    -> true
  | _ -> false


let rewrap_arity_def2_category arity categ = 

  match categ with
  | Function (Def2 _) -> Function (Def2 arity)
  | FunctionDecl _ ->  FunctionDecl (arity)
  | Global (Def2 _) ->  Global (Def2 arity)

  | Class (Def2 _) ->  Class (Def2 arity)
  | Method (Def2 _) ->  Method (Def2 arity)
  | Field (Def2 _) -> Field (Def2 arity)
  | StaticMethod (Def2 _) -> StaticMethod (Def2 arity)
        
  | Macro (Def2 _) -> Macro (Def2 arity)
  | MacroVar (Def2 _) -> MacroVar (Def2 arity)

  (* todo? *)
  | Module Def ->
      pr2_once "No arity for Module Def yet";
      Module Def
  | TypeDef Def  ->  
      pr2_once "No arity for Typedef Def yet";
      TypeDef Def

  | _ -> failwith "not a Def2-kind categoriy"
