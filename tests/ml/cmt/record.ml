type record = { 
  fld1: int; 
  fld2: float;
  mutable mut_fld3: float;
}

let use_record_in_pattern = function
  { fld1 = i; _} -> i

let use_record x = x.fld1

let modify_record x =
  x.mut_fld3 <- 3.

