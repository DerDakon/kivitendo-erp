package SL::Controller::TopQuickSearch::GLTransaction;

use strict;
use parent qw(Rose::Object);

use SL::DB::GLTransaction;
use SL::DB::Invoice;
use SL::DB::PurchaseInvoice;
use SL::DB::AccTransaction;
use SL::Locale::String qw(t8);
use List::Util qw(sum);

sub auth { 'general_ledger' }

sub name { 'gl_transaction' }

sub description_config { t8('GL search') }

sub description_field { t8('GL search') }

sub query_autocomplete {
  my ($self, %params) = @_;

  my $limit = $::form->{limit} || 40; # max number of results per type (AR/AP/GL)
  my $term  = $::form->{term}  || '';

  my $descriptionquery = { ilike => '%' . $term . '%' };
  my $referencequery   = { ilike => '%' . $term . '%' };
  my $apinvnumberquery = { ilike => '%' . $term . '%' };
  my $namequery        = { ilike => '%' . $term . '%' };
  my $arinvnumberquery = { ilike => '%' . $term       };
  # ar match is more restrictive. Left fuzzy beginning so it also matches "Storno zu $INVNUMBER"
  # and numbers like 000123 if you only enter 123.
  # When used in quicksearch short numbers like 1 or 11 won't match because of the
  # ajax autocomplete minlimit of 3 characters

  my (@glfilter, @arfilter, @apfilter);

  push( @glfilter, (or => [ description => $descriptionquery, reference => $referencequery ] ) );
  push( @arfilter, (or => [ invnumber   => $arinvnumberquery, name      => $namequery ] ) );
  push( @apfilter, (or => [ invnumber   => $apinvnumberquery, name      => $namequery ] ) );

  my $gls = SL::DB::Manager::GLTransaction->get_all(  query => [ @glfilter ], limit => $limit, sort_by => 'transdate DESC');
  my $ars = SL::DB::Manager::Invoice->get_all(        query => [ @arfilter ], limit => $limit, sort_by => 'transdate DESC', with_objects => [ 'customer' ]);
  my $aps = SL::DB::Manager::PurchaseInvoice->get_all(query => [ @apfilter ], limit => $limit, sort_by => 'transdate DESC', with_objects => [ 'vendor' ]);

  # use the sum of all credit amounts as the "amount" of the gl transaction
  foreach my $gl ( @$gls ) {
    $gl->{'amount'} = sum map { $_->amount if $_->amount > 0 } @{$gl->transactions};
  };

  my $gldata = [
    map(
      {
        {
           transdate => DateTime->from_object(object => $_->transdate)->ymd(),
           label     => $_->abbreviation. ": " . $_->description . " " . $_->reference . " " . $::form->format_amount(\%::myconfig, $_->{'amount'},2). " (" . $_->transdate->to_lxoffice . ")" ,
           id        => 'gl.pl?action=edit&id=' . $_->id,
        }
      }
      @{$gls}
    ),
  ];

  my $ardata = [
    map(
      {
        {
           transdate => DateTime->from_object(object => $_->transdate)->ymd(),
           label     => $_->abbreviation . ": " . $_->invnumber . "   " . $_->customer->name . " " . $::form->format_amount(\%::myconfig, $_->amount,2)  . " (" . $_->transdate->to_lxoffice . ")" ,
           id        => ($_->invoice ? "is" : "ar" ) . '.pl?action=edit&id=' . $_->id,
        }
      }
      @{$ars}
    ),
  ];

  my $apdata = [
    map(
      {
        {
           transdate => DateTime->from_object(object => $_->transdate)->ymd(),
           label     => $_->abbreviation . ": " . $_->invnumber . " " . $_->vendor->name . " " . $::form->format_amount(\%::myconfig, $_->amount,2)  . " (" . $_->transdate->to_lxoffice . ")" ,
           value     => "",
           id        => ($_->invoice ? "ir" : "ap" ) . '.pl?action=edit&id=' . $_->id,
        }
      }
      @{$aps}
    ),
  ];

  my $data;
  push(@{$data},@{$gldata});
  push(@{$data},@{$ardata});
  push(@{$data},@{$apdata});

  @$data = reverse sort { $a->{'transdate'} cmp $b->{'transdate'} } @$data;

  $data;
}

sub select_autocomplete {
  $::form->{id}
}

sub do_search {
  my ($self) = @_;

  my $results = $self->query_autocomplete;

  return @$results == 1
    ? $results->[0]{id}
    : undef;
}

# TODO: result overview page

1;
