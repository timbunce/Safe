require Safe;

print "1..9\n";

$foo = "ok 1\n";
%bar = (key => "ok 2\n");
@baz = "o";
push(@baz, "3"); # Two steps to prevent "Identifier used only once..."
$glob = "ok 4\n";
@glob = qw(not ok 9);

$" = 'k ';

sub sayok5 { print "ok 5\n" }

$cpt = new Safe;
$cpt->share(qw($foo %bar @baz *glob &sayok5 $"));

$err = $cpt->reval(q{
    print $foo ? $foo : "not ok 1\n";
    print $bar{key} ? $bar{key} : "not ok 2\n";
    if (@baz) {
	print "@baz\n";
    } else {
	print "not ok 3\n";
    }
    print $glob;
    sayok5();
    $foo =~ s/1/7/;
    $bar{new} = "ok 8\n";
    @glob = qw(ok 9);
});
print $err ? "not ok 6\n#$err" : "ok 6\n";
$" = ' ';
print $foo, $bar{new}, "@glob\n";
