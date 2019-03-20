(* elpi: embedded lambda prolog interpreter                                  *)
(* license: GNU Lesser General Public License Version 2.1 or later           *)
(* ------------------------------------------------------------------------- *)

module U = Elpi_util
open Elpi_ast

module Str = Re.Str

let of_ploc l = {
  Loc.source_name = Ploc.file_name l;
  source_start = Ploc.first_pos l;
  source_stop = Ploc.last_pos l;
  line = Ploc.line_nb l;
  line_starts_at = Ploc.bol_pos l;
}
let to_ploc {
    Loc.source_name = source_name;
    line = line;
    line_starts_at = line_starts_at;
    source_start = source_start;
    source_stop = source_stop;
  } =
  Ploc.make_loc source_name line line_starts_at (source_start, source_stop) ""

exception ParseError of Loc.t * string

type fixity = Infixl | Infixr | Infix | Prefix | Prefixr | Postfix | Postfixl

let fixity_of_string = function
  | "infixl" -> Infixl 
  | "infixr" -> Infixr 
  | "infix" -> Infix 
  | "prefix" -> Prefix 
  | "prefixr" -> Prefixr 
  | "postfix" -> Postfix 
  | "postfixl" -> Postfixl
  | s -> raise (Stream.Error ("invalid fixity: " ^ s))

let set_precedence, precedence_of =
 let module ConstMap = Map.Make(Func) in 
 let precs = ref ConstMap.empty in
 (fun c p -> precs := ConstMap.add c p !precs),
 (fun c -> ConstMap.find c !precs)
;;

let cur_dirname = ref "./"
let last_loc : Ploc.t ref = ref (Ploc.make_loc "dummy" 1 0 (0, 0) "")
let set_fname ?(line=1) fname = last_loc := (Ploc.make_loc fname line 0 (0, 0) "")

let rec readsymlinks f =
  try
    let link = Unix.readlink f in
    if not(Filename.is_relative link) then readsymlinks link
    else readsymlinks Filename.(concat (dirname f) link)
  with Unix.Unix_error _ | Failure _ -> f

let symlink_dirname f = Filename.dirname (readsymlinks f)

let make_absolute filename =
  if not (Filename.is_relative filename) then filename
  else Filename.concat !cur_dirname filename

let cur_tjpath = ref []

let set_tjpath cwd paths =
 cur_dirname := cwd;
 let tjpath = List.map (fun f -> make_absolute (readsymlinks f)) paths in
 cur_tjpath := tjpath

(*CSC: when parse_one opens a file for reading, open the .tex file
  for writing (and put the header) *)
(* the parsed variable is a cache to avoid parsing the same file twice *)

let parse_silent = ref true
let parsed = ref []

exception File_not_found of string

let rec parse_one e (origfilename as filename) =
 let origprefixname =
   try Filename.chop_extension origfilename
   with Invalid_argument _ ->
     raise (Failure ("File "^origfilename^" has no extension")) in
 let prefixname, filename =
  let rec iter_tjpath dirnames =
   let filename,dirnames,relative =
    if not (Filename.is_relative filename) then filename,[],false
    else
     match dirnames with
        [] -> raise (File_not_found filename)
      | dirname::dirnames->Filename.concat dirname filename,dirnames,true in
   let prefixname = Filename.chop_extension filename in
   let prefixname,filename =
    let change_suffix filename =
     if Filename.check_suffix filename ".elpi" then
      (* Backward compatibility with Teyjus *) 
      prefixname ^ ".mod"
     else if Filename.check_suffix filename ".mod" then
      (* Forward compatibility with Teyjus *) 
      prefixname ^ ".elpi"
     else filename in
    if Sys.file_exists filename then prefixname,filename
    else
     let changed_filename = change_suffix filename in
     if Sys.file_exists changed_filename then prefixname,changed_filename
     else if relative then iter_tjpath dirnames
     else raise (File_not_found origfilename) in
   prefixname,filename
  in
   let dirs = !cur_dirname :: !cur_tjpath in 
   try iter_tjpath dirs
   with File_not_found f ->
     raise (Failure ("File "^f^" not found in: " ^ String.concat ", " dirs))
 in
 let inode = Digest.file filename in
 if List.mem_assoc inode !parsed then begin
  if not !parse_silent then Printf.eprintf "already loaded %s\n%!" origfilename;
  match !(List.assoc inode !parsed) with
  | None -> []
  | Some l -> l
 end else begin
  let sigs =
   if Filename.check_suffix filename ".sig" then []
   else
    let signame = prefixname ^ ".sig" in
    if Sys.file_exists signame then
     let origsigname = origprefixname ^ ".sig" in
     parse_one e origsigname
    else [] in
  if not !parse_silent then
    Printf.printf "loading %s (%s)\n%!" origfilename (Digest.to_hex inode);
  let ast = ref None in
  parsed := (inode,ast) ::!parsed ;
  let ch = open_in filename in
  let saved_cur_dirname = !cur_dirname in
  cur_dirname := symlink_dirname filename;
  sigs @
  try
   let loc = !last_loc in
   set_fname filename;
   let res = Grammar.Entry.parse e (Stream.of_channel ch)in
   last_loc := loc;
   ast := Some res;
   close_in ch;
   cur_dirname := saved_cur_dirname;
   res
  with Ploc.Exc(l,(Token.Error msg | Stream.Error msg)) ->
    close_in ch;
    let loc = of_ploc l in
    let loc = { loc with Loc.source_name = origfilename } in
    raise (ParseError(loc,msg))
  | Ploc.Exc(_,e) -> close_in ch; raise e
 end
  
