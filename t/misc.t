use Safe qw(opname opcode ops_to_mask mask_to_ops);

print "1..6\n";

$cpt = new Safe 'Root';
$Root::foo = "not ok 1";
@{$cpt->varglob('bar')} = qw(not ok 2);
${$cpt->varglob('foo')} = "ok 1";
@Root::bar = "ok";
push(@Root::bar, "2"); # Two steps to prevent "Identifier used only once..."

print "$Root::foo\n";
print "@{$cpt->varglob('bar')}\n";

print opname(22) eq "bless" ? "ok 3\n" : "not ok 3\n";
print opcode("bless") == 22 ? "ok 4\n" : "not ok 4\n";

$m1 = $cpt->mask();
$cpt->trap("negate");
$m2 = $cpt->mask();
@masked = mask_to_ops($m1);
print $m2 eq ops_to_mask("negate", @masked) ? "ok 5\n" : "not ok 5\n";
$cpt->untrap(187);
substr($m2, 187, 1) = "\0";
print $m2 eq $cpt->mask() ? "ok 6\n" : "not ok 6\n";
