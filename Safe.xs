#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* maxo shouldn't differ from MAXO but leave room anyway (see BOOT:)	*/
#define OP_MASK_BUF_SIZE (MAXO + 100)

static HV *op_named_bits;	/* cache shared for whole process	*/
static SV *opset_all;		/* mask with all bits set		*/
static IV  opset_len;		/* length of opmasks in bytes		*/
static int safe_debug = 0;

static SV  *new_opset _((SV *old_opset));
static int  verify_opset _((SV *opset, int fatal));
static void set_opset_bits _((char *bitmap, SV *bitspec, int on, char *opname));
static void put_op_bitspec _((char *optag,  STRLEN len, SV *opset));
static SV  *get_op_bitspec _((char *opname, STRLEN len, int fatal));


/* Initialise our private op_named_bits HV.
 * It is first loaded with the name and number of each perl operator.
 * Then the builtin tags :none and :all are added.
 * Safe.pm loads the standard optags from __DATA__
 */

static void
op_names_init()
{
    int i;
    STRLEN len;
    char *opname;
    char *bitmap;

    op_named_bits = newHV();
    for(i=0; i < maxo; ++i) {
	hv_store(op_named_bits, op_name[i],strlen(op_name[i]),
		Sv=newSViv(i), 0);
	SvREADONLY_on(Sv);
    }

    put_op_bitspec(":none",0, sv_2mortal(new_opset(Nullsv)));

    opset_all = new_opset(Nullsv);
    bitmap = SvPV(opset_all, len);
    i = len-1; /* deal with last byte specially, see below */
    while(i-- > 0)
	bitmap[i] = 0xFF;
    /* Take care to set the right number of bits in the last byte */
    bitmap[len-1] = ~(~0 << (maxo & 0x07));
    put_op_bitspec(":all",0, opset_all); /* don't mortalise */
}


/* Store a new tag definition. Always a mask.
 * The tag must not already be defined.
 * SV *mask is copied not referenced.
 */

static void
put_op_bitspec(optag, len, mask)
    char *optag;
    STRLEN len;
    SV *mask;
{
    SV **svp;
    verify_opset(mask,1);
    if (!len)
	len = strlen(optag);
    svp = hv_fetch(op_named_bits, optag, len, 1);
    if (SvOK(*svp))
	croak("Opcode tag \"%s\" already defined", optag);
    sv_setsv(*svp, mask);
    SvREADONLY_on(*svp);
}



/* Fetch a 'bits' entry for an opname or optag (IV/PV).
 * Note that we return the actual entry for speed.
 * Always sv_mortalcopy() if returing it to user code.
 */

static SV *
get_op_bitspec(opname, len, fatal)
    char *opname;
    STRLEN len;
    int fatal;
{
    SV **svp;
    if (!len)
	len = strlen(opname);
    svp = hv_fetch(op_named_bits, opname, len, 0);
    if (!svp || !SvOK(*svp)) {
	if (!fatal)
	    return Nullsv;
	if (*opname == ':')
	    croak("Unknown operator tag \"%s\"", opname);
	if (*opname == '!')	/* XXX here later, or elsewhere? */
	    croak("Can't negate operators here (\"%s\")", opname);
	if (isALPHA(*opname))
	    croak("Unknown operator name \"%s\"", opname);
	croak("Unknown operator prefix \"%s\"", opname);
    }
    return *svp;
}



static SV *
new_opset(old_opset)
    SV *old_opset;
{
    SV *opset;
    if (old_opset) {
	verify_opset(old_opset,1);
	opset = newSVsv(old_opset);
    }
    else {
	opset = newSV(opset_len);
	Zero(SvPVX(opset), opset_len, char);
	SvCUR_set(opset, opset_len);
	(void)SvPOK_only(opset);
    }
    /* not mortalised here */
    return opset;
}


static int
verify_opset(opset, fatal)
    SV *opset;
    int fatal;
{
    char *err = Nullch;
    if      (!SvOK(opset))              err = "undefined";
    else if (!SvPOK(opset))             err = "wrong type";
    else if (SvCUR(opset) != opset_len) err = "wrong size";
    if (err && fatal) {
	croak("Invalid opset: %s", err);
    }
    return !err;
}


