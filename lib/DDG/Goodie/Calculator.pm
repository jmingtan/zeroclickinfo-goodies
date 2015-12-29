package DDG::Goodie::Calculator::Result;
# Defines the result form used by the Calculator Goodie to
# allow for more detailed and curated results.

BEGIN {
    require Exporter;

    our @ISA    = qw(Exporter);
    our @EXPORT = qw(pure new_tainted
                     taint_result_when taint_result_unless
                     untaint_when);
}

use Math::BigRat try => 'GMP';
use Math::Cephes qw(:explog);
use Math::Cephes qw(:trigs);
use Math::Round;
use Moo;
use Math::Trig qw(deg2rad);

use overload
    '""'    => 'to_string',
    # Basic arithmetic
    '+'     => 'add_results',
    '-'     => 'subtract_results',
    '*'     => 'multiply_results',
    '/'     => 'divide_results',
    '%'     => 'modulo_results',
    '**'    => 'exponent_results',
    # Comparisons
    '<=>'   => 'num_compare_results',
    # Trig
    'atan2' => 'atan2_results',
    # Misc functions
    'exp'   => 'exp_result',
    'log'   => 'log_result',
    'sqrt'  => 'sqrt_result',
    'int'   => 'int_result';

# If an irrational (or ungodly) number was produced, so a fraction
# should not be displayed.
has 'tainted' => (
    is => 'ro',
    isa => sub { die unless $_[0] =~ /^[01]$/ },
    default => 0,
);

# The wrapped value.
has 'value' => (
    is => 'rw',
);

has 'is_degrees' => (
    is => 'rw',
    default => 0,
);

sub taint {
    my $self = shift;
    $self->{'tainted'} = 1;
}

sub untaint {
    my $self = shift;
    $self->{'value'} = to_rat($self->{'value'});
    $self->{'tainted'} = 0;
}

# Creates a new, untainted result.
sub pure {
    my $value = shift;
    return DDG::Goodie::Calculator::Result->new({ value => $value });
}

# Creates a new tainted result.
sub new_tainted {
    my $value = shift;
    return DDG::Goodie::Calculator::Result->new({
            tainted => 1,
            value   => $value,
        });
}

sub wrap_result {
    my $result = shift;
    return $result if ref $result eq 'DDG::Goodie::Calculator::Result';
    return pure($result);
}

# preserve_taintf SUB, COND, FUNC
# Expects SUB to produce a result to be wrapped,
# COND to determine whether FUNC should be run
# when passed the result from SUB as well as its
# arguments, and FUNC to modify the final result.
sub preserve_taintf {
    my ($sub, $taintf_cond, $taintf) = @_;
    return sub {
        my $res = $sub->(@_);
        my $should_taintf = $taintf_cond->($res, @_);
        my $result = wrap_result($res);
        $taintf->($result) if $should_taintf;
        return $result;
    };
}

# Modify the taint of the result if the inner-result returns true
# for the given condition.
sub modify_taint_when {
    my ($taintf, $condition, $sub) = @_;
    preserve_taintf(
        $sub,
        sub { $condition->($_[0]) if defined $_[0] },
        sub { $taintf->($_[0]) });
}

sub taint_result_when { modify_taint_when(\&taint, @_) }

sub taint_result_unless {
    my ($condition, $sub) = @_;
    taint_result_when(sub { not $condition->(@_) }, $sub);
}

sub untaint_when { modify_taint_when(\&untaint, @_) }

sub to_string {
    my $self = shift;
    my $res = $self->value();
    return "$res" if defined $res;
}

# Tell the Calculator that the value is an angle in degrees.
sub make_degrees {
    my $self = shift;
    $self->is_degrees(1);
}

# Combine two Results using the given operation. Preserves appropriate
# attributes.
sub combine_results {
    my ($sub, $swapsub) = @_;
    my $resf = sub {
        my ($self, $other, $swap) = @_;
        my $first_val = $self->value();
        my $second_val = $other->value();
        my $res = $sub->($first_val, $second_val)
            if (defined $first_val && defined $second_val);
        $res = $swapsub->($res)
            if (defined $swapsub && defined $res && $swap);
        return $res;
    };
    my $cond = sub { shift; $_[0]->tainted() || $_[1]->tainted() };
    return preserve_taintf($resf, $cond, \&taint);
}

