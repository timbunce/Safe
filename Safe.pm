package Safe;

require 5.002;

require Exporter;
require DynaLoader;
use Carp;
use subs qw(empty_opset full_opset MAXO define_op_tag ops_to_opset opset_to_ops opdesc);

$VERSION = "2.01";

@ISA = qw(Exporter DynaLoader);
@EXPORT_OK = qw(ops_to_opset opset_to_ops opdesc
		empty_opset full_opset MAXO define_optag);


my $default_root = 0;

sub new {
    my($class, $root, $mask) = @_;
    my $obj = {};
    bless $obj, $class;
    $obj->{Root} = defined($root) ? $root : ("Safe::Root".$default_root++);
    # use permit/deny methods instead till interface issues resolved
    croak "Mask parameter to new no longer supported" if defined $mask;
    $obj->permit_only(':default');
    # We must share $_ and @_ with the compartment or else ops such
    # as split, length and so on won't default to $_ properly, nor
    # will passing argument to subroutines work (via @_). In fact,
    # for reasons I don't completely understand, we need to share
    # the whole glob *_ rather than $_ and @_ separately, otherwise
    # @_ in non default packages within the compartment don't work.
    *{$obj->root . "::_"} = *_;
    return $obj;
}

sub DESTROY {
    my $obj = shift;
    my $root = $obj->root();
    if ($root =~ /^Safe::(Root\d+)$/){
	$root = $1;
	delete ${"Safe::"}{"$root\::"};
    }
}

sub root {
    my $obj = shift;
    croak("Safe root method now read-only") if @_;
    return $obj->{Root};
}


sub mask {
    my $obj = shift;
    return $obj->{Mask} unless @_;
    $obj->deny_only(shift);
}

# v1 compatibility methods
sub trap   { shift->deny(@_)   }
sub untrap { shift->permit(@_) }


sub dump_opset {
    my $obj = shift;
    print unpack("h*",$obj->{Mask}),"\n";
}



sub share {
    my $obj = shift;
    my $root = $obj->root();
    my $caller = caller;
    my ($var, $arg);
    foreach $arg (@_) {
	($var = $arg) =~ s/^(\W)//;
	*{$root."::$var"} = ($1 eq '$') ? \${$caller."::$var"}
			  : ($1 eq '@') ? \@{$caller."::$var"}
			  : ($1 eq '%') ? \%{$caller."::$var"}
			  : ($1 eq '*') ?  *{$caller."::$var"}
			  : ($1 eq '&') ? \&{$caller."::$var"}
			  : (!$1)       ? \&{$caller."::$var"}
			  : croak(qq(No such variable type for "$1$var"));
    }
}

sub varglob {
    my ($obj, $var) = @_;
    return *{$obj->root()."::$var"};
}


sub reval {
    my ($obj, $expr) = @_;
    my $root = $obj->{Root};

    # Create anon sub ref in root of compartment
    # Uses a closure to pass in the code to be executed
    # (eval on one line to keep line numbers straight)
    my $evalsub = eval
	    sprintf('package %s; sub { eval $expr; }', $root);
    return _safe_call_sv($root, $obj->{Mask}, $evalsub);
}

sub rdo {
    my ($obj, $file) = @_;
    my $root = $obj->{Root};

    my $evalsub = eval
	    sprintf('package %s; sub { do $file }', $root);
    return _safe_call_sv($root, $obj->{Mask}, $evalsub);
}


