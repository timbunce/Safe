/*
 * This file was generated automatically by xsubpp version 1.9 from the 
 * contents of Safe.xs. Don't edit this file, edit Safe.xs instead.
 *
 *	ANY CHANGES MADE HERE WILL BE LOST! 
 *
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

XS(XS_Safe_safe_call_sv)
{
    dXSARGS;
    if (items != 3) {
	croak("Usage: Safe::safe_call_sv(package, mask, codesv)");
    }
    {
	char *	package = (char *)SvPV(ST(0),na);
	SV *	mask = ST(1);
	SV *	codesv = ST(2);
	int i;

	char *str;

	STRLEN len;


	ENTER;

	SAVETMPS;

	save_hptr(&defstash);

	SAVEPPTR(op_mask);

	Newz(666, op_mask, MAXO, char);

	SAVEFREEPV(op_mask);

	str = SvPV(mask, len);

	for (i = 0; i < MAXO && i < len; i++)

	    op_mask[i] = str[i];

	defstash = gv_stashpv(package, TRUE);

	GvHV(gv_fetchpv("main::", TRUE, SVt_PVHV)) = defstash;

	PUSHMARK(sp);

	i = perl_call_sv(codesv, G_SCALAR|G_EVAL);

	SPAGAIN;

	ST(0) = i ? newSVsv(POPs) : &sv_undef;

	PUTBACK;

	FREETMPS;

	LEAVE;

	sv_2mortal(ST(0));

    }
    XSRETURN(1);
}

XS(XS_Safe_op_mask)
{
    dXSARGS;
    if (items != 0) {
	croak("Usage: Safe::op_mask()");
    }
    {
	ST(0) = sv_newmortal();

	if (op_mask)

	    sv_setpvn(ST(0), op_mask, MAXO);

    }
    XSRETURN(1);
}

XS(XS_Safe_mask_to_ops)
{
    dXSARGS;
    if (items != 1) {
	croak("Usage: Safe::mask_to_ops(mask)");
    }
    SP -= items;
    {
	SV *	mask = ST(0);
	STRLEN len;

	char *maskstr = SvPV(mask, len);

	int i;

	for (i = 0; i < len && i < MAXO; i++)

	    if (maskstr[i])

		XPUSHs(sv_2mortal(newSVpv(op_name[i], 0)));

	PUTBACK;
	return;
    }
}

XS(XS_Safe_ops_to_mask)
{
    dXSARGS;
    if (items < 0) {
	croak("Usage: Safe::ops_to_mask(...)");
    }
    {
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

    }
    XSRETURN(1);
}

XS(XS_Safe_opname)
{
    dXSARGS;
    if (items < 0) {
	croak("Usage: Safe::opname(...)");
    }
    SP -= items;
    {
	int i, opcode;

	for (i = 0; i < items; i++)

	{

	    opcode = SvIV(ST(i));

	    if (opcode < 0 || opcode >= MAXO)

		croak("opcode out of range");

	    XPUSHs(sv_2mortal(newSVpv(op_name[opcode], 0)));

	}

	PUTBACK;
	return;
    }
}

XS(XS_Safe_opcode)
{
    dXSARGS;
    if (items < 0) {
	croak("Usage: Safe::opcode(...)");
    }
    SP -= items;
    {
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

	PUTBACK;
	return;
    }
}

XS(XS_Safe_MAXO)
{
    dXSARGS;
    if (items != 0) {
	croak("Usage: Safe::MAXO()");
    }
    {
	int	RETVAL;
	RETVAL = MAXO;

	ST(0) = sv_newmortal();
	sv_setiv(ST(0), (IV)RETVAL);
    }
    XSRETURN(1);
}

XS(boot_Safe)
{
    dXSARGS;
    char* file = __FILE__;

    newXS("Safe::safe_call_sv", XS_Safe_safe_call_sv, file);
    newXS("Safe::op_mask", XS_Safe_op_mask, file);
    newXS("Safe::mask_to_ops", XS_Safe_mask_to_ops, file);
    newXS("Safe::ops_to_mask", XS_Safe_ops_to_mask, file);
    newXS("Safe::opname", XS_Safe_opname, file);
    newXS("Safe::opcode", XS_Safe_opcode, file);
    newXS("Safe::MAXO", XS_Safe_MAXO, file);
    ST(0) = &sv_yes;
    XSRETURN(1);
}