sub preserving_taint {
    my $sub = shift;
    preserve_taintf($sub, sub { shift; $_[0]->tainted() }, \&taint);
}

sub upon_result {
    my $sub = shift;
    return preserving_taint sub {
        my $self = shift;
        my $value = $self->value();
        my $res = $sub->($value) if defined $value;
        return $res;
    }
}

sub on_result { (upon_result($_[1]))->($_[0]) };

*on_decimal = preserving_taint sub {
    my ($self, $sub) = @_;
    my $res = $sub->($self->as_decimal());
    return $res;
};

*add_results = combine_results(sub { $_[0] + $_[1] });
*subtract_results = combine_results(sub { $_[0] - $_[1] });
*multiply_results = combine_results(sub { $_[0] * $_[1] });
*divide_results = combine_results(sub { $_[0] / $_[1] });
*modulo_results = combine_results(sub { $_[0] % $_[1] });

sub num_compare_results {
    my ($self, $other, $swap) = @_;
    return $other->value() <=> $self->value() if $swap;
    return $self->value()  <=> $other->value();
}

sub from_big {
    my $to_convert = shift;
    return $to_convert->numify() if ref $to_convert eq 'Math::BigRat';
    return $to_convert->bstr() if ref $to_convert eq 'Math::BigFloat';
    return $to_convert->bstr() if ref $to_convert eq 'Math::BigInt';
    return $to_convert;
}

sub to_rat {
    my $num = shift;
    return $num if ref $num eq 'Math::BigRat';
    return Math::BigRat->new($num);
}

# Unwrap the arguments from Big{Float,Rat} for operations such as sine
# and log.
sub with_unwrap {
    my $sub = shift;
    return sub {
        my @args = @_;
        return $sub->(map { from_big($_) } @args);
    };
}

sub wrap_unwrap {
    my $sub = shift;
    return sub {
        return to_rat(with_unwrap($sub)->(@_));
    };
}

# Little bit hacky for exponents because of the way Number::Fraction
# handles them. Basically have to deal with the case when the base and
# exponent are valid fractions, and the exponent is negative - other cases
# are handled fine by Number::Fraction.
sub exponentiate_fraction {
    if ($_[1] < 0) {
        my $res = 1 / $_[0] ** abs($_[1]);
        return $res;
    };
    my $res = wrap_unwrap(sub { $_[0] ** $_[1] })->(@_);
    return $res;
}

*exponent_results = combine_results \&exponentiate_fraction;
*atan2_results = combine_results \&atan2;
*exp_result = upon_result sub { exp $_[0] };
*log_result = upon_result sub { "@{[nearest(1e-15, log $_[0])]}" };
*sqrt_result = upon_result sub { sqrt $_[0] };
*int_result = upon_result sub { int $_[0] };

sub to_radians { $_[0]->is_degrees() ? $_[0]->on_decimal(\&deg2rad) : $_[0] }

sub with_radians {
    my $sub = shift;
    return sub {
        my $self = shift;
        my $rads = $self->to_radians();
        return ($rads->on_result($sub))->rounded(1e-15);
    };
}

*rsin = with_radians(\&sin);
*rcos = with_radians(\&cos);

sub as_fraction_string {
    my $self = shift;
    my $show = "$self";
    my $value = $self->value();
    if ($self->is_fraction()) {
        return "$value";
    }
}

sub is_integer {
    my $self = shift;
    my $tolerance = shift;
    my $value = $self->value();
    return pure($self->rounded($tolerance))->is_integer() if defined $tolerance;
    return $value->is_int() if ref $value eq 'Math::BigRat';
    return $value =~ /^\d+$/;
}

sub is_fraction {
    my $self = shift;
    my $value = $self->value();
    ref $value eq 'Math::BigRat' ? 1 : 0;
}

sub as_rounded_decimal {
    my $self = shift;
    my $decimal = $self->value();
    my ($nom, $expt) = split 'e', $decimal;
    if (defined $expt) {
        my $num = nearest(1e-12, $nom);
        return $num . 'e' . $expt;
    };
    my ($s, $e) = split 'e', sprintf('%0.13e', $decimal);
    return nearest(1e-12, $s) * 10 ** $e;
}