static void
set_opset_bits(bitmap, bitspec, on, opname)
    char *bitmap;
    SV *bitspec;
    int on;
    char *opname;
{
    if (SvIOK(bitspec)) {
	int myopcode = SvIV(bitspec);
	int offset = myopcode >> 3;
	int bit    = myopcode & 0x07;
	if (myopcode >= maxo || myopcode < 0)
	    croak("panic: opcode \"%s\" value %d is invalid", opname, myopcode);
	if (safe_debug >= 2)
	    warn("set_opset_bits bit %2d (off=%d, bit=%d) %s on\n",
			myopcode, offset, bit, opname, (on)?"on":"off");
	if (on)
	    bitmap[offset] |= 1 << bit;
	else
	    bitmap[offset] &= ~(1 << bit);
    }
    else if (SvPOK(bitspec) && SvCUR(bitspec) == opset_len) {

	STRLEN len;
	char *specbits = SvPV(bitspec, len);
	if (safe_debug >= 2)
	    warn("set_opset_bits opset %s %s\n", opname, (on)?"on":"off");
	if (on) 
	    while(len-- > 0) bitmap[len] |=  specbits[len];
	else
	    while(len-- > 0) bitmap[len] &= ~specbits[len];
    }
    else
	croak("panic: invalid bitspec for \"%s\" (type %d)",
		opname, SvTYPE(bitspec));
}



MODULE = Safe	PACKAGE = Safe

BOOT:
    assert(maxo < OP_MASK_BUF_SIZE);
    opset_len = (maxo / 8) + 1;
    if (safe_debug >= 1)
	warn("opset_len %d\n", opset_len);
    op_names_init();


void
_safe_call_sv(package, mask, codesv)
    char *	package
    SV *	mask
    SV *	codesv
    PPCODE:
    int i,j;
    char *bitmask;
    char op_mask_buf[OP_MASK_BUF_SIZE];
    STRLEN len;
    int myopcode = 0;

    verify_opset(mask,1);
    bitmask = SvPV(mask, len);

    ENTER;
    SAVEPPTR(op_mask);
    op_mask = &op_mask_buf[0];

    save_aptr(&endav);
    endav = (AV*)sv_2mortal((SV*)newAV()); /* Ignore END blocks for now */

    save_hptr(&defstash);
    defstash = gv_stashpv(package, TRUE);
    GvHV(gv_fetchpv("main::", TRUE, SVt_PVHV)) = defstash;

    /* expand bitmask to byte op_mask (worth caching?) */
    for (i=0; i < opset_len; i++) {
	U16 bits = bitmask[i];
	for (j=0; j < 8 && myopcode < maxo; )
	    op_mask[myopcode++] = bits & (1 << j++);
    }

    PUSHMARK(sp);
    i = perl_call_sv(codesv, GIMME|G_EVAL|G_KEEPERR); /* use callers context */
    SPAGAIN; /* for the PUTBACK added by xsubpp */
    LEAVE;


void
verify_opset(opset, fatal = 0)
    SV *opset
    int fatal


void
opset_to_ops(opset, desc = 0)
    SV *opset
    int	desc
    PPCODE:
    {
    STRLEN len;
    int i, j, myopcode;
    char *bitmap = SvPV(opset, len);
    char **names = (desc) ? op_desc : op_name;
    verify_opset(opset,1);
    for (myopcode=0, i=0; i < opset_len; i++) {
	U16 bits = bitmap[i];
	for (j=0; j < 8 && myopcode < maxo; j++, myopcode++) {
	    if ( bits & (1 << j) )
		XPUSHs(sv_2mortal(newSVpv(names[myopcode], 0)));
	}
    }
    }


