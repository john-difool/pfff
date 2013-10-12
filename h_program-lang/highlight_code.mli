
type category =
  | Comment 
  | Number | Boolean | Null | String | Regexp

  | Keyword 
  | KeywordConditional | KeywordLoop 
  | KeywordExn | KeywordObject | KeywordModule
  | Builtin | BuiltinCommentColor | BuiltinBoolean
  | Operator | Punctuation

  | Function of usedef2
  | FunctionDecl of def_info
  | Global of usedef2
  | Class of usedef2
  | Field of usedef2
  | Method of usedef2
  | StaticMethod of usedef2
  | Macro of usedef2
  | MacroVar of usedef2

  | StructName of usedef
  | EnumName of usedef
  | EnumValue of usedef
  | TypeDef of usedef

  | ConstructorDef of def_info
  | ConstructorUse of use_info
  | ConstructorMatch of use_info

  | Module of usedef
  | Label of usedef
  | FunctionEquation

  | BadSmell
  | UseOfRef
  | PointerCall
  | CallByRef
  | ParameterRef
  | IdentUnknown

  | Local of usedef
  | Parameter of usedef

  | TypeVoid | TypeInt | TypeMisc

  | Ifdef | Include | IncludeFilePath | Define | CppOther

  | EmbededHtml (* e.g. xhp *) | EmbededHtmlAttr
  | EmbededUrl (* e.g. xhp *)
  | EmbededCode (* e.g. javascript *)
  | EmbededStyle (* e.g. css *)
  | Verbatim (* for latex, noweb, html pre *)

  | GrammarRule

  | CommentWordImportantNotion | CommentWordImportantModal
  | CommentSection0 | CommentSection1 | CommentSection2 
  | CommentSection3 | CommentSection4
  | CommentEstet | CommentCopyright | CommentSyncweb

  | MatchGlimpse | MatchSmPL
  | MatchParent
  | MatchSmPLPositif | MatchSmPLNegatif

  | BackGround | ForeGround

  | NotParsed | Passed | Expanded | Error
  | NoType

  | Normal

and usedef = Use | Def
and usedef2 = Use2 of use_info | Def2 of def_info
 and def_info = use_arity
  and use_arity = NoUse | UniqueUse | SomeUse | MultiUse | LotsOfUse | HugeUse
 and use_info = place * def_arity * use_arity
  and place = PlaceLocal | PlaceSameDir | PlaceExternal | NoInfoPlace
  and def_arity = UniqueDef | DoubleDef | MultiDef | NoDef

type highlighter_preferences = {
  mutable show_type_error : bool;
  mutable show_local_global : bool;
}
val default_highlighter_preferences: highlighter_preferences
val legend_color_codes : string

(* main entry point *)
val info_of_category :
  category ->
  [> `BACKGROUND of string
   | `FOREGROUND of string
   | `SCALE of [> `LARGE | `MEDIUM | `XX_LARGE | `X_LARGE ]
   | `STRIKETHROUGH of bool
   | `STYLE of [> `ITALIC ]
   | `UNDERLINE of [> `DOUBLE | `SINGLE ]
   | `WEIGHT of [> `BOLD ] ]
  list

val is_entity_def_category: category -> bool
val rewrap_arity_def2_category: def_info -> category -> category

(* use the same polymorphic variants than in ocamlgtk *)
val info_of_usedef : 
  usedef -> 
  [> `STYLE of [> `ITALIC ] ] list
val info_of_def_arity :
  def_arity ->
  [> `STRIKETHROUGH of bool | `UNDERLINE of [> `DOUBLE | `SINGLE ] ] list
val info_of_place : 'a -> 'b

val arity_ids : 'a list -> def_arity