sub as_decimal {
    my $self = shift;
    my $value = $self->value();
    return $value->as_float->bstr() if ref $value eq 'Math::BigRat';
    return $value->bstr() if ref $value eq 'Math::BigFloat';
    return $value;
}

*rounded = preserving_taint sub {
    my ($self, $round_to) = @_;
    return to_rat("@{[nearest($round_to, $self->as_decimal())]}");
};

sub contains_bad_result {
    my $self = shift;
    return 1 unless defined $self->value();
    return 1 if $self->is_fraction() && $self->value->denominator() == 0;
    return $self->value() =~ /(inf|nan)/i;
}




package DDG::Goodie::Calculator::Parser::Grammar;

BEGIN {
    require Exporter;

    our @ISA    = qw(Exporter);
    our @EXPORT = qw(new_sub_grammar);
}

use Moose;
use namespace::autoclean;

has spec => (
    is => 'ro',
    required => 1,
    isa => 'CodeRef',
);
has name => (
    is => 'ro',
    required => 1,
    isa => 'Str',
);
has terms => (
    is => 'rw',
    isa => sub { [] },
);
has bless_counter => (
    is => 'ro',
    default => 0,
    isa => 'Int',
);
has ignore_case => (
    is => 'ro',
    default => 0,
    isa => 'Bool',
);

sub generate_sub_grammar {
    my $self = shift;
    my $str_grammar = $self->{name} . " ::= \n";
    my ($first_term, @terms) = @{$self->terms()};
    my ($first_refer, $first_refer_def) = generate_alternate_forms($first_term);
    my @alternate_forms = ($first_refer_def) if defined $first_refer_def;
    $str_grammar .= generate_grammar_line($self->{spec}->($first_refer), $first_term, 1);
    foreach my $term (@terms) {
        my ($refer, $refer_def) = generate_alternate_forms($term);
        push @alternate_forms, $refer_def if defined $refer_def;
        $str_grammar .= generate_grammar_line($self->{spec}->($refer), $term, 0);
    };
    foreach my $alternate_form (@alternate_forms) {
        $str_grammar .= "\n$alternate_form\n";
    };
    return $str_grammar;
}
sub add_term {
    my ($self, $term) = @_;
    $self->{bless_counter}++;
    $term->{name} //= ($self->name . $self->bless_counter);
    $term->{forms} //= [$term->{rep}];
    $term->{ignore_case} //= $self->ignore_case;
    push @{$self->{terms}}, $term;
}

__PACKAGE__->meta->make_immutable;

sub generate_grammar_line {
    my ($rhs, $term, $is_first) = @_;
    my $result;
    my $blessf = $term->{name};
    $result .= '    ' . ($is_first ? '  ' : '| ');
    $result .= join ' ', @$rhs;
    $result .= " bless => $blessf";
    $result .= ' assoc => ' . $term->{assoc} if defined $term->{assoc};
    return "$result\n";
}

sub generate_alternate_forms {
    my $term = shift;
    my $name = $term->{name};
    my $forms = $term->{forms};
    my ($refer_to, $refer_definition);
    if (ref $forms eq 'ARRAY') {
        $refer_to = "<gen @{[$name =~ s/[^[:alnum:]]/ /gr]} forms>";
        $refer_definition = $refer_to . ' ~ ' . join(' | ',
            map { $term->{ignore_case} ? "'$_':i" : "'$_'" } @$forms);
    } else {
        $refer_to = "'$forms'";
    };
    return ($refer_to, $refer_definition);
}

sub new_sub_grammar { DDG::Goodie::Calculator::Parser::Grammar->new(@_) };


package DDG::Goodie::Calculator::Parser;
# Contains the grammar and parsing actions used by the Calculator Goodie.

BEGIN {
    require Exporter;

    our @ISA    = qw(Exporter);
    our @EXPORT = qw(get_parse_results
                     generate_grammar);
}

use strict;
use utf8;

use Marpa::R2;
use Math::Cephes qw(exp floor ceil);
use Math::Cephes qw(:hypers);
use Math::Cephes qw(asin acos atan);
use DDG::Goodie::Calculator::Result;
use DDG::Goodie::Calculator::Parser::Grammar;
use Moo;