let parse e filenames =
  List.concat (List.map (parse_one e) filenames)

let string_of_chars chars = 
  let buf = Buffer.create 10 in
  List.iter (Buffer.add_char buf) chars;
  Buffer.contents buf
let _spy ?(name="") ?pp f b s =
  let l = Stream.npeek 10 s in
  Printf.eprintf "%s< %s | %S...\n"
    name (Plexing.Lexbuf.get b) (string_of_chars l);
  try
    let b = f b s in
    begin match pp with
    | None -> Printf.eprintf "%s> ok" name
    | Some pp -> Printf.eprintf "%s> %s\n\n" name (pp b)
    end; b
  with e ->
    Printf.eprintf "nope\n";
    raise e
;;

let digit = lexer [ '0'-'9' ]
(* let octal = lexer [ '0'-'7' ] *)
(* let hex = lexer [ '0'-'9' | 'A'-'F' | 'a'-'f' ] *)
let schar2 =
 lexer [ '+'  | '*' | '/' | '^' | '<' | '>' | '`' | '\'' | '?' | '@' | '#'
       | '~' | '=' | '&' | '!' ]
let schar = lexer [ schar2 | '-' | '$' | '_' ]
let lcase = lexer [ 'a'-'z' ]
let ucase = lexer [ 'A'-'Z' ]
let idchar = lexer [ lcase | ucase | digit | schar ]
let rec idcharstar = lexer [ idchar idcharstar | ]
let rec idcharstarns = lexer [ idchar idcharstarns | ?= [ '.' 'a'-'z' | '.' 'A'-'Z' ] '.' idchar idcharstarns | ]
let idcharplus = lexer [ idchar idcharstar ]
let rec num = lexer [ digit | digit num ]
let symbchar = lexer [ lcase | ucase | digit | schar | ':' ]
let rec symbcharstar = lexer [ symbchar symbcharstar | ]

