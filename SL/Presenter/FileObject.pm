package SL::Presenter::FileObject;

use strict;

use SL::Presenter::EscapedText qw(escape is_escaped);

use Exporter qw(import);
our @EXPORT_OK = qw(file_object);

use Carp;

sub file_object {
  my ($file_object, %params) = @_;

  my $link_start  = '<a href="controller.pl?action=File/download&id=' . $file_object->id;
  $link_start    .= '&version=' . $file_object->version if $file_object->version;
  $link_start    .= '">';

  my $link_end    = '</a>';

  my $text = join '', (
    $params{no_link} ? '' : $link_start,
    escape($file_object->file_name),
    $params{no_link} ? '' : $link_end,
  );

  is_escaped($text);
}

1;


__END__

=pod

=encoding utf8

=head1 NAME

SL::Presenter::FileObject - Presenter module for SL::File::Object(s), the
file objects of the filemanagement. (Note, that this are not instances of
SL::DB::File)

=head1 SYNOPSIS

  my $file_object = SL::File->get(id => 1);
  my $html        = SL::Presenter::File::file_object($file_object, no_link => 1);

=head1 FUNCTIONS

=over 4

=item C<file_object $file_object, %params>

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of the file object
C<$file_object>.

C<%params> can include:

=over 2

=item * no_link

If falsish (the default) then the file name of the object will be linked
to the "download action" for that file.

=back

=back

=head1 BUGS

Nothing here yet.

=head1 AUTHOR

Bernd Bleßmann E<lt>bernd@kivitendo-premium.deE<gt>

=cut
