require Safe;

print "1..6\n";

# Set up a package namespace of things to be visible to the unsafe code
$Root::foo = "visible";

$bar = "invisible";

# Stop perl from moaning about identifies which are apparently only used once
$Root::foo .= "";
$bar .= "";

$cpt = new Safe "Root";
$error = $cpt->reval(q{
    print $foo eq 'visible' ? "ok 1\n" : "not ok 1\n";
    print $main::foo  eq 'visible' ? "ok 2\n" : "not ok 2\n";
    print defined($bar) ? "not ok 3\n" : "ok 3\n";
    print defined($::bar) ? "not ok 4\n" : "ok 4\n";
    print defined($main::bar) ? "not ok 5\n" : "ok 5\n";
});
print $error ? "not ok 6\n" : "ok 6\n";
