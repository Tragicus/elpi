(* elpi: embedded lambda prolog interpreter                                  *)
(* license: GNU Lesser General Public License Version 2.1 or later           *)
(* ------------------------------------------------------------------------- *)

(* This module provides all the built-in predicates and evaluable constants. *)

open Elpi_API.BuiltIn

(* Builtins that are part of the language, like "is" or "!" *)
val core_builtins : declaration list

(* Basic I/O facilities *)
val io_builtins : declaration list

(* Builtins to be backward compatible with Teyjus, eg extra i/o predicates *)
val lp_builtins : declaration list

(* Elpi predicates like print *)
val elpi_builtins : declaration list

(* Elpi non-logical predicates like var, new_int ... *)
val elpi_nonlogical_builtins : declaration list

(* Elpi stdlib *)
val elpi_stdlib : declaration list

(* All the above, to be used as a sane default in Setup.init *)
val std_declarations : declaration list
val std_builtins : Elpi_API.Setup.builtins

(* Type descriptors for built-in predicates *)
val pair : 'a Elpi_API.Conversion.t -> 'b Elpi_API.Conversion.t -> ('a * 'b) Elpi_API.Conversion.t
val option : 'a Elpi_API.Conversion.t -> 'a option Elpi_API.Conversion.t
val bool : bool Elpi_API.Conversion.t

(* The string is the "file name" *)
val in_stream  : (in_channel * string) Elpi_API.Conversion.t
val out_stream : (out_channel * string) Elpi_API.Conversion.t
