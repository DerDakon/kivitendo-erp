package SL::BackgroundJob::ConvertTimeRecordings;

use strict;

use parent qw(SL::BackgroundJob::Base);

use SL::DB::DeliveryOrder;
use SL::DB::TimeRecording;

use SL::Locale::String qw(t8);

use DateTime;
use Try::Tiny;

sub create_job {
  $_[0]->create_standard_job('7 3 1 * *'); # every first day of month at 03:07
}


#
# If job does not throw an error,
# success in background_job_histories is 'success'.
# It is 'failure' otherwise.
#
# Return value goes to result in background_job_histories.
#
sub run {
  my ($self, $db_obj) = @_;

  my $data;
  $data = $db_obj->data_as_hash if $db_obj;

  $self->{$_} = [] for qw(job_errors);
  # from/to date from data. Defaults to begining and end of last month.
  my $from_date;
  my $to_date;
  # handle errors with a catch handler
  try {
    $from_date   = DateTime->from_kivitendo($data->{from_date}) if $data->{from_date};
    $to_date     = DateTime->from_kivitendo($data->{to_date})   if $data->{to_date};
  } catch {
    die "Cannot convert date from string $data->{from_date} $data->{to_date}\n Details :\n $_"; # not $@
  };
  $from_date ||= DateTime->new( day => 1,    month => DateTime->today_local->month, year => DateTime->today_local->year)->subtract(months => 1);
  $to_date   ||= DateTime->last_day_of_month(month => DateTime->today_local->month, year => DateTime->today_local->year)->subtract(months => 1);

  $to_date->add(days => 1); # to get all from the to_date, because of the time part (15.12.2020 23.59 > 15.12.2020)

  my %customer_where;
  %customer_where = ('customer.customernumber' => $data->{customernumbers}) if 'ARRAY' eq ref $data->{customernumbers};

  my $time_recordings = SL::DB::Manager::TimeRecording->get_all(where        => [end_time => { ge_lt => [ $from_date, $to_date ]},
                                                                                 or => [booked => 0, booked => undef],
                                                                                 %customer_where],
                                                                with_objects => ['customer']);
  my %time_recordings_by_customer_id;
  push @{ $time_recordings_by_customer_id{$_->customer_id} }, $_ for @$time_recordings;

  my @donumbers;
  foreach my $customer_id (keys %time_recordings_by_customer_id) {
    my $do;
    if (!eval {
      $do = SL::DB::DeliveryOrder->new_from_time_recordings($time_recordings_by_customer_id{$customer_id});
      1;
    }) {
      $::lxdebug->message(LXDebug->WARN(),
                          "ConvertTimeRecordings: creating delivery order failed ($@) for time recording ids " . join ', ', map { $_->id } @{$time_recordings_by_customer_id{$customer_id}});
      push @{ $self->{job_errors} }, "ConvertTimeRecordings: creating delivery order failed ($@) for time recording ids " . join ', ', map { $_->id } @{$time_recordings_by_customer_id{$customer_id}};

    }

    if ($do) {
      if (!SL::DB->client->with_transaction(sub {
        $do->save;
        $_->update_attributes(booked => 1) for @{$time_recordings_by_customer_id{$customer_id}};
        1;
      })) {
        $::lxdebug->message(LXDebug->WARN(),
                            "ConvertTimeRecordings: saving delivery order failed for time recording ids " . join ', ', map { $_->id } @{$time_recordings_by_customer_id{$customer_id}});
        push @{ $self->{job_errors} }, "ConvertTimeRecordings: saving delivery order failed for time recording ids " . join ', ', map { $_->id } @{$time_recordings_by_customer_id{$customer_id}};
      } else {
        push @donumbers, $do->donumber;
      }
    }
  }

  my $msg  = t8('Number of delivery orders created:');
  $msg    .= ' ';
  $msg    .= scalar @donumbers;
  $msg    .= ' (';
  $msg    .= join ', ', @donumbers;
  $msg    .= ').';
  # die if errors exists
  if (@{ $self->{job_errors} }) {
    $msg  .= ' ' . t8('The following errors occurred:');
    $msg  .= join "\n", @{ $self->{job_errors} };
    die $msg;
  }
  return $msg;
}

1;

# possible data
# from_date: 01.12.2020
# to_date: 15.12.2020
# customernumbers: [1,2,3]
__END__

=pod

=encoding utf8

=head1 NAME

SL::BackgroundJob::ConvertTimeRecordings - Convert time recording
entries into delivery orders

=head1 SYNOPSIS

Get all time recording entries for the given period and customer numbers
and create delivery ordes out of that (using
C<SL::DB::DeliveryOrder-E<gt>new_from_time_recordings>).

=head1 CONFIGURATION

Some data can be provided to configure this backgroung job.
If there is user data and it cannot be validated the background job
returns a error messages.

=over 4

=item C<from_date>

The date from which on time recordings should be collected. It defaults
to the first day of the previous month.

Example (format depends on your settings):

from_date: 01.12.2020

=item C<to_date>

The date till which time recordings should be collected. It defaults
to the last day of the previous month.

Example (format depends on your settings):

to_date: 15.12.2020

=item C<customernumbers>

An array with the customer numbers for which time recordings should
be collected. If not given, time recordings for customers are
collected. This is the default.

Example (format depends on your settings):

customernumbers: [c1,22332,334343]

=item C<part_id>

The part id of a time based service which should be used to
book the times. If not set the clients config defaults is used.

=item C<rounding>

If set the 0 no rounding of the times will be done otherwise
the times will be rounded up to th full quarters of an hour,
ie. 0.25h 0.5h 0.75h 1.25h ...
Defaults to rounding true (1).

=item C<link_project>

If set the job tries to find a previous Order with the current
customer and project number and tries to do as much automatic
workflow processing as the UI.
Defaults to off. If set to true (1) the job will fail if there
is no Sales Orders which qualifies as a predecessor.
Conditions for a predeccesor:

 * Global project_id must match time_recording.project_id OR data.project_id
 * Customer name must match time_recording.customer_id OR data.customernumbers
 * The sales order must have at least one or more time related services
 * The Project needs to be valid and active

The job doesn't care if the Sales Order is already delivered or closed.
If the sales order is overdelivered some organisational stuff needs to be done.
The sales order may also already be closed, ie the amount is fully billed, but
the services are not yet fully delivered (simple case: 'Payment in advance').

Hint: take a look or extend the job CloseProjectsBelongingToClosedSalesOrder for
further automatisation of your organisational needs.


=item C<project_id>

Use this project_id instead of the project_id in the time recordings.

=back

=head1 AUTHOR

Bernd Bleßmann E<lt>bernd@kivitendo-premium.deE<gt>

=cut