my @grammars;
sub new_branch {
    my $new_grammar = new_sub_grammar @_;
    push @grammars, $new_grammar;
    return $new_grammar;
}
my $unary_function_grammar = new_branch {
    name => "GenUnaryFunction",
    spec => sub { ["($_[0])", 'Argument'] },
};

my $word_constant_grammar = new_branch {
    name        => "WordConstant",
    spec        => sub { ["($_[0])"] },
    ignore_case => 1,
};

my $symbol_constant_grammar = new_branch {
    name        => "SymbolConstant",
    spec        => sub { ["($_[0])"] },
    ignore_case => 1,
};

my $binary_function_grammar = new_branch {
    name => "GenBinaryFunction",
    spec => sub {
        [ "($_[0])", "('(')", 'Expression',
          "(';')", 'Expression', "(')')",
        ] }
};

my $postfix_fmodifier_grammar = new_branch {
    name        => "GenPostFixFactorModifier",
    spec        => sub { [ 'Factor', "($_[0])" ] },
    ignore_case => 1,
};

my $expression_operator_grammar = new_branch {
    name => "GenExprOp",
    spec => sub { ['Expression', "($_[0])", 'Expression'] }
};

my $term_operator_grammar = new_branch {
    name => "GenTermOp",
    spec => sub { ['Term', "($_[0])", 'Term'] }
};

my $factor_term_operator_grammar = new_branch({
    name => "GenFactorTermOp",
    spec => sub { ['Factor', "($_[0])", 'Term'] }
});

sub new_fraction { Math::BigRat->new(@_) };


sub doit {
    my ($name, $sub) = @_;
    my $full_name = 'DDG::Goodie::Calculator::Parser::' . $name . '::doit';
    no strict 'refs';
    *$full_name = *{uc $full_name} = $sub;
}

sub show {
    my ($name, $sub) = @_;
    my $full_name = 'DDG::Goodie::Calculator::Parser::' . $name . '::show';
    no strict 'refs';
    *$full_name = *{uc $full_name} = $sub;
}
sub new_base {
    my $term = shift;
    doit $term->{name}, $term->{doit};
    show $term->{name}, $term->{show};
}

# Usage: binary_doit NAME, SUB
# SUB should take 2 arguments and return the result of the action.
sub binary_doit {
    my ($name, $sub) = @_;
    doit $name, sub {
        my $self = shift;
        my $new_sub = untaint_when(sub { length $_[0]->rounded(1e-15) < 10 }, $sub);
        return $new_sub->($self->[0]->doit(), $self->[1]->doit());
    };
}


sub binary_show {
    my ($name, $sub) = @_;
    show $name, sub {
        my $self = shift;
        return $sub->($self->[0]->show(), $self->[1]->show());
    };
}
sub new_binary {
    my ($name, $doit, $show) = @_;
    binary_doit $name, $doit;
    binary_show $name, $show;
}

sub unary_doit {
    my ($name, $sub) = @_;
    no strict 'refs';
    doit $name, sub {
        my $self = shift;
        my $new_sub = untaint_when sub { $_[0] =~ /^\d+$/ }, $sub;
        return $new_sub->($self->[0]->doit());
    };
}

sub unary_show {
    my ($name, $sub) = @_;
    show $name, sub {
        my $self = shift;
        return $sub->($self->[0]->show());
    };
}
sub new_unary {
    my ($name, $doit, $show) = @_;
    unary_doit $name, $doit;
    unary_show $name, $show;
}

sub new_unary_misc {
    my $term = shift;
    unary_doit $term->{name}, $term->{doit};
    unary_show $term->{name}, $term->{show};
}
new_unary_misc {
    name => 'paren',
    doit => sub { $_[0] },
    show => sub { "($_[0])" },
};
new_unary_misc {
    name => 'primary',
    doit => sub { $_[0] },
    show => sub { $_[0] },
};

# Integers, decimals etc...
sub new_base_value {
    my $term = shift;
    doit $term->{name}, sub { pure(new_fraction($_[0]->[0]->[2])) };
    show $term->{name}, sub { "$_[0]->[0]->[2]" };
}

new_base_value { name => 'integer' };
new_base_value { name => 'decimal' };