let stringchar = lexer
 [ "\\\\" / -> $add "\\"
 | "\\n" / -> $add "\n"
 | "\\b" / -> $add "\b"
 | "\\t" / -> $add "\t"
 | "\\r" / -> $add "\r"
 | "\\x" / -> $add "\x"
 | "\\\"" / -> $add "\""
 (* CSC: I have no idea how to implement the \octal syntax & friend :-(
 | "\\" / [ -> buflen := String.length $buf ; $add "" ] octal / ->
    $add (mkOctal "4")*)
 | _ ]

let rec string = lexer [ '"' / '"' string | '"' / | stringchar string ]
let any = lexer [ _ ]
let mk_terminator keep n b s =
  let l = Stream.npeek n s in
  if List.length l = n && List.for_all ((=) '}') l then begin
   let b = ref b in
   for _i = 1 to n do
     Stream.junk s;
     if keep then b := Plexing.Lexbuf.add '}' !b;
   done; !b
  end else raise Stream.Failure
let rec quoted_inner d = (*spy ~name:"quoted_inner"*) (lexer
  [ d
  | "{" (maybe_quoted_inner d)
  | any (quoted_inner d) ])
and maybe_quoted_inner d = (*spy ~name:"maybe"*) (lexer
  [ d
  | "{" (quoted true 2) (quoted_inner d)
  | any (quoted_inner d) ])
and  quoted keep n = (*spy ~name:"quoted"*) (lexer
  [ "{" (quoted keep (n+1))
  | (quoted_inner (mk_terminator keep n)) ])

let constant = "CONSTANT" (* to use physical equality *)

let rec tok b s = (*spy ~name:"tok" ~pp:(fun (a,b) -> a ^ " " ^ b)*) (lexer
  [ ucase idcharstar -> constant,$buf 
  | lcase idcharstarns -> constant,$buf
  | schar2 symbcharstar -> constant,$buf
  | num -> "INTEGER",$buf
  | num ?= [ '.' '0'-'9' ] '.' num -> "FLOAT",$buf
  | '-' idcharstar -> constant,$buf
  | '_' -> "FRESHUV", "_"
  | '_' idcharplus -> constant,$buf
  | ":-"  -> constant,$buf
  | ":"  -> "COLON",$buf
  | "::"  -> constant,$buf
  | ',' -> constant,$buf
  | ';' -> constant,$buf
  | '?' -> constant,$buf
  | '.' -> "FULLSTOP",$buf
  | '.' num -> "FLOAT",$buf
  | '\\' -> "BIND","\\"
  | '(' [ is_infix ->
             "ESCAPE",  String.(sub $buf 0 (length $buf - 1))
        | -> "LPAREN",$buf ]
  | ')' -> "RPAREN",$buf
  | '[' -> "LBRACKET",$buf
  | ']' -> "RBRACKET",$buf
  | "{{" / (quoted false 2) -> "QUOTED", $buf
  | '{' -> "LCURLY",$buf
  | '}' -> "RCURLY",$buf
  | '|' -> "PIPE",$buf
  | '"' / string -> "LITERAL", $buf
]) b s
and is_infix_aux b s =
  let k1, s1 = tok b s in
  let k2, s2 = tok b s in 
  if k1 == constant && k2 = "RPAREN" && not (is_capital s1.[0])
  then string2lexbuf2 s1 s2
  else if k1 = "LBRACKET" && k2 = "RBRACKET" then
    let k3, s3 = tok b s in
    if k3 = "RPAREN" then string2lexbuf3 s1 s2 s3
    else raise Stream.Failure
  else raise Stream.Failure
and protect max_chars lex s =
  let l = Stream.npeek max_chars s in
  let safe_s = Stream.of_list l in
  let to_junk, res = lex Plexing.Lexbuf.empty safe_s in
  for _i = 0 to to_junk-1 do Stream.junk s; done;
  res
and is_infix _ s = protect 6 is_infix_aux s
and string2lexbuf2 s1 s2 =
  let b = ref Plexing.Lexbuf.empty in
  String.iter (fun c -> b := Plexing.Lexbuf.add c !b) s1;
  String.iter (fun c -> b := Plexing.Lexbuf.add c !b) s2;
  String.(length s1 + length s2), !b
and string2lexbuf3 s1 s2 s3 =
  let b = ref Plexing.Lexbuf.empty in
  String.iter (fun c -> b := Plexing.Lexbuf.add c !b) s1;
  String.iter (fun c -> b := Plexing.Lexbuf.add c !b) s2;
  String.iter (fun c -> b := Plexing.Lexbuf.add c !b) s3;
  String.(length s1 + length s2 + length s3), !b
and is_capital c = match c with 'A'..'Z' -> true | _ -> false

let option_eq x y = match x, y with Some x, Some y -> x == y | _ -> x == y

module StringSet = Set.Make(String);;
let symbols = ref StringSet.empty;;

let literatebuf = Buffer.create 17;;

(* %! <= \leq creates a map from "<=" to "\leq" *)
let set_liter_map, get_literal, _print_lit_map =
 let lit_map = ref U.StrMap.empty in
 (fun s1 s2 -> lit_map := U.StrMap.add s1 s2 !lit_map),
 (fun s -> U.StrMap.find s !lit_map),
 (fun () -> U.StrMap.iter (fun s1 s2 -> Format.printf "\n%s -> %s\n%!" s1 s2) !lit_map);;

let succ_line loc ep =
  Ploc.make_loc (Ploc.file_name loc) (Ploc.line_nb loc + 1) ep
                (Ploc.last_pos loc, Ploc.last_pos loc) (Ploc.comment loc)

let set_loc_pos loc init bp ep =
  Ploc.sub loc (bp - init) (ep - bp)

let rec lex loc c init = parser bp
  | [< '( ' ' | '\t' | '\r' ); s >] -> lex loc c init s
  | [< '( '\n' ) ; s >] ep -> lex (succ_line loc ep) c init s
  | [< '( '%' ); '( '!'); s >] -> literatecomment loc c init s
  | [< '( '%' ); s >] -> comment loc c init s
  | [< ?= [ '/'; '*' ]; '( '/' ); '( '*' ); s >] -> comment2 loc 0 c init s
  | [< s >] ->
       if option_eq (Stream.peek s) None
       then ("EOF",""), (set_loc_pos loc init bp bp)
       else
        let (x,y) as res = tok c s in
        let ep = Stream.count s in
        (if x == constant then
         (match y with
         | "module" -> "MODULE", "module"
         | "sig" -> "SIG", "SIG"
         | "import" -> "IMPORT", "accumulate"
         | "shorten" -> "SHORTEN", "shorten"
         | "accum_sig" -> "ACCUM_SIG", "accum_sig"
         | "use_sig" -> "USE_SIG", "use_sig"
         | "local" -> "LOCAL", "local"
         | "pred" -> "PRED", "pred"
         | "mode" -> "MODE", "mode"
         | "macro" -> "MACRO", "macro"
         | "rule" -> "RULE", "rule"
         | "namespace" -> "NAMESPACE", "namespace"
         | "constraint" -> "CONSTRAINT", "constraint"
         | "localkind" -> "LOCALKIND", "localkind"
         | "useonly" -> "USEONLY", "useonly"
         | "exportdef" -> "EXPORTDEF", "exportdef"
         | "kind" -> "KIND", "kind"
         | "typeabbrev" -> "TYPEABBREV", "typeabbrev"
         | "type" -> "TYPE", "type"
         | "external" -> "EXTERNAL", "external"
         | "closed" -> "CLOSED", "closed"
         | "end" -> "EOF", "end"
         | "accumulate" -> "ACCUMULATE", "accumulate"
         | "infixl" -> "FIXITY", "infixl"
         | "infixr" -> "FIXITY", "infixr"
         | "infix" -> "FIXITY", "infix"
         | "prefix" -> "FIXITY", "prefix"
         | "prefixr" -> "FIXITY", "prefixr"
         | "postfix" -> "FIXITY", "postfix"
         | "postfixl" -> "FIXITY", "postfixl"
        
         | x when StringSet.mem x !symbols -> "SYMBOL",x
        
         | _ -> res) else res), (set_loc_pos loc init bp ep)
and literatecomment loc c init = parser
  | [< '( '\n' ); s >] ep ->
      let loc = succ_line loc ep in
      let buf = Buffer.contents literatebuf in
      Buffer.reset literatebuf;
      let list_str = Str.split (Str.regexp " +") buf in
      (match list_str with
       | [s1;s2] -> set_liter_map s1 s2; 
       | _ -> prerr_endline ("Wrong syntax: literate comment: " ^ buf); exit 1);
  (*   print_lit_map (); *)
  (*   prerr_endline buf; (*register imperatively*) *)
      lex loc c init s
  | [< '_ as x ; s >] -> Buffer.add_char literatebuf x; literatecomment loc c init s
and comment loc c init = parser
  | [< '( '\n' ); s >] ep -> lex (succ_line loc ep) c init s
  | [< '_ ; s >] -> comment loc c init s
and comment2 loc lvl c init = parser
  | [< ?= [ '*'; '/' ]; '( '*' ); '( '/'); s >] ->
      if lvl = 0 then lex loc c init s else comment2 loc (lvl-1) c init s
  | [< ?= [ '/'; '*' ]; '( '/' ); '( '*' ); s >] -> comment2 loc (lvl+1) c init s
  | [< '( '\n' ); s >] ep -> comment2 (succ_line loc ep) lvl c init s
  | [< '_ ; s >] -> comment2 loc lvl c init s


open Plexing

(* For some reason, the [Ploc.after] function of Camlp5 does not update line
   numbers, so we define our own function that does it. *)
let after loc =
  let line_nb = Ploc.line_nb_last loc in
  let bol_pos = Ploc.bol_pos_last loc in
  Ploc.make_loc (Ploc.file_name loc) line_nb bol_pos
                (Ploc.last_pos loc, Ploc.last_pos loc) (Ploc.comment loc)

let lex_fun s =
  let tab = Hashtbl.create 207 in
  (Stream.from (fun id ->
     let tok, loc = lex !last_loc Lexbuf.empty (Stream.count s) s in
(*      Printf.eprintf "tok: %s, %s, %s\n" (Loc.show (of_ploc loc)) (fst tok) (snd tok); *)
     last_loc := after loc;
     Hashtbl.add tab id loc;
     Some tok)),
  (fun id -> try Hashtbl.find tab id with Not_found -> !last_loc)
;;

let tok_match =
 function
    ((s1:string),"") ->
      fun ((s2:string),v) ->
       if Pervasives.compare s1 s2 == 0 then v else raise Stream.Failure
  | ((s1:string),v1) ->
      fun ((s2:string),v2) ->
       if Pervasives.compare s1 s2==0 && Pervasives.compare v1 v2==0 then v2
       else raise Stream.Failure

let lex = {
  tok_func = lex_fun;
  tok_using =
   (fun x,y ->
      if x = "SYMBOL" && y <> "" then begin
       symbols := StringSet.add y !symbols
      end
   );
  tok_removing = (fun _ -> ());
  tok_match = tok_match;
  tok_text = (function (s,y) -> s ^ " " ^ y);
  tok_comm = None;
}

let g = Grammar.gcreate lex
let lp = Grammar.Entry.create g "lp"
let goal = Grammar.Entry.create g "goal"
let atom = Grammar.Entry.create g "atom"

let min_precedence = -1  (* minimal precedence in use *)
let lam_precedence = -1  (* precedence of lambda abstraction *)
let umin_precedence = 0   (* minimal user defined precedence *)
let umax_precedence = 256 (* maximal user defined precedence *)
let appl_precedence = umax_precedence + 1 (* precedence of application *)
let inf_precedence = appl_precedence+1 (* greater than any used precedence*)

(*
let dummy_prod =
 let dummy_action =
   Gramext.action (fun _ ->
     failwith "internal error, lexer generated a dummy token") in
 [ [ Gramext.Stoken ("DUMMY", "") ], dummy_action ]
*)

let used_precedences = ref [110];;
let is_used n =
 let rec aux visited acc =
  function
     hd::_  when hd = n ->
     !used_precedences, (Gramext.Level (string_of_int n), None)
   | hd::tl when hd < n ->
     aux (hd::visited) (Gramext.After (string_of_int hd)) tl
   | l -> List.rev (n::visited) @ l, (acc, Some (string_of_int n))
 in
  let used, res = aux [] Gramext.First !used_precedences in
  used_precedences := used ;
  res
;;

let desugar_multi_binder loc = function
  | App(Const hd as binder,args)
    when Func.(equal hd pif || equal hd sigmaf) && List.length args > 1 ->
      let last, rev_rest = let l = List.rev args in List.hd l, List.tl l in
      let names = List.map (function
        | Const x -> Func.show x
        | (App _ | Lam _ | CData _ | Quoted _) ->
            Elpi_util.error "multi binder syntax") rev_rest in
      let body = mkApp (of_ploc loc) [binder;last] in
      List.fold_left (fun bo name -> mkApp (of_ploc loc) [binder;mkLam name bo]) body names
  | (App _ | Const _ | Lam _ | CData _ | Quoted _) as t -> t
;;

let desugar_macro = function
  | App(Const hd,[Const name; body]) when Func.(equal hd rimplf) ->
      if ((Func.show name).[0] != '@') then
        raise (Stream.Error "Macro name must begin with @");
      name, body
  | App(Const hd,[App(Const name,args); body]) when Func.(equal hd rimplf) ->
      if ((Func.show name).[0] != '@') then
        raise (Stream.Error "Macro name must begin with @");
      let names = List.map (function
        | Const x -> Func.show x
        | (App _ | Lam _ | CData _ | Quoted _) ->
             Elpi_util.error "macro binder syntax") args in
      name, List.fold_right mkLam names body
  | (App _ | Const _ | Lam _ | CData _ | Quoted _) ->
        raise (Stream.Error "Illformed macro")
;;

let constant_colon strm =
  match Stream.npeek 2 strm with
  | [ ("CONSTANT",_); ("COLON",_) ] -> ()
  | _ -> raise Stream.Failure
let constant_colon =
  Grammar.Entry.of_parser g "constant_colon" constant_colon

type gramext = { fix : fixity; sym : string; prec : int }

let gram_extend loc { fix; sym = cst; prec = nprec } =
  if nprec < umin_precedence || nprec > umax_precedence then
    raise (ParseError(loc,Printf.sprintf "precedence muse be inside [%d,%d]" umin_precedence umax_precedence))
  else
    let binrule =
     [ Gramext.Sself ; Gramext.Stoken ("SYMBOL",cst); Gramext.Sself ],
     Gramext.action (fun t2 cst t1 loc -> mkApp (of_ploc loc) [mkCon cst;t1;t2]) in
    let prerule =
     [ Gramext.Stoken ("SYMBOL",cst); Gramext.Sself ],
     Gramext.action (fun t cst loc -> mkApp (of_ploc loc) [mkCon cst;t]) in
    let postrule =
     [ Gramext.Sself ; Gramext.Stoken ("SYMBOL",cst) ],
     Gramext.action (fun cst t loc -> mkApp (of_ploc loc) [mkCon cst;t]) in
    let ppinfo = fix, nprec in
    let fixity,rule =
     (* NOTE: we do not distinguish between infix and infixl,
        prefix and prefix, postfix and postfixl *)
     match fix with
       Infix    -> Gramext.NonA,   binrule
     | Infixl   -> Gramext.LeftA,  binrule
     | Infixr   -> Gramext.RightA, binrule
     | Prefix   -> Gramext.NonA,   prerule
     | Prefixr  -> Gramext.RightA, prerule
     | Postfix  -> Gramext.NonA,   postrule
     | Postfixl -> Gramext.LeftA,  postrule in
    set_precedence (Func.from_string cst) ppinfo ;
    let where,name = is_used nprec in
     Grammar.extend
      [Grammar.Entry.obj atom, Some where, [name, Some fixity, [rule]]];
;;
          (* Debugging code
          prerr_endline "###########################################";
          Grammar.iter_entry (
            Grammar.print_entry Format.err_formatter
          ) (Grammar.Entry.obj atom);
          prerr_endline ""; *)


EXTEND
  GLOBAL: lp goal atom;
  lp: [ [ cl = LIST0 clause; EOF -> List.concat cl ] ];
  const_sym:
    [[ c = CONSTANT -> c
     | s = SYMBOL -> s
     | e = ESCAPE -> e ]];
  filename:
    [[ c = CONSTANT -> c
     | c = LITERAL -> c ]];
  i_o : [[ CONSTANT "i" -> true | CONSTANT "o" -> false ]];
  mode :
    [[ LPAREN; c = CONSTANT; l = LIST1 i_o; RPAREN ->
       { mname = Func.from_string c; margs = l } ]];
  chrrule :
    [[ to_match = LIST0 sequent;
       to_remove = OPT [ BIND; l = LIST1 sequent -> l ];
       guard = OPT [ PIPE; a = atom LEVEL "abstterm" -> a ];
       new_goal = OPT [ SYMBOL "<=>"; gs = sequent -> gs ] ->
         create_chr_rule ~to_match ?to_remove ?guard ?new_goal ~cattributes:[] ~clocation:(of_ploc loc) ()
    ]];
  sequent_core :
    [ [ constant_colon; e = CONSTANT; COLON; t = atom -> Some e, (t : term) 
      | t = atom -> None, (t : term) ]
    ];
  sequent :
   [[ LPAREN; c = sequent_core; RPAREN ->
         let e, t1 = (c : string option * term) in
         let eigen =
           match e with Some x -> mkCon x | None -> mkFreshUVar () in
         let context, conclusion =
           match t1 with
           | App(Const x,[a;b]) when Func.equal x Func.sequentf -> a, b
           | (App _ | Const _ | Lam _ | CData _ | Quoted _) ->
                mkFreshUVar (), t1 in
         { eigen; context; conclusion }
    | c = atom LEVEL "abstterm" ->
         { eigen = mkFreshUVar (); context = mkFreshUVar (); conclusion = c }
   ]];
  attribute_value :
   [[ c = CONSTANT -> c | l = LITERAL -> l ]];
  attribute :
   [[ CONSTANT "name";   name = attribute_value -> Name name
    | CONSTANT "before"; name = attribute_value -> Before name
    | CONSTANT "after";  name = attribute_value -> After name
    | CONSTANT "if";     expr = LITERAL -> If expr
    ]];
  pragma : [[ CONSTANT "#line"; l = INTEGER; f = LITERAL ->
    set_fname ~line:(int_of_string l) f ]];
  pred_item : [[ m = i_o; COLON; t = ctype -> (m,t) ]];
  pred : [[ c = const_sym; a = LIST0 pred_item SEP SYMBOL "," ->
    let name = Func.from_string c in
    [ { mname = name; margs = List.map fst a } ],
     (name, List.fold_right (fun (_,t) ty ->
        mkApp (of_ploc loc) [mkCon "->";t;ty]) a (mkCon "prop"))
  ]];
  attributes : [[ COLON; l = LIST1 attribute SEP COLON-> l ]];
  clause :
    [[ attributes = OPT attributes; f = atom; FULLSTOP ->
       let attributes = match attributes with None -> [] | Some x -> x in
       let c = { loc = of_ploc loc; attributes; body = f } in
       [Clause c]
     | cattributes = OPT attributes; RULE; r = chrrule; FULLSTOP ->
       let cattributes = match cattributes with None -> [] | Some x -> x in
       [Chr { r with cattributes } ]
     | pragma -> []
     | LCURLY -> [Begin (of_ploc loc)]
     | RCURLY -> [End (of_ploc loc)]
     | PRED; p = pred; FULLSTOP ->
         let m, (n,t) = p in
         [Type { tloc=of_ploc loc; textern = false; tname = n ; tty = t }; Mode m]
     | TYPE; names = LIST1 const_sym SEP SYMBOL ","; t = type_; FULLSTOP ->
         List.map (fun n ->
           Type { tloc=of_ploc loc; textern=false; tname=Func.from_string n; tty=t })
           names
     | EXTERNAL;
       TYPE; names = LIST1 const_sym SEP SYMBOL ","; t = type_; FULLSTOP ->
         List.map (fun n ->
           Type { tloc=of_ploc loc; textern=true; tname=Func.from_string n; tty=t })
         names
     | EXTERNAL; PRED; p = pred; FULLSTOP ->
         let _, (n,t) = p in (* No mode for ML code *)
         [Type { tloc = of_ploc loc; textern = true; tname = n; tty = t }]
     | MODE; m = LIST1 mode SEP SYMBOL ","; FULLSTOP -> [Mode m]
     | MACRO; b = atom; FULLSTOP ->
         let name, body = desugar_macro b in
         [Macro { mlocation =of_ploc loc; maname = name; mbody = body }]
     | NAMESPACE; ns = CONSTANT; LCURLY ->
         [ Namespace (of_ploc loc, Func.from_string ns) ]
     | CONSTRAINT; names=LIST0 CONSTANT; LCURLY ->
         [ Constraint (of_ploc loc, List.map Func.from_string names) ]
     | MODULE; CONSTANT; FULLSTOP -> []
     | SIG; CONSTANT; FULLSTOP -> []
     | ACCUMULATE; filenames=LIST1 filename SEP SYMBOL ","; FULLSTOP ->
        [Accumulated(parse lp (List.map (fun fn -> fn ^ ".mod") filenames))]
     | IMPORT; filenames=LIST1 CONSTANT SEP SYMBOL ","; FULLSTOP ->
        [Accumulated(parse lp (List.map (fun fn -> fn ^ ".mod") filenames))]
     | ACCUM_SIG; filenames=LIST1 filename SEP SYMBOL ","; FULLSTOP ->
        [Accumulated(parse lp (List.map (fun fn -> fn ^ ".sig") filenames))]
     | USE_SIG; filenames=LIST1 filename SEP SYMBOL ","; FULLSTOP ->
        [Accumulated(parse lp (List.map (fun fn -> fn ^ ".sig") filenames))]
     | SHORTEN; name = CONSTANT; FULLSTOP ->
        [ Shorten(of_ploc loc, Func.from_string name) ]
     | LOCAL; vars = LIST1 const_sym SEP SYMBOL ","; FULLSTOP ->
        List.map (fun x -> mkLocal x) vars
     | LOCAL; vars = LIST1 const_sym SEP SYMBOL ","; type_; FULLSTOP ->
        List.map (fun x -> mkLocal x) vars
     | LOCALKIND; LIST1 const_sym SEP SYMBOL ","; FULLSTOP -> []
     | LOCALKIND; LIST1 const_sym SEP SYMBOL ","; kind; FULLSTOP -> []
     | CLOSED; LIST1 const_sym SEP SYMBOL ","; FULLSTOP -> []
     | CLOSED; LIST1 const_sym SEP SYMBOL ","; type_; FULLSTOP -> []
     | USEONLY; LIST1 const_sym SEP SYMBOL ","; FULLSTOP -> []
     | USEONLY; LIST1 const_sym SEP SYMBOL ","; type_; FULLSTOP -> []
     | EXPORTDEF; LIST1 const_sym SEP SYMBOL ","; FULLSTOP -> []
     | EXPORTDEF; LIST1 const_sym SEP SYMBOL ","; type_; FULLSTOP -> []
     | KIND; names = LIST1 const_sym SEP SYMBOL ","; t = kind; FULLSTOP ->
         List.map (fun n ->
           Type { tloc=of_ploc loc; textern=false; tname=Func.from_string n; tty=t })
         names
     | TYPEABBREV; abbrform; TYPE; FULLSTOP -> []
     | fix = FIXITY; syms = LIST1 const_sym SEP SYMBOL ","; prec = INTEGER; FULLSTOP ->
         List.iter (fun sym ->
           gram_extend (of_ploc loc) {
             fix = fixity_of_string fix;
             sym;
             prec = int_of_string prec
           }) syms;
         []
    ]];
  kind:
    [[ t = TYPE -> mkCon t
     | t = TYPE; a = SYMBOL "->"; k = kind -> mkApp (of_ploc loc) [mkCon a; mkCon t; k]
    ]];
  type_:
    [[ c = ctype -> c
     | s = ctype; a = SYMBOL "->"; t = type_ -> mkApp (of_ploc loc) [mkCon a; s; t]
    ]];
  ctype:
     [ "main" [ c = CONSTANT; l = LIST0 ctype LEVEL "arg" -> 
                  if c = "o" && l = [] then mkCon "prop"
                  else mkApp (of_ploc loc) (mkCon c :: l)
              | CONSTANT "ctype"; s = LITERAL ->
                  mkApp (of_ploc loc) [Const Func.ctypef; mkC (cstring.U.CData.cin s)] ]
     | "arg"  [ c = CONSTANT -> mkCon c
              | LPAREN; t = type_; RPAREN -> t ]
     ];
  abbrform:
    [[ CONSTANT -> ()
     | LPAREN; CONSTANT; LIST1 CONSTANT; RPAREN -> ()
     | LPAREN; abbrform; RPAREN -> ()
    ]];
  goal:
    [[ OPT pragma; p = premise -> of_ploc loc, p ]];
  premise : [[ a = atom -> a ]];
  atom :
   [ "1" [ ]
   | "110"
      [ args = LIST1 atom LEVEL "120" SEP SYMBOL "," ->
          if List.length args > 1 then mkApp (of_ploc loc) (Const Func.andf :: args)
          else List.hd args
      ]
   | "term"
      [ hd = atom; args = LIST1 atom LEVEL "abstterm" ->
         desugar_multi_binder loc (mkApp (of_ploc loc) (hd :: args)) ]
   | "abstterm"
      [ c=CONSTANT; OPT[COLON;type_]; b=OPT[BIND; a = atom LEVEL "1" -> a ] ->
          (match b with None -> mkCon c | Some b -> mkLam c b)
      | u=FRESHUV; OPT[COLON;type_]; b=OPT[BIND; a = atom LEVEL "1" -> a ] ->
          (match b with None -> mkFreshUVar () | Some b ->
           mkLam Func.(show dummyname)  b)
      | s = LITERAL -> mkC (cstring.U.CData.cin s)
      | s = QUOTED -> mkQuoted (of_ploc loc) s
      | s = INTEGER -> mkC (cint.U.CData.cin (int_of_string s))
      | s = FLOAT -> mkC (cfloat.U.CData.cin (float_of_string s))
      | LPAREN; a = atom; RPAREN -> a
      | LCURLY; a = atom; RCURLY -> mkApp (of_ploc loc) [Const Func.spillf;a]
        (* 120 is the first level after 110, which is that of ,
           Warning: keep the hard-coded constant in sync with
           the list_element_prec below :-(
        *)
      | LBRACKET; xs = LIST0 atom LEVEL "120" SEP SYMBOL ",";
          tl = OPT [ PIPE; x = atom LEVEL "1" -> x ]; RBRACKET ->
          let tl = match tl with None -> mkNil | Some x -> x in
          if List.length xs = 0 && tl <> mkNil then 
            raise (Token.Error ("List with no elements cannot have a tail"));
          if List.length xs = 0 then mkNil
          else mkSeq (xs@[tl]) ]
   | "wtf" 
      [ s = ESCAPE -> mkCon s ]
      ];
END

(* 120 is the first level after 110, which is that of , *)
let list_element_prec = 120

let parser_initialized = ref false

let init_loc = {
  Loc.source_name = "";
  source_start = 0;
  source_stop = 0;
  line = -1;
  line_starts_at = 0;
}

let init ~lp_syntax ~paths ~cwd () =
  assert(!parser_initialized = false);
  parsed := [];
  set_tjpath cwd paths;
  List.iter (gram_extend init_loc) lp_syntax;
  parser_initialized := true
;;

let run_parser f x =
  if !parser_initialized = false then U.anomaly "parsing before calling init";
  try f x with
  | Ploc.Exc(l,(Token.Error msg | Stream.Error msg)) ->
      let loc = of_ploc l in
      raise(ParseError(loc,msg))
  | Ploc.Exc(l,e) ->
      let loc = of_ploc l in
      raise(ParseError(loc,"Unexpected exception: " ^ Printexc.to_string e))
  | NotInProlog(loc,s) -> raise (ParseError(loc, "NotInProlog: " ^ s))
;;

let parse_program ~print_accumulated_files filenames : program =
  parse_silent := print_accumulated_files;
  run_parser (parse lp) filenames

let parse_program_from_stream ~print_accumulated_files strm : program =
  parse_silent := print_accumulated_files;
  run_parser (Grammar.Entry.parse lp) strm

let set_last_loc = function
  | None -> ()
  | Some loc -> last_loc := to_ploc { loc with Loc.source_stop = loc.Loc.source_start }

let parse_goal ?loc s : goal =
  set_last_loc loc;
  run_parser (Grammar.Entry.parse goal) (Stream.of_string s)

let parse_goal_from_stream ?loc strm =
  set_last_loc loc;
  run_parser (Grammar.Entry.parse goal) strm

let lp_gramext = [
  { fix = Infixl;	sym = ":-";	prec = 1; };
  { fix = Infixr;	sym = ";";	prec = 100; };
  { fix = Infix;	sym = "?-";	prec = 115; };
  { fix = Infixr;	sym = "->";	prec = 116; };
  { fix = Infixr;	sym = "&";	prec = 120; };
  { fix = Infixr;	sym = "=>";	prec = 129; };
  { fix = Infixl;	sym = "as";	prec = 0; };
  { fix = Infix;	sym = "<";	prec = 130; };
  { fix = Infix;	sym = "=<";	prec = 130; };
  { fix = Infix;	sym = "=";	prec = 130; };
  { fix = Infix;	sym = ">=";	prec = 130; };
  { fix = Infix;	sym = ">";	prec = 130; };
  { fix = Infix;	sym = "i<";	prec = 130; };
  { fix = Infix;	sym = "i=<";	prec = 130; };
  { fix = Infix;	sym = "i>=";	prec = 130; };
  { fix = Infix;	sym = "i>";	prec = 130; };
  { fix = Infix;	sym = "is";	prec = 130; };
  { fix = Infix;	sym = "r<";	prec = 130; };
  { fix = Infix;	sym = "r=<";	prec = 130; };
  { fix = Infix;	sym = "r>=";	prec = 130; };
  { fix = Infix;	sym = "r>";	prec = 130; };
  { fix = Infix;	sym = "s<";	prec = 130; };
  { fix = Infix;	sym = "s=<";	prec = 130; };
  { fix = Infix;	sym = "s>=";	prec = 130; };
  { fix = Infix;	sym = "s>";	prec = 130; };
  { fix = Infix;	sym = "@";	prec = 135; };
  { fix = Infixr;	sym = "::";	prec = 140; };
  { fix = Infix;	sym = "`->";	prec = 141; };
  { fix = Infix;	sym = "`:";	prec = 141; };
  { fix = Infixl;	sym = "^";	prec = 150; };
  { fix = Infixl;	sym = "-";	prec = 150; };
  { fix = Infixl;	sym = "+";	prec = 150; };
  { fix = Infixl;	sym = "i-";	prec = 150; };
  { fix = Infixl;	sym = "i+";	prec = 150; };
  { fix = Infixl;	sym = "r-";	prec = 150; };
  { fix = Infixl;	sym = "r+";	prec = 150; };
  { fix = Infixl;	sym = "/";	prec = 160; };
  { fix = Infixl;	sym = "*";	prec = 160; };
  { fix = Infixl;	sym = "div";	prec = 160; };
  { fix = Infixl;	sym = "i*";	prec = 160; };
  { fix = Infixl;	sym = "mod";	prec = 160; };
  { fix = Infixl;	sym = "r*";	prec = 160; };
  { fix = Prefix;	sym = "~";	prec = 256; };
  { fix = Prefix;	sym = "i~";	prec = 256; };
  { fix = Prefix;	sym = "r~";	prec = 256; };
]
