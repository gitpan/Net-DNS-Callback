use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'Net::DNS::Callback',
    'VERSION_FROM'	=> 'lib/Net/DNS/Callback.pm',
    'PREREQ_PM'		=> {
				'Test::More'	=> 0,
				'Net::DNS'		=> 0,
			},
	ABSTRACT_FROM => 'lib/Net/DNS/Callback.pm',
	AUTHOR     => 'Shevek <cpan@anarres.org>',
);

sub MY::postamble {
	my $self = shift;
	my $old = $self->MM::postamble(@_);
	chomp($old);
	my $new = <<'EON';

.PHONY : aux readme

aux : readme

readme : lib/Net/DNS/Callback.pm
	perldoc -t lib/Net/DNS/Callback.pm > README

EON
	return $old . $new;
}