new_unary_misc {
    name => 'angle_degrees',
    doit => sub { $_[0]->make_degrees(); return $_[0]; },
    show => sub { "$_[0]°" },
};

new_base {
    name => 'prefix_currency',
    doit => sub { $_[0]->[1]->doit() },
    show => sub {
        my $self = shift;
        # Things like $5.00, &pound.75
        return $self->[0] . sprintf('%0.2f', $self->[1]->show());
    },
};

sub new_postfix_fmodifier {
    my $term = shift;
    $postfix_fmodifier_grammar->add_term($term);
    new_unary_misc {
        name => $term->{name},
        doit => $term->{action},
        show => sub { "$_[0] " . $term->{rep} },
    };
}

new_postfix_fmodifier {
    rep    => 'squared',
    action => taint_when_long(sub { $_[0] * $_[0] }),
};

sub new_binary_misc {
    my $term = shift;
    new_binary $term->{name}, $term->{doit}, $term->{show};
}

new_binary_misc {
    name => 'factored_word_constant',
    doit => sub { $_[0] * $_[1] },
    show => sub { "$_[0] $_[1]" },
};
new_binary_misc {
    name => 'factored_symbol_constant',
    doit => sub { $_[0] * $_[1] },
    show => sub { "$_[0]$_[1]" },
};

sub grammar_term_gen {
    my ($bsub, $grammar_hash, $show_sub_gen) = @_;
    return sub {
        my $term = shift;
        $grammar_hash->add_term($term);
        my $doit = $term->{action};
        my $show = $show_sub_gen->($term->{rep});
        $bsub->($term->{name}, $doit, $show);
    };
}

sub function_gen {
    my $shower = sub { my $rep = shift; return sub { "$rep(@{[join '; ', @_]})" }; };
    return grammar_term_gen(@_, $shower);
}

sub new_unary_function  { function_gen(
    \&new_unary, $unary_function_grammar)->(@_) };

sub new_binary_function { function_gen(
    \&new_binary, $binary_function_grammar)->(@_) };

new_binary_function {
    rep    => 'mod',
    forms  => ['mod'],
    action => sub { $_[0] % $_[1] },
};


# Result should not be displayed as a fraction if result a long decimal.
sub new_unary_bounded {
    my $unary = shift;
    $unary->{action} = untaint_when(
        sub { length $_[0]->rounded(1e-15) < 15 },
        taint_when_long($unary->{action}));
    new_unary_function $unary;
}

new_unary_bounded {
    rep    => 'sin',
    forms  => ['sin', 'sine'],
    action => sub { $_[0]->rsin() },
};
new_unary_bounded {
    rep    => 'cos',
    forms  => ['cos', 'cosine'],
    action => sub { $_[0]->rcos() },
};
new_unary_bounded {
    rep    => 'sec',
    forms  => ['sec', 'secant'],
    action => sub { pure(1) / $_[0]->rcos() },
};
new_unary_bounded {
    rep    => 'csc',
    forms  => ['csc', 'cosec', 'cosecant'],
    action => sub { pure(1) / $_[0]->rsin() },
};
new_unary_bounded {
    rep    => 'cotan',
    forms  => ['cotan', 'cot', 'cotangent'],
    action => sub { $_[0]->rcos() / $_[0]->rsin() },
};
new_unary_bounded {
    rep    => 'tan',
    forms  => ['tan', 'tangent'],
    action => sub { $_[0]->rsin() / $_[0]->rcos() },
};
sub on_result { my $f = shift; return sub { $_[0]->on_result($f) } }

new_unary_bounded {
    forms  => ['arcsin', 'asin'],
    action => on_result(\&asin),
    rep    => 'arcsin',
};
new_unary_bounded {
    forms  => ['arccos', 'acos'],
    rep    => 'arccos',
    action => on_result(\&acos),
};
new_unary_bounded {
    forms  => ['arctan', 'atan'],
    action => on_result(\&atan),
    rep    => 'arctan',
};

new_unary_function {
    rep    => 'floor',
    action => on_result(\&floor),
};
new_unary_function {
    rep    => 'ceil',
    forms  => ['ceil', 'ceiling'],
    action => on_result(\&ceil),
};


