(* elpi: embedded lambda prolog interpreter                                  *)
(* license: GNU Lesser General Public License Version 2.1 or later           *)
(* ------------------------------------------------------------------------- *)
open Suite

let declare = Test.declare
    ~category:(Filename.(chop_extension (basename __FILE__)))

let () = declare "cut1"
  ~source_elpi:"cut.elpi"
  ~description:"what else"
  ()
let () = declare "cut2"
  ~source_elpi:"cut2.elpi"
  ~description:"what else"
  ()
let () = declare "cut3"
  ~source_elpi:"cut3.elpi"
  ~description:"what else"
  ()
let () = declare "cut4"
  ~source_elpi:"cut4.elpi"
  ~description:"what else"
  ()
let () = declare "cut5"
  ~source_elpi:"cut5.elpi"
  ~description:"what else"
  ()
let () = declare "cut6"
  ~source_elpi:"cut6.elpi"
  ~description:"what else"
  ()

let () = declare "backtracking"
  ~source_elpi:"trail.elpi"
  ~description:"backtracking variable assignment"
  ()

let () = declare "uminus"
  ~source_elpi:"uminus.elpi"
  ~description:"parsing and evaluation of unary minus"
  ()

let () = declare "typeabbrv1"
  ~source_elpi:"typeabbrv1.elpi"
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv2"
  ~source_elpi:"typeabbrv2.elpi"
  ~expectation:Failure
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv3"
  ~source_elpi:"typeabbrv3.elpi"
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv4"
  ~source_elpi:"typeabbrv4.elpi"
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv5"
  ~source_elpi:"typeabbrv5.elpi"
  ~expectation:Failure
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv6"
  ~source_elpi:"typeabbrv6.elpi"
  ~expectation:Failure
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv7"
  ~source_elpi:"typeabbrv7.elpi"
  ~expectation:Success
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv8"
  ~source_elpi:"typeabbrv8.elpi"
  ~expectation:Success
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv9"
  ~source_elpi:"typeabbrv9.elpi"
  ~expectation:Success
  ~description:"type abbreviations"
  ()
let () = declare "typeabbrv10"
  ~source_elpi:"typeabbrv10.elpi"
  ~expectation:(FailureOutput (Str.regexp "3 has type int but is used with type (foo X[0-9]+)"))
  ~description:"type abbreviations and error messages"
  ()
let () = declare "typeabbrv11"
  ~source_elpi:"typeabbrv11.elpi"
  ~expectation:(FailureOutput (Str.regexp "x has type string but is used with type int"))
  ~description:"type abbreviations and error messages"
  ()
let () = declare "typeabbrv12"
  ~source_elpi:"typeabbrv12.elpi"
  ~expectation:(FailureOutput (Str.regexp "x has type string but is used with type y"))
  ~description:"type abbreviations and error messages"
  ()

let () = declare "conj2"
  ~source_elpi:"conj2.elpi"
  ~description:"parsing and evaluation of & (binary conj)"
  ()

let () = declare "conj2_legacy"
  ~source_elpi:"conj2.elpi"
  ~description:"parsing and evaluation of & (binary conj)"
  ~legacy_parser:true
  ()

(* 
  Note in the following tests with DT, we disable typecheck not to print the
  number of candidates found in the search of clauses done by the elpi typechecker
*)
let () = declare "dt_var"
  ~source_elpi:"dt_var.elpi"
  ~description:"discrimination_tree indexing flex"
  ~typecheck:false
  ~trace:(On["tty";"stdout";"-trace-at";"1";"9999";"-trace-only";"dev:disc-tree:candidates"])
  ~expectation:(SuccessOutput (Str.regexp "dev:disc-tree:candidates = 2"))
  ()

let () = declare "dt_var2"
  ~source_elpi:"dt_var2.elpi"
  ~description:"discrimination_tree indexing flex"
  ~typecheck:false
  ~trace:(On["tty";"stdout";"-trace-at";"1";"9999";"-trace-only";"dev:disc-tree:candidates"])
  ~expectation:(SuccessOutput (Str.regexp "dev:disc-tree:candidates = 3"))
  ()

let () = declare "dt_multi1"
  ~source_elpi:"dt_multi1.elpi"
  ~description:"discrimination_tree indexing multi argument"
  ~typecheck:false
  ~trace:(On["tty";"stdout";"-trace-at";"1";"9999999";"-trace-only";"dev:disc-tree:candidates"])
  ~expectation:(SuccessOutput (Str.regexp "dev:disc-tree:candidates = 1"))
  ()

let () = declare "dt_multi2"
  ~source_elpi:"dt_multi2.elpi"
  ~description:"discrimination_tree indexing multi with flexible"
  ~typecheck:false
  ~trace:(On["tty";"stdout";"-trace-at";"1";"9999999";"-trace-only";"dev:disc-tree:candidates"])
  ~expectation:(SuccessOutput (Str.regexp "dev:disc-tree:candidates = 101"))
  ()

let () = declare "dt_multi3"
  ~source_elpi:"dt_multi3.elpi"
  ~description:"discrimination_tree indexing multi with flexible in input mode"
  ~typecheck:false
  ~trace:(On["tty";"stdout";"-trace-at";"1";"9999999";"-trace-only";"dev:disc-tree:candidates"])
  ~expectation:(FailureOutput (Str.regexp "dev:disc-tree:candidates = 0"))
  ()

let () = declare "is"
  ~source_elpi:"is.elpi"
  ~description:"calc"
  ()