void
ops_to_opset(...)
    CODE:
    int i, j;
    SV *bitspec, *opset;
    char *bitmap;
    STRLEN len, on;
    opset = new_opset(Nullsv);
    bitmap = SvPVX(opset);
    for (i = 0; i < items; i++) {
	char *opname;
	on = 1;
	if (verify_opset(ST(i),0)) {
	    opname = "(opset)";
	    bitspec = ST(i);
	}
	else {
	    opname = SvPV(ST(i), len);
	    if (*opname == '!') { on=0; ++opname;--len; }
	    bitspec = get_op_bitspec(opname, len, 1);
	}
	set_opset_bits(bitmap, bitspec, on, opname);
    }
    ST(0) = opset;


#define PERMITING  (ix == 0 || ix == 1)
#define ONLY_THESE (ix == 0 || ix == 2)

void
permit_only(safe, ...)
    SV *safe
    ALIAS:
	permit    = 1
	deny_only = 2
	deny      = 3
    CODE:
    int i, on;
    SV *bitspec, *mask;
    char *bitmap, *opname;
    STRLEN len;

    if (!SvROK(safe) || !SvOBJECT(SvRV(safe)) || SvTYPE(SvRV(safe))!=SVt_PVHV)
	croak("Not a Safe object");
    mask = *hv_fetch((HV*)SvRV(safe), "Mask",4, 1);
    if (ONLY_THESE)	/* *_only = new mask, else edit current	*/
	 sv_setsv(mask, new_opset(PERMITING ? opset_all : Nullsv));
    else verify_opset(mask,1); /* croaks */
    bitmap = SvPVX(mask);
    for (i = 1; i < items; i++) {
	on = PERMITING ? 0 : 1;		/* deny = mask bit on	*/
	if (verify_opset(ST(i),0)) {	/* it's a valid mask	*/
	    opname = "(mask)";
	    bitspec = ST(i);
	}
	else {				/* it's an opname/optag	*/
	    opname = SvPV(ST(i), len);
	    /* invert if op has ! prefix (only one allowed)	*/
	    if (*opname == '!') { on = !on; ++opname; --len; }
	    bitspec = get_op_bitspec(opname, len, 1); /* croaks */
	}
	set_opset_bits(bitmap, bitspec, on, opname);
    }
    ST(0) = &sv_yes;



void
opdesc(...)
    PPCODE:
    int i, myopcode;
    STRLEN len;
    SV **args;
    /* copy args to a scratch area since we may push output values onto	*/
    /* the stack faster than we read values off it if masks are used.	*/
    args = (SV**)SvPVX(sv_2mortal(newSVpv((char*)&ST(0), items*sizeof(SV*))));
    for (i = 0; i < items; i++) {
	char *opname = SvPV(args[i], len);
	SV *bitspec = get_op_bitspec(opname, len, 1);
	if (SvIOK(bitspec)) {
	    myopcode = SvIV(bitspec);
	    if (myopcode < 0 || myopcode >= maxo)
		croak("panic: opcode %d (%s) out of range",myopcode,opname);
	    XPUSHs(sv_2mortal(newSVpv(op_desc[myopcode], 0)));
	}
	else if (SvPOK(bitspec) && SvCUR(bitspec) == opset_len) {
	    int b, j;
	    char *bitmap = SvPV(bitspec,na);
	    myopcode = 0;
	    for (b=0; b < opset_len; b++) {
		U16 bits = bitmap[b];
		for (j=0; j < 8 && myopcode < maxo; j++, myopcode++)
		    if (bits & (1 << j))
			XPUSHs(sv_2mortal(newSVpv(op_desc[myopcode], 0)));
	    }
	}
	else
	    croak("panic: invalid bitspec for \"%s\" (type %d)",
		opname, SvTYPE(bitspec));
    }


void
empty_opset()
    CODE:
    ST(0) = sv_2mortal(new_opset(Nullsv));

void
full_opset()
    CODE:
    ST(0) = sv_2mortal(new_opset(opset_all));


void
define_optag(optagsv, mask)
    SV *optagsv
    SV *mask
    CODE:
    STRLEN len;
    char *optag = SvPV(optagsv, len);
    put_op_bitspec(optag, len, mask); /* croaks */
    ST(0) = &sv_yes;


int
MAXO()
    CODE:
    RETVAL = maxo;
    OUTPUT:
    RETVAL

