#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = Safe	PACKAGE = Safe

void
safe_call_sv(package, mask, codesv)
	char *	package
	SV *	mask
	SV *	codesv
    CODE:
	int i;
	char *str;
	STRLEN len;

	ENTER;
	SAVETMPS;
	save_hptr(&defstash);
	save_aptr(&endav);
	SAVEPPTR(op_mask);
	Newz(666, op_mask, MAXO, char);
	SAVEFREEPV(op_mask);
	str = SvPV(mask, len);
	for (i = 0; i < MAXO && i < len; i++)
	    op_mask[i] = str[i];
	defstash = gv_stashpv(package, TRUE);
	endav = (AV*)sv_2mortal((SV*)newAV()); /* Ignore END blocks for now */
	GvHV(gv_fetchpv("main::", TRUE, SVt_PVHV)) = defstash;
	PUSHMARK(sp);
	i = perl_call_sv(codesv, G_SCALAR|G_EVAL);
	SPAGAIN;
	ST(0) = i ? newSVsv(POPs) : &sv_undef;
	PUTBACK;
	FREETMPS;
	LEAVE;
	sv_2mortal(ST(0));

void
op_mask()
    CODE:
	ST(0) = sv_newmortal();
	if (op_mask)
	    sv_setpvn(ST(0), op_mask, MAXO);

void
mask_to_ops(mask)
	SV *	mask
    PPCODE:
	STRLEN len;
	char *maskstr = SvPV(mask, len);
	int i;
	for (i = 0; i < len && i < MAXO; i++)
	    if (maskstr[i])
		XPUSHs(sv_2mortal(newSVpv(op_name[i], 0)));

void
ops_to_mask(...)
    CODE:
	int i, j;
	char *mask, *op;
	Newz(666, mask, MAXO, char);
	for (i = 0; i < items; i++)
	{
	    op = SvPV(ST(i), na);
	    for (j = 0; j < MAXO && strNE(op, op_name[j]); j++) /* nothing */ ;
	    if (j < MAXO)
		mask[j] = 1;
	    else
	    {
		Safefree(mask);
		croak("bad op name \"%s\" in mask", op);
	    }
	}
	ST(0) = sv_newmortal();
	sv_usepvn(ST(0), mask, MAXO);

void
opname(...)
    PPCODE:
	int i, opcode;
	for (i = 0; i < items; i++)
	{
	    opcode = SvIV(ST(i));
	    if (opcode < 0 || opcode >= MAXO)
		croak("opcode out of range");
	    XPUSHs(sv_2mortal(newSVpv(op_name[opcode], 0)));
	}

void
opcode(...)
    PPCODE:
	int i, j;
	char *op;
	for (i = 0; i < items; i++)
	{
	    op = SvPV(ST(i), na);
	    for (j = 0; j < MAXO && strNE(op, op_name[j]); j++) /* nothing */ ;
	    if (j == MAXO)
		croak("bad op name \"%s\"", op);
	    XPUSHs(sv_2mortal(newSViv(j)));
	}

int
MAXO()
    CODE:
	RETVAL = MAXO;
    OUTPUT:
	RETVAL