# Hyperbolic functions
new_unary_bounded {
    rep    => 'sinh',
    action => on_result(\&sinh),
};
new_unary_bounded {
    rep    => 'cosh',
    action => on_result(\&cosh),
};
new_unary_bounded {
    rep    => 'tanh',
    action => on_result(\&tanh),
};
new_unary_bounded {
    rep    => 'artanh',
    forms  => ['artanh', 'atanh'],
    action => on_result(\&atanh),
};
new_unary_bounded {
    forms  => ['arcosh', 'acosh'],
    rep    => 'arcosh',
    action => on_result(\&acosh),
};
new_unary_bounded {
    forms  => ['arsinh', 'asinh'],
    rep    => 'arsinh',
    action => on_result(\&asinh),
};

# Log functions
new_unary_function {
    forms  => ['ln', 'log'],
    rep    => 'ln',
    action => taint_when_long(sub { log $_[0] }),
};

new_binary_misc {
    name => 'logarithm',
    doit => taint_when_long(sub { (log $_[1]) / (log $_[0]) }),
    show => sub { "log$_[0]($_[1])" },
};

# Misc functions
new_unary_bounded {
    rep    => 'sqrt',
    action => sub { sqrt $_[0] },
};

sub calculate_factorial {
    return if $_[0] > pure(1000); # Much larger than this and I start
                                  # to notice a delay.
    return $_[0]->on_result(sub { $_[0]->bfac() });
}

new_unary_function {
    rep    => 'factorial',
    forms  => ['factorial', 'fact'],
    action => \&calculate_factorial,
};
new_unary_function {
    rep    => 'exp',
    action => taint_result_unless(sub { $_[0] =~ /^\d+$/ }, \&exp ),
};


# OPERATORS

# new_binary_operator NAME, SYMBOL, ROUTINE
sub new_binary_operator {
    my ($name, $operator, $sub) = @_;
    new_binary $name, $sub, sub { "$_[0] $operator $_[1]" };
}
sub binary_operator_gen {
    my $grammar_hash = shift;
    my $shower = sub { my $operator = shift; return sub { "$_[0] $operator $_[1]" } };
    return grammar_term_gen(\&new_binary, $grammar_hash, $shower);
}
sub new_expression_operator { binary_operator_gen($expression_operator_grammar)->(@_) }
sub new_term_operator { binary_operator_gen($term_operator_grammar)->(@_) }
sub new_factor_term_operator { binary_operator_gen($factor_term_operator_grammar)->(@_) }

new_expression_operator {
    rep => '-',
    action => sub { $_[0] - $_[1] },
};
new_expression_operator {
    rep => '+',
    action => sub { $_[0] + $_[1] },
};
new_term_operator {
    rep => '*',
    action => sub { $_[0] * $_[1] },
};
new_term_operator {
    rep => '/',
    forms => ['/', 'divided by'],
    action => sub { $_[0] / $_[1] },
};

sub taint_when_long { taint_result_when(sub { length $_[0] > 10 }, @_) }

new_factor_term_operator {
    rep => '^',
    forms => ['^', 'to the power', 'to the power of'],
    assoc => 'right',
    action => taint_when_long(sub { $_[0] ** $_[1] }),
};

new_binary_misc {
    name => 'exp',
    doit => sub { $_[0] * pure(10) ** $_[1] },
    show => sub { "$_[0]e$_[1]" },
};

new_unary_misc {
    name => 'factorial_operator',
    doit => \&calculate_factorial,
    show => sub { "$_[0]!" },
};

sub new_constant {
    my ($constant, $grammar_ref) = @_;
    $grammar_ref->add_term($constant);
    doit $constant->{name}, sub { $constant->{value} };
    show $constant->{name}, sub { $constant->{rep} };
}

sub new_symbol_constant {
    my $constant = shift;
    new_constant $constant, $symbol_constant_grammar;
}
sub new_word_constant {
    my $constant = shift;
    new_constant $constant, $word_constant_grammar;
}

my $big_pi = Math::BigRat->new()->bpi();
my $big_e =  Math::BigRat->new(1)->bexp();

# If any constants cannot be displayed as a fraction, wrap them with this
sub irrational { new_tainted(@_) };

