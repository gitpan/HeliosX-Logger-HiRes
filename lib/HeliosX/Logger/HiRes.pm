package HeliosX::Logger::HiRes;

use 5.008;
use base qw(HeliosX::Logger);
use strict;
use warnings;

use Error qw(:try);
use Data::ObjectDriver;
use Time::HiRes qw(time);

use Helios::Error;
use Helios::LogEntry;
use HeliosX::Logger::LoggingError;

our $VERSION = '0.01_0821';

our $DOD_RETRY_LIMIT = 5;
our $DOD_RETRY_INTERVAL = 5;

=head1 NAME

HeliosX::Logger::HiRes - HeliosX::Logger subclass providing high resolution logging for Helios

=head1 SYNOPSIS

 #in your service class
 package MyService;
 use base qw(HeliosX::ExtLoggerService);
 
 # in helios.ini, disable internal logging 
 # and enable HeliosX::Logger::HiRes
 internal_logger=off
 loggers=HeliosX::Logger::HiRes

=head1 DESCRIPTION

Unlike some other HeliosX::Logger subclasses, HeliosX::Logger::HiRes intends 
not to link Helios with external logging systems, but to enhance Helios's own 
internal logging system by providing much more precise timestamping of log 
messages via the Time::HiRes module.  

The Helios base system's logging subsystem only has resolution to a second, 
which keeps it consistent with the underlying TheSchwartz queueing system.  
But if your collective runs many short-lived (sub-second runtime) jobs, the 
ordering of log messages can easily get confused, with some log entries 
appearing after other messages that clearly came before.  In order prevent 
this, HeliosX::Logger::HiRes uses the Perl Time::HiRes module to capture a 
much more precise measure of an entry's log time, and stores that time in a 
slightly modified Helios database schema that can handle the subsecond 
precision of the new time. 

=head1 HELIOS DATABASE SCHEMA CHANGES

In order to handle the more precise timing information, HeliosX::Logger::HiRes 
requires minor changes to the Helios database schema.  These changes will not 
alter the functionality of Helios::Panoptes or other utilities or Helios 
services not utilizing HeliosX::Logger::HiRes.  To alter the database schema, 
connect to your MySQL Helios database and execute the commands in the 
sql/helios_hires.sql file.  This will only affect the HELIOS_LOG_TB.  Job 
history (HELIOS_JOB_HISTORY_TB) and service uptime monitoring 
(HELIOS_WORKER_REGISTRY_TB) will be unaffected.

=head1 IMPLEMENTED METHODS

=head2 init()

...is empty.

=cut

sub init { }


=head2 logMsg($job, $level, $msg)

This method effectively does the same thing as the original Helios logging 
code, but makes sure the log times recorded are subsecond times.

=cut

sub logMsg {
	my ($self, $job, $level, $msg) = @_;
	my $config = $self->getConfig();
	my $jobid;
	my $funcid;
	my $retryCount = 0;
	if ( defined($job) ) {
		$jobid = $job->getJobid;
		$funcid = $job->getFuncid;
	}
	RETRY:{
		try {
			my $d = $self->getDriver();
			my $entry = Helios::LogEntry->new(
                log_time   => sprintf("%.6f", time()),
                host       => $self->getHostname,
                process_id => $$,
                jobid      => $jobid,
                funcid     => $funcid,
                job_class  => $self->getJobType,
                priority   => $level,
                message    => $msg			
            );
            $d->insert($entry);
		} otherwise {
			if ($retryCount > $DOD_RETRY_LIMIT ) { 
				throw HeliosX::Logger::LoggingError( $_[0]->text() );
			}
			sleep $DOD_RETRY_INTERVAL;
			$retryCount++;
			next RETRY;
		};
	}
	return 1;
}


=head1 OTHER METHODS

=head2 getDriver()

Returns a Data::ObjectDriver object that can be used to write to the 
HELIOS_LOG_TB in the Helios database.

=cut

sub getDriver {
	my $config = $_[0]->getConfig();
	return Data::ObjectDriver::Driver::DBI->new(
	   dsn => $config->{dsn},
	   username => $config->{user},
	   password => $config->{password}
	);
}



1;
__END__


=head1 SEE ALSO

L<HeliosX::ExtLoggerService>, L<HeliosX::Logger>, L<Time::HiRes>

=head1 AUTHOR

Andrew Johnson, E<lt>lajandy at cpan dotorgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Andrew Johnson

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
