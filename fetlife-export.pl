#!/usr/bin/perl -w

use strict;
use WWW::Mechanize;
use Term::ReadKey;
use LWP::Simple qw/getstore/;
use File::Basename;
use File::Path;
use HTML::TreeBuilder;

$|++;

my $mech = new WWW::Mechanize;
my $username = shift or &usage;
my $dir = shift || ".";
print "Password: ";
ReadMode('noecho');
my $password = ReadLine 0;
ReadMode('normal');
chomp $password;
print "\n";

mkpath("$dir/fetlife");

&login($username, $password);
my $id = &getId();
print "userID: $id\n";

&downloadPics();
&downloadWriting();

sub downloadWriting {
  mkdir "$dir/fetlife/posts";

  print "Loading posts: .";
  $mech->get("https://fetlife.com/users/$id/posts");
  my @links = $mech->find_all_links( url_regex => qr{/users/$id/posts/\d+$} );
  while (my $next = $mech->find_link( url_regex => qr{/posts\?page=(\d)}, text_regex => qr/Next/ )) {
    print ".";
    $mech->get($next);
    push @links, $mech->find_all_links( url_regex => qr{/users/$id/posts/\d+$} );
  }

  my $num = @links;
  my $s = &s($num);
  my $i = 1;
  print " $num post$s found.\n";
  return unless $num;
  foreach my $page (@links) {
    print "$i/$num\r";

    &getPost($page);

    $i++;
  }
}

sub getPost {
  my $page = shift;
  my $tree;
  $mech->get($page);
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());
  my $name = basename($page->url());
  open(DATA, "> $dir/fetlife/posts/$name.html") or die "Can't write $name.html: $!";
  print DATA $tree->look_down( id => 'post_content' )->as_HTML(undef, "\t", {}), "\n\n";
  print DATA $tree->look_down( id => 'comments' )->as_HTML(undef, "\t", {}), "\n\n";

  close DATA;
  $tree->delete();
}

sub downloadPics {
  mkdir "$dir/fetlife/pics";

  print "Loading pictures: .";
  $mech->get("https://fetlife.com/users/$id/pictures");
  my @links = $mech->find_all_links( url_regex => qr{/users/$id/pictures/\d+$} );
  while (my $next = $mech->find_link( url_regex => qr{/pictures\?page=(\d)}, text_regex => qr/Next/ )) {
    print ".";
    $mech->get($next);
    push @links, $mech->find_all_links( url_regex => qr{/users/$id/pictures/\d+$} );
  }

  my $num = @links;
  my $s = &s($num);
  my $i = 1;
  print " $num picture$s found.\n";
  return unless $num;
  foreach my $page (@links) {
    print "$i/$num\r";

    &getImage($page);

    $i++;
  }
}

sub getImage {
  my $page = shift;
  my $tree;
  $mech->get($page);
  my $image = $mech->find_image( url_regex => qr{flpics.*_720\.jpg} );
  my $name = basename($image->url());
  return if -f "$dir/fetlife/pics/$name.data";
  getstore($image->url(), "$dir/fetlife/pics/$name");
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());
  open(DATA, "> $dir/fetlife/pics/$name.data") or die "Can't write $name.data: $!";
  print DATA "Caption: ";
  my $caption = $tree->look_down( class => "caption" );
  if ($caption) {
    print DATA $caption->as_HTML;
  } else {
    print DATA "N/A";
  }

  print DATA "\n\nComments:\n";

  my @comments = $tree->look_down( class => 'comment clearfix' );
  pop @comments; # ignore the new comment line
  # print "comments: ", scalar @comments, "\n";
  foreach my $comment (@comments) {
    # print "-----\n", $comment->dump();
    print DATA $comment->look_down( class => 'nickname' )->as_HTML();
    print DATA " - ", $comment->look_down( class => "time_ago" )->attr('datetime'), "\n";
    print DATA $comment->look_down( class => qr/content/ )->as_HTML();
    print DATA "\n\n";
  }

  close DATA;
  $tree->delete();
}

sub getId {
  my $link = $mech->find_link( text_regex => qr/View Your Profile/i );
  die "Failed to find profile link!" unless $link;
  if ($link->url() =~ m{/(\d+)$}) {
    return $1;
  } else {
    die "Failed to get user ID out of profile link: " . $link->url();
  }
}

sub login {
  my ($username, $password) = @_;

  $mech->get( "https://fetlife.com/login" );
  $mech->form_with_fields( qw/nickname_or_email password/ );
  $mech->field( 'nickname_or_email' => $username );
  $mech->field( 'password' => $password );
  my $res = $mech->submit();
  die "Login failed!" unless $res->is_success;
}

sub usage {
  print "$0 <username> [<directory>]\n";
  exit 1;
}

sub s {
  my $num = shift;
  return $num == 1 ? "" : "s";
}