# Constants go here.
new_symbol_constant {
    forms => 'pi',
    rep => 'π',
    value => irrational($big_pi),
};
new_word_constant {
    rep => 'dozen',
    value => pure(12),
};
new_symbol_constant {
    rep => 'e',
    value => irrational($big_e),
};
new_word_constant {
    rep => 'score',
    value => pure(20),
};

sub generate_grammar {
    my $initial_grammar_text = shift;
    my @generated_grammars = map { $_->generate_sub_grammar() } @grammars;
    my $grammar_text = join "\n", ($initial_grammar_text, @generated_grammars);
    my $grammar = Marpa::R2::Scanless::G->new(
        {   bless_package => 'DDG::Goodie::Calculator::Parser',
            source        => \$grammar_text,
        }
    );
}

sub get_parse {
  my ($recce, $input) = @_;
  eval { $recce->read(\$input) } or return undef;
  return $recce->value();
}


sub get_parse_results {
    my ($grammar, $to_compute) = @_;
    my $recce = Marpa::R2::Scanless::R->new(
        { grammar => $grammar,
        } );
    my $parsed = get_parse($recce, $to_compute) or return;
    my $generated_input = ${$parsed}->show();
    my $val_result = ${$parsed}->doit();
    return unless defined $val_result->value();
    return ($generated_input, $val_result);
}



package DDG::Goodie::Calculator;
# ABSTRACT: perform simple arithmetical calculations

use strict;
use DDG::Goodie;
with 'DDG::GoodieRole::NumberStyler';
use utf8;

use DDG::Goodie::Calculator::Parser;

zci answer_type => "calculation";
zci is_cached   => 1;

my $decimal = qr/(-?\d++[,.]?\d*+)|([,.]\d++)/;
# Check for binary operations
triggers query_nowhitespace => qr/($decimal|\w+)(\W+|x)($decimal|\w+)/;
# Factorial
triggers query_nowhitespace => qr/\d+[!]/;
# Check for functions
triggers query_nowhitespace => qr/\w+\(.*\)/;
# Check for constants and named operations
triggers query_nowhitespace => qr/$decimal\W*\w+/;
# They might want to find out what fraction a decimal represents
triggers query_nowhitespace => qr/[,.]\d+/;

my %phone_number_regexes = (
    'US' => qr/[0-9]{3}(?: |\-)[0-9]{3}\-[0-9]{4}/,
    'UK' => qr/0[0-9]{3}[ -][0-9]{3}[ -][0-9]{4}/,
    'UK2' => qr/0[0-9]{4}[ -][0-9]{3}[ -][0-9]{3}/,
);

my $number_re = number_style_regex();
# Each octet should look like a number between 0 and 255.
my $ip4_octet = qr/([01]?\d\d?|2[0-4]\d|25[0-5])/;
# There should be 4 of them separated by 3 dots.
my $ip4_regex = qr/(?:$ip4_octet\.){3}$ip4_octet/;
# 0-32
my $up_to_32  = qr/([1-2]?[0-9]{1}|3[1-2])/;
# Looks like network notation, either CIDR or subnet mask
my $network   = qr#^$ip4_regex\s*/\s*(?:$up_to_32|$ip4_regex)\s*$#;
sub should_not_trigger {
    my $query = shift;
    # Probably are searching for a phone number, not making a calculation
    for my $phone_regex (%phone_number_regexes) {
        return 1 if $query =~ $phone_regex;
    };
    # Probably attempt to express a hexadecimal number, query_nowhitespace makes this overreach a bit.
    return 1 if ($query =~ /\b0\s*x/);
    # Probably want to talk about addresses, not calculations.
    return 1 if ($query =~ $network);
    return 0;
}

sub get_style {
    my $text = shift;
    my @numbers = grep { $_ =~ /^$number_re$/ } (split /[^\d,.]+/, $text);
    return number_style_for(@numbers);
}

sub get_currency {
    my $text = shift;
    # Add new currency symbols here.
    $text =~ /(?<currency>[\$])$decimal/;
    return $+{'currency'};
}

# For prefix currencies that round to 2 decimal places.
sub format_for_currency {
    my ($text, $currency) = @_;
    return $text unless defined $currency;
    my $result = sprintf('%0.2f', $text->as_decimal());
    return $currency . $result;
}

