require Safe;

print "1..1\n";

$cpt = new Safe;
$err = $cpt->reval(q{
    system("echo not ok 1");
});
if ($err =~ /^system trapped by operation mask/) {
    print "ok 1\n";
} else {
    print "not ok 1\n";
}
