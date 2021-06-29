/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2002-2021, University of Amsterdam
                              VU University Amsterdam
                              SWI-Prolog Solutions b.v.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(prolog_main,
          [ main/0,
            argv_options/3,             % +Argv, -RestArgv, -Options
            cli_parse_debug_options/2,  % +OptionsIn, -Options
            cli_enable_development_system/0
          ]).
:- autoload(library(debug), [debug/1]).
:- autoload(library(pce_dispatch), [pce_dispatch/1]).
:- autoload(library(threadutil), [tspy/1]).

:- dynamic
    interactive/0.

/** <module> Provide entry point for scripts

This library is intended for supporting   PrologScript on Unix using the
=|#!|= magic sequence for scripts using   commandline options. The entry
point main/0 calls the user-supplied predicate  main/1 passing a list of
commandline options. Below is a simle `echo` implementation in Prolog.

```
#!/usr/bin/env swipl

:- initialization(main, main).

main(Argv) :-
    echo(Argv).

echo([]) :- nl.
echo([Last]) :- !,
    write(Last), nl.
echo([H|T]) :-
    write(H), write(' '),
    echo(T).
```

@see	library(optparse) for comprehensive option parsing.
@see	library(prolog_stack) to force backtraces in case of an
	uncaught exception.
@see    XPCE users should have a look at library(pce_main), which
        starts the GUI and processes events until all windows have gone.
*/

:- module_transparent
    main/0.

%!  main
%
%   Call main/1 using the passed  command-line arguments. Before calling
%   main/1  this  predicate  installs  a  signal  handler  for  =SIGINT=
%   (Control-C) that terminates the process with status 1.

main :-
    context_module(M),
    set_signals,
    current_prolog_flag(argv, Av),
    catch_with_backtrace(M:main(Av), Error, throw(Error)),
    (   interactive
    ->  cli_enable_development_system
    ;   true
    ).

set_signals :-
    on_signal(int, _, interrupt).

%!  interrupt(+Signal)
%
%   We received an interrupt.  This handler is installed using
%   on_signal/3.

interrupt(_Sig) :-
    halt(1).

%!  argv_options(+Argv, -RestArgv, -Options) is det.
%
%   Generic transformation of long commandline arguments to options.
%   Each --Name=Value is mapped to Name(Value).   Each plain name is
%   mapped to Name(true), unless Name starts  with =|no-|=, in which
%   case the option is mapped to  Name(false). Numeric option values
%   are mapped to Prolog numbers.
%
%   @see library(optparse) provides a more involved option library,
%   providing both short and long options, help and error handling.
%   This predicate is more for quick-and-dirty scripts.

argv_options([], [], []).
argv_options([H0|T0], R, [H|T]) :-
    sub_atom(H0, 0, _, _, --),
    !,
    (   sub_atom(H0, B, _, A, =)
    ->  B2 is B-2,
        sub_atom(H0, 2, B2, _, Name),
        sub_string(H0, _, A,  0, Value0),
        convert_option(Name, Value0, Value)
    ;   sub_atom(H0, 2, _, 0, Name0),
        (   sub_atom(Name0, 0, _, _, 'no-')
        ->  sub_atom(Name0, 3, _, 0, Name),
            Value = false
        ;   Name = Name0,
            Value = true
        )
    ),
    canonical_name(Name, PlName),
    H =.. [PlName,Value],
    argv_options(T0, R, T).
argv_options([H|T0], [H|R], T) :-
    argv_options(T0, R, T).

convert_option(password, String, String) :- !.
convert_option(_, String, Number) :-
    number_string(Number, String),
    !.
convert_option(_, String, Atom) :-
    atom_string(Atom, String).

canonical_name(Name, PlName) :-
    split_string(Name, "-_", "", Parts),
    atomic_list_concat(Parts, '_', PlName).

%!	cli_parse_debug_options(+OptionsIn, -Options) is det.
%
%       Parse certain commandline options for  debugging and development
%       purposes. Options processed are  below.   Note  that  the option
%       argument is an atom such that these  options may be activated as
%       e.g., ``--debug='http(_)'``.
%
%         - debug(Topic)
%           Call debug(Topic).  See debug/1 and debug/3.
%         - spy(Predicate)
%           Place a spy-point on Predicate.
%         - gspy(Predicate)
%           As spy using the graphical debugger.  See tspy/1.
%         - interactive(true)
%           Start the Prolog toplevel after main/1 completes.

cli_parse_debug_options([], []).
cli_parse_debug_options([H|T0], Opts) :-
    debug_option(H),
    !,
    cli_parse_debug_options(T0, Opts).
cli_parse_debug_options([H|T0], [H|T]) :-
    cli_parse_debug_options(T0, T).

debug_option(interactive(true)) :-
    asserta(interactive).
debug_option(debug(TopicS)) :-
    term_string(Topic, TopicS),
    debug(Topic).
debug_option(spy(Atom)) :-
    atom_pi(Atom, PI),
    spy(PI).
debug_option(gspy(Atom)) :-
    atom_pi(Atom, PI),
    tspy(PI).

atom_pi(Atom, Module:PI) :-
    split(Atom, :, Module, PiAtom),
    !,
    atom_pi(PiAtom, PI).
atom_pi(Atom, Name//Arity) :-
    split(Atom, //, Name, Arity),
    !.
atom_pi(Atom, Name/Arity) :-
    split(Atom, /, Name, Arity),
    !.
atom_pi(Atom, _) :-
    format(user_error, 'Invalid predicate indicator: "~w"~n', [Atom]),
    halt(1).

split(Atom, Sep, Before, After) :-
    sub_atom(Atom, BL, _, AL, Sep),
    !,
    sub_atom(Atom, 0, BL, _, Before),
    sub_atom(Atom, _, AL, 0, AfterAtom),
    (   atom_number(AfterAtom, After)
    ->  true
    ;   After = AfterAtom
    ).


%!  cli_enable_development_system
%
%   Re-enable the development environment. Currently  re-enables xpce if
%   this was loaded, but not  initialised   and  causes  the interactive
%   toplevel to be re-enabled.
%
%   This predicate may  be  called  from   main/1  to  enter  the Prolog
%   toplevel  rather  than  terminating  the  application  after  main/1
%   completes.

cli_enable_development_system :-
    on_signal(int, _, debug),
    set_prolog_flag(xpce_threaded, true),
    set_prolog_flag(message_ide, true),
    (   current_prolog_flag(xpce_version, _)
    ->  call(pce_dispatch([]))
    ;   true
    ),
    set_prolog_flag(toplevel_goal, prolog).


		 /*******************************
		 *          IDE SUPPORT		*
		 *******************************/

:- multifile
    prolog:called_by/2.

prolog:called_by(main, [main(_)]).
