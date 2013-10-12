(*s: view_mainmap.mli *)

val paint: Model2.drawing -> unit

val zoom_pan_scale_map: Cairo.t -> Model2.drawing -> unit

val device_to_user_area: Model2.drawing -> Figures.rectangle

val with_map: Model2.drawing -> (Cairo.t -> 'a) -> 'a

val button_action:
 < as_widget : [> `widget ] Gtk.obj; .. > ->
   Model2.drawing ref -> GdkEvent.Button.t -> bool

(*e: view_mainmap.mli *)