sub _init_default_tags {
    local($/) = "\n=";	# pod sections
    my(%all, %seen);
    @all{opset_to_ops(full_opset)} = (); # keys only

    while(<DATA>) {
	next unless m/^###START###/m .. m/^###END###/m;
	next unless m/^item\s+(:\w+)/;
	my $tag = $1;

	# split into lines, keep only indented lines
	my @lines = grep { s/^\s+// } split(/\n/);
	foreach(@lines) { s/\s+--.*// } # delete comments
	my @ops   = map { split /\s+/ } @lines;

	foreach(@ops) {
	    my $seen;
	    warn "$tag: $_ already tagged in $seen\n"
		if $seen=$seen{$_};
	    $seen{$_} = $tag;
	    delete $all{$_};
	}
	my $opset = ops_to_opset(@ops);
	define_optag($tag, $opset);
    }
    close(DATA);
    warn "Untagged opnames: ".join(' ',keys %all)."\n" if %all;
}

bootstrap Safe $VERSION;

_init_default_tags();

1;

__DATA__

=head1 NAME

Safe - Compile and execute code in restricted compartments

=head1 DESCRIPTION

The Safe extension module allows the creation of compartments
in which perl code can be evaluated. Each compartment has

=over 8

=item a new namespace

The "root" of the namespace (i.e. "main::") is changed to a
different package and code evaluated in the compartment cannot
refer to variables outside this namespace, even with run-time
glob lookups and other tricks.

Code which is compiled outside the compartment can choose to place
variables into (or I<share> variables with) the compartment's namespace
and only that data will be visible to code evaluated in the
compartment.

By default, the only variables shared with compartments are the
"underscore" variables $_ and @_ (and, technically, the less frequently
used %_, the _ filehandle and so on). This is because otherwise perl
operators which default to $_ will not work and neither will the
assignment of arguments to @_ on subroutine entry.

=item an operator mask

Each compartment has an associated "operator mask". Recall that
perl code is compiled into an internal format before execution.
Evaluating perl code (e.g. via "eval" or "do 'file'") causes
the code to be compiled into an internal format and then,
provided there was no error in the compilation, executed.
Code evaulated in a compartment compiles subject to the
compartment's operator mask. Attempting to evaulate code in a
compartment which contains a masked operator will cause the
compilation to fail with an error. The code will not be executed.

By default, the operator mask for a newly created compartment masks
out all operations which give "access to the system" in some sense.
This includes masking off operators such as I<system>, I<open>,
I<chown>, and I<shmget> but does not mask off operators such as
I<print>, I<sysread> and I<E<lt>HANDLE<gt>>. Those file operators
are allowed since for the code in the compartment to have access
to a filehandle, the code outside the compartment must have explicitly
placed the filehandle variable inside the compartment.

(Note: the definition of the default ops is not yet finalised.)

Since it is only at the compilation stage that the operator mask
applies, controlled access to potentially unsafe operations can
be achieved by having a handle to a wrapper subroutine (written
outside the compartment) placed into the compartment. For example,

    $cpt = new Safe;
    sub wrapper {
        # vet arguments and perform potentially unsafe operations
    }
    $cpt->share('&wrapper');

=back

Confusingly the term 'operator mask' is used to refer to the 'masking
out' of operators during compilation and also to a value defining a set
of operators. The term 'opset' is being more widely used to refer to
the latter but you may still come across mask being used instead.

=head2 WARNING

The interface to the Safe module has changed quite dramatically since
version 1 (as supplied with Perl5.002). Study these pages carefully if
you have code written to use Safe version 1 because you will need to
makes changes.


=head2 Operator Names and Operator Lists

XXX

The canonical list of operator names is the contents of the array
op_name defined and initialised in file F<opcode.h> of the Perl
source distribution (and installed into the perl library).

Each operator has both a terse name and a more verbose or recognisable
descriptive name. The opdesc function can be used to return a list of
descriptions for a list of operators.

Many of the functions and methods listed below take a lists of
operators as parameters. Operator lists can be made up of several
types of elements. Each element can be one of

=over 8

=item an operator name (opname)

XXX

=item an operator tag name (optag)

Operator tags can be used to refer to groups (or sets) of operators.
Tag names always being with a colon. The Safe module defines several
optags and the user can define others using the define_optag function.

=item a negated opname or optag

XXX

=item an operator set (opset)

An I<opset> as an opaque binary string of approximately 43 bytes which
holds a set or zero or more operators.

The ops_to_opset and opset_to_ops functions can be used to convert from
a list of operators to an opset (and I<vice versa>).

Wherever a list of operators can be given you can use one or more opsets.

=back



=head2 Methods in class Safe

To create a new compartment, use

    $cpt = new Safe;

Optional argument is (NAMESPACE), where NAMESPACE is the root namespace
to use for the compartment (defaults to "Safe::Root0", incremented for
each new compartment).

Note that version 1.00 of the Safe module supported a second optional
parameter, MASK.  That functionality has been withdrawn pending deeper
consideration. Use the permit and deny methods described below.

The following methods can then be used on the compartment
object returned by the above constructor. The object argument
is implicit in each case.


=over 8

=item permit (OP, ...)

Permit the listed operators to be used when compiling code in the
compartment (in I<addition> to any operators already permitted).

=item permit_only (OP, ...)

Permit I<only> the listed operators to be used when compiling code in
the compartment (I<no> other operators are permitted).

=item deny (OP, ...)

Deny the listed operators from being used when compiling code in the
compartment (other operators may still be permitted).

=item deny_only (OP, ...)

Deny I<only> the listed operators from being used when compiling code
in the compartment (I<all> other operators will be permitted).

=item trap (OP, ...)

=item untrap (OP, ...)

The trap and untrap methods are synonyms for deny and permit
respectfully.  They are provided for backwards compatibility and
should not be used in new code.

=item share (VARNAME, ...)

This shares the variable(s) in the argument list with the compartment.
This is almost identical to exporting variables using the Exporter
module.

Each VARNAME must be the B<name> of a variable with a leading type
identifier included. A bareword is treated as a function name. Examples
of legal names are '$foo' for a scalar, '@foo' for an array,
'%foo' for a hash, '&foo' or 'foo' for a subroutine and '*foo' for a
glob (i.e.  all symbol table entries associated with "foo", including
scalar, array, hash, sub and filehandle).

=item varglob (VARNAME)

This returns a glob reference for the symbol table entry of VARNAME in
the package of the compartment. VARNAME must be the B<name> of a
variable without any leading type marker. For example,

    $cpt = new Safe 'Root';
    $Root::foo = "Hello world";
    # Equivalent version which doesn't need to know $cpt's package name:
    ${$cpt->varglob('foo')} = "Hello world";


=item reval (STRING)

This evaluates STRING as perl code inside the compartment.

The code can only see the compartment's namespace (as returned by the
B<root> method). The compartment's root package appears to be the
C<main::> package to the code inside the compartment.

Any attempt by the code in STRING to use an operator which is not permitted
by the compartment will cause an error (at run-time of the main program
but at compile-time for the code in STRING).  The error is of the form
"%s trapped by operation mask operation...".

If an operation is trapped in this way, then the code in STRING will
not be executed. If such a trapped operation occurs or any other
compile-time or return error, then $@ is set to the error message, just
as with an eval().

If there is no error, then the method returns the value of the last
expression evaluated, or a return statement may be used, just as with
subroutines and B<eval()>. The context (list or scalar) is determined
by the caller as usual.

This behaviour differs from the beta distribution of the Safe extension
where earlier versions of perl made it hard to mimic the return
behaviour of the eval() command and the context was always scalar.

Some points to note:

If the entereval/leaveeval ops are permitted then the code can use them
to 'hide' code which might use denied ops. This is not a major problem
since when the code tries to execute the eval it will fail because the
opmask is still in effect. However this technique would allow clever,
and possibly harmful, code to 'probe' the boundaries of what is possible.

Any string eval which is executed by code executing in a compartment,
or by code called from code executing in a compartment, will be eval'd
in the namespace of the compartment. This is potentially a serious
problem.

Consider a function foo() in package bar compiled outside a compartment
but shared with it. Assume the compartment has a root package called
'Root'. If foo() contains an eval statement like eval '$baz = 1' then,
normally, $bar::foo will be set to 1.  If foo() is called from the
compartment (by whatever means) then instead of setting $bar::foo, the
eval will actually set $Root::bar::foo.

This can easily be demonstrated by using a module, such as the Socket
module, which uses eval "..." as part of an AUTOLOAD function. You can
'use' the module outside the compartment and share an (autoloaded)
function with the compartment. If an autoload is triggered by code in
the compartment, or by any code anywhere that is called by any means
from the compartment, then the eval in the Socket module's AUTOLOAD
function happens in the namespace of the compartment. Any variables
created or used by the eval'd code are now under the control of
the code in the compartment.

A similar effect applies to I<all> runtime symbol lookups in code
called from a compartment but not compiled within it.



=item rdo (FILENAME)

This evaluates the contents of file FILENAME inside the compartment.
See above documentation on the B<reval> method for further details.

=item root (NAMESPACE)

This method returns the name of the package that is the root of the
compartment's namespace.

Note that this behaviour differs from version 1.00 of the Safe module
where the root module could be used to change the namespace. That
functionality has been withdrawn pending deeper consideration.

=item mask (MASK)

This is a get-or-set method for the compartment's operator mask.

With no MASK argument present, it returns the current operator mask of
the compartment.

With the MASK argument present, it sets the operator mask for the
compartment (equivalent to calling the deny_only method).

=back


=head2 Subroutines in package Safe

The Safe package contains subroutines for manipulating operator names
tags and sets. All are available for export by the package.

=over 8

=item ops_to_opset (OP, ...)

This takes a list of operators and returns an opset representing
precisely those operators.

=item opset_to_ops (OPSET)

This takes an opset and returns a list of operator names corresponding
to those operators in the set.

=item full_opset

This just returns opset which includes all operators.

=item empty_opset

This just returns an opset which contains no operators.

This is useful if you want a compartment to make use of the namespace
protection features but do not want the default restrictive mask.

=item define_optag (OPTAG, OPSET)

Define OPTAG as a symbolic name for OPSET. Optag names always start
with a colon C<:>. The optag name used must not be defined already
(define_optag will croak if it is already defined). Optag names are
global to the perl process and optag definitions cannot be altered or
deleted once defined.

It is strongly recommended that applications using Safe should use a
leading capital letter on their tag names since lowercase names are
reserved for use by the Safe module. If using Safe within a module
you should prefix your tags names with the name of your module to
ensure uniqueness.


=item opdesc (OP, ...)

This takes a list of operators and returns the corresponding list of
operator descriptions.

=back


=head2 Some Safety Issues

This section is currently just an outline of some of the things code in
a compartment might do (intentionally or unintentionally) which can
have an effect outside the compartment.

=over 8

=item Memory

Consuming all (or nearly all) available memory.

=item CPU

Causing infinite loops etc.

=item Snooping

Copying private information out of your system. Even something as
simple as your user name is of value to others. Much useful information
could be gleaned from your environment variables for example.

=item Signals

Causing signals (especially SIGFPE and SIGALARM) to affect your process.

Setting up a signal handler will need to be carefully considered
and controlled.  What mask is in effect when a signal handler
gets called?  If a user can get an imported function to get an
exception and call the user's signal handler, does that user's
restricted mask get re-instated before the handler is called?
Does an imported handler get called with its original mask or
the user's one?

=item State Changes

Ops such as chdir obviously effect the process as a whole and not just
the code in the compartment. Ops such as rand and srand have a similar
but more subtle effect.

=back

=cut

###START### special marker for automatic opcode extraction

=head1 Opcode Tags

=over 5

=item :base_core

    null stub scalar pushmark wantarray const defined undef

    rv2sv sassign

    rv2av aassign aelem aelemfast aslice

    rv2hv helem hslice each values keys exists -- no delete here

    preinc i_preinc predec i_predec postinc i_postinc postdec i_postdec
    int hex oct abs pow multiply i_multiply divide i_divide modulo
    i_modulo add i_add subtract i_subtract

    left_shift right_shift bit_and bit_xor bit_or negate i_negate
    not complement

    lt i_lt gt i_gt le i_le ge i_ge eq i_eq ne i_ne ncmp i_ncmp
    slt sgt sle sge seq sne scmp

    substr vec stringify study pos length index rindex ord chr

    ucfirst lcfirst uc lc quotemeta trans chop schop chomp schomp

    splice push pop shift unshift reverse

    cond_expr flip flop andassign orassign and or xor

    lineseq nextstate unstack scope enter leave entersub leavesub
    return method

    warn die

	leaveeval -- needed for Safe to operate

=item :base_mem

These memory related ops are not included in :base_core because they
can easily be used to implement a resource attack (e.g., consume all
available memory).

    concat repeat join

    anonlist anonhash

Note that despite the existance of this optag a memory resource attack
may still be possible using only :base_core ops.

Disabling these ops is a I<very> heavy handed way to attempt to prevent
a memory resource attack. It's probable that a specific memory limit
mechanism will be added to perl in the near future.

=item :base_loop

These loop ops are not included in :base_core because they can easily be
used to implement a resource attack (e.g., consume all available CPU time).

    grepstart grepwhile
    mapstart mapwhile
    enteriter iter
    enterloop leaveloop
    last next redo

=item :base_orig

These are a hotchpotch of opcode still waiting to be considered

    gvsv gv gelem

    padsv padav padhv padany

    pushre

    rv2gv av2arylen rv2cv anoncode prototype refgen
    srefgen ref bless

    glob readline rcatline

    regcmaybe regcomp match subst substcont

    sprintf formline

    crypt

    delete -- hash elem

    split list lslice

    range

    reset

    caller dbstate goto

    tie untie

    dbmopen dbmclose sselect select getc read enterwrite leavewrite
    prtf print sysread syswrite send recv eof tell seek truncate fcntl
    sockpair bind connect listen accept shutdown gsockopt
    getsockname

    ftrwrite ftsvtx

    open_dir readdir closedir telldir seekdir rewinddir

    getppid getpgrp setpgrp getpriority setpriority time tms localtime gmtime

    entertry leavetry

    ghbyname ghbyaddr ghostent gnbyname gnbyaddr gnetent gpbyname
    gpbynumber gprotoent gsbyname gsbyport gservent shostent snetent
    sprotoent sservent ehostent enetent eprotoent eservent

    gpwnam gpwuid gpwent spwent epwent ggrnam ggrgid ggrent sgrent
    egrent


=item :base_math

These ops are not included in :base_core because of the risk of them being
used to generate floating point exceptions (which would have to be caught
using a $SIG{FPE} handler).

    atan2 sin cos exp log sqrt

These ops are not included in :base_core because they have an effect
beyond the scope of the compartment.

    rand srand

=item :default

The default set of ops allowed in a compartment.  (The current ops
allowed is unstable while development continues. It will change.)

    :base_core :base_mem :base_loop :base_orig

=item :subprocess

    backtick system

    fork

    wait waitpid

=item :ownprocess

    exec exit dump syscall kill

=item :filesys_open

    sysopen open close umask

=item :filesys_read

    stat lstat readlink

    ftatime ftblk ftchr ftctime ftdir fteexec fteowned fteread
    ftewrite ftfile ftis ftlink ftmtime ftpipe ftrexec ftrowned
    ftrread ftsgid ftsize ftsock ftsuid fttty ftzero

    fttext ftbinary

    fileno

=item :filesys_write

    link unlink rename symlink

    mkdir rmdir

    utime chmod chown

=item :others

This tag holds groups of assorted specialist opcodes that don't warrant
having optags defined for them.

SystemV Interprocess Communications:

    msgctl msgget msgrcv msgsnd

    semctl semget semop

    shmctl shmget shmread shmwrite

=item :still_to_be_decided

    chdir
    chroot
    require dofile 
    binmode
    flock ioctl
    getlogin
    pipe_op socket getpeername ssockopt 
    sleep alarm
    sort
    tied
    pack unpack
    entereval -- can be used to hide code

=item :foo

Just an example to show and test negation

    :default !spwent !sgrent

=back

=cut

###END### special marker for automatic opcode extraction

=head2 AUTHOR

Originally designed and implemented by Malcolm Beattie,
mbeattie@sable.ox.ac.uk.

Optags and other changes added by Tim Bunce <Tim.Bunce@ig.co.uk>.

=cut