sub format_currency_for_display {
    my ($style, $text, $currency) = @_;
    return $style->for_display(format_for_currency($text, $currency));
}

sub standardize_symbols {
    my $text = shift;
    # Only replace x's surrounded by non-alpha characters so it
    # can occur in function names.
    $text =~ s/(?<![[:alpha:]])x(?![[:alpha:]])/*/g;
    $text =~ s/[∙⋅×]/*/g;
    $text =~ s#[÷]#/#g;
    $text =~ s/\*{2}/^/g;
    $text =~ s/π/pi/g;
    $text =~ s/°/degrees/g;
    return $text;
}

sub should_display_decimal {
    my ($to_compute, $result) = @_;
    if ($result->is_fraction()) {
        return 1 if not decimal_strings_equal($to_compute, $result->as_decimal());
    } else {
        return 1 if $to_compute ne $result->value();
    }
    return 0;
}

sub should_display_fraction {
    my ($to_compute, $result) = @_;
    if ($result->is_fraction()) {
        my $tainted = $result->tainted();
        return 0 if $result->tainted();
        my $no_whitespace_input = $to_compute =~ s/\s*//gr;
        return $no_whitespace_input ne $result->as_fraction_string;
    }
    return 0;
}

# Check if two strings represent the same decimal number.
sub decimal_strings_equal {
    my ($first, $second) = @_;
    $first =~ s/^\./0\./;
    $second =~ s/^\./0\./;
    return $first eq $second;
}

sub got_rounded {
    my ($original, $to_test) = @_;
    return $original->value() != $to_test;
}

sub format_number_for_display {
    my ($style, $number) = @_;
    return $style->for_display($number);
}

sub format_integer_for_display {
    my ($style, $number) = @_;
    my $result = '';
    if ($number->value->length() > 30) {
        $result .= '≈ ';
        $number = $number->value->as_int->bround(20)->bsstr();
    };
    return $result . $style->for_display($number);
}

sub format_for_display {
    my ($style, $to_compute, $value, $currency) = @_;
    return format_currency_for_display $style, $value, $currency if defined $currency;
    return format_integer_for_display $style, $value if $value->is_integer();
    my $result;
    my $displayed_fraction;
    if (should_display_fraction($to_compute, $value)) {
        $result .= format_number_for_display($style, $value) . ' ';
        $displayed_fraction = 1;
    };
    if (should_display_decimal($to_compute, $value)) {
        my $decimal = $value->as_rounded_decimal();
        if (got_rounded($value, $decimal)) {
            $result .= '≈ ';
        } else {
            $result .= '= ' if $displayed_fraction;
        }
        $result .= format_number_for_display($style, $decimal);
    };
    $result =~ s/\s+$//;
    return $result;
}

sub is_bad_result {
    my $result = shift;
    return 1 unless defined $result;
    return $result->contains_bad_result();
}

my $grammar_text = scalar share('grammar.txt')->slurp();
my $grammar = generate_grammar($grammar_text);
sub to_display {
    my $query = shift;
    my $currency = get_currency $query;
    $query = standardize_symbols $query;
    my $style = get_style $query or return;
    my $to_compute = $query =~ s/((?:[,.\d][\d,. _]*[,.\d]?))/$style->for_computation($1)/ger;
    my ($generated_input, $val_result) = eval { get_parse_results $grammar, $to_compute } or return;
    return if is_bad_result $val_result;
    my $result = format_for_display $style, $to_compute, $val_result, $currency;
    $generated_input =~ s/(\d+(?:\.\d+)?)/$style->for_display($1)/ge;
    # Didn't come up with anything the user didn't already know.
    return if ($generated_input eq $result);
    return ($generated_input, $result);
}



handle query => sub {
    my $query = $_;

    return if should_not_trigger $query;
    $query =~ s/^\s*(?:what\s*is|calculate|solve|math)\s*//;
    my ($generated_input, $result) = to_display $query or return;
    return unless defined $result && defined $generated_input;
    return $result,
        structured_answer => {
            id   => 'calculator',
            name => 'Answer',
            data => {
                title    => "$result",
                subtitle => "Calculate: $generated_input",
            },
            templates => {
              group  => 'text',
              moreAt => '0',
            },
        };
};

1;
