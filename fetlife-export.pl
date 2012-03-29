#!/usr/bin/perl -w

use strict;
use WWW::Mechanize;
use Term::ReadKey;
use LWP::Simple qw/getstore/;
use File::Basename;
use File::Path;
use HTML::TreeBuilder;
use String::Escape;
use Unicode::Escape;

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

&login($username, $password);
my $id = &getId();
print "userID: $id\n";

mkpath("$dir/fetlife");

&downloadProfile();
&collectLinksInActivityFeed();
&downloadConversations();
&downloadWriting();

sub downloadProfile {
  print "Loading profile: .", "\n";
  $mech->get("https://fetlife.com/users/$id");
  my $tree;
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());

  open(DATA, "> $dir/fetlife/$id.html") or die "Can't write $id.html: $!";
  print DATA $tree->look_down( id => 'profile' )->as_HTML(undef, "\t", {}), "\n\n";

  close DATA;
  $tree->delete();
}

sub downloadConversations {
  mkdir "$dir/fetlife/conversations";

  print "Loading conversations: .";
  $mech->get("https://fetlife.com/conversations/all");
  my @links = $mech->find_all_links( url_regex => qr{/conversations/\d+} );
  while (my $next = $mech->find_link( url_regex => qr{/conversations/all\?page=(\d)}, text_regex => qr/Next/ )) {
      print ".";
      $mech->get($next);
      push @links, $mech->find_all_links( url_regex => qr{/conversations/\d+} );
  }

  my $num = @links;
  my $s = &s($num);
  my $i = 1;
  print " $num conversation$s found.\n";
  return unless $num;
  foreach my $page (@links) {
    print "$i/$num\r";

    &getMessages($page);

    $i++;
  }
}

sub getMessages {
  my $page = shift;
  my $tree;
  $mech->get($page);
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());
  my $x = basename($page->url());
  my @y = split(/#/, $x);
  my $name = $y[0];

  open(DATA, "> $dir/fetlife/conversations/$name.html") or die "Can't write $name.html";
  print DATA $tree->look_down( id => 'messages' )->as_HTML(undef, "\t", {}), "\n\n";

  close DATA;
  $tree->delete();
}

# Traverses a user's activity feed, collecting links to download.
# TODO: Refactor this so the `downloadStatuses()` and `downloadGroupPosts()` functions
#       aren't actually nested here.
sub collectLinksInActivityFeed {
  print "Loading activity feed: .";

  $mech->get("https://fetlife.com/users/$id/activity");

  # Only links to one's own statuses are FQURIs, so use absolute (server-relative) URI.
  my @statuses    = $mech->find_all_links( url_regex => qr{/users/\d+/statuses/\d+$} );
  my @pictures    = $mech->find_all_links( url_regex => qr{https?://fetlife.com/users/\d+/pictures/\d+$} );
  my @group_posts = $mech->find_all_links( url_regex => qr{https?://fetlife.com/groups/\d+/group_posts/\d+$} );

  while (my $next = $mech->find_link( url_regex => qr{/users/$id/activity/more\?page}, text_regex => qr/view more/ )) {
    print ".";
    $mech->get($next);

    #### FetLife returns straight-up jQuery, so clean this out before parsing.
    #### TODO: Can we refactor this? It feels kludgy.
    # Split into lines.
    my @x = split("\n", $mech->content);

    # If this is the end of the feed, we'll only get 2 lines back with which we can do nothing.
    # Otherwise, we'll get three lines.
    if (3 == scalar(grep $_, @x)) {
      # Ignore the first line.

      # Clean the second line.
      ## Extract the JavaScript and Unicode-encoded text from the jQuery commands.
      ### Cut out the first 24 characters, which are always: `$("#mini_feed").append("`
      my $x1 = substr($x[1], 24);
      ### Cut out the last 3 characters, which are always: `");`
      $x1 = substr($x1, 0, -3);
      $x1 = Unicode::Escape::unescape($x1, 'UTF-8');
      $x1 = String::Escape::unbackslash($x1);

      my $x2 = substr($x[2], 23);
      $x2 = substr($x2, 0, -3);
      $x2 = String::Escape::unbackslash($x2);

      # Concatenate the cleaned-up lines together.
      my $html = Encode::decode_utf8($x1 . $x2);
      $mech->update_html($html);
    }

    push @statuses, $mech->find_all_links( url_regex => qr{/users/\d+/statuses/\d+$} );
    push @pictures, $mech->find_all_links( url_regex => qr{https?://fetlife.com/users/\d+/pictures/\d+$} );
    push @group_posts, $mech->find_all_links( url_regex => qr{https?://fetlife.com/groups/\d+/group_posts/\d+$} );
  }

  # TODO: Filter out duplicate links from these arrays; we don't need to hit them twice.

  # Count how many statuses were found.
  my $snum = @statuses;
  my $s = &s($snum, 1);
  print " $snum status$s found.\n";

  # Count how many group threads were found.
  my $pnum = @pictures;
  $s = &s($pnum);
  print " $pnum picture$s found.\n";

  # Count how many group threads were found.
  my $gnum = @group_posts;
  $s = &s($gnum);
  print " $gnum group thread$s found.\n";

  # If we found statuses, group threads, or pictures, go download them.
  if ($snum) {
    downloadStatuses($snum, @statuses);
  }

  if ($pnum) {
    downloadPics($pnum, @pictures);
  }

  if ($gnum) {
    downloadGroupPosts($gnum, @group_posts);
  }
}

sub downloadStatuses ($$) {
  mkdir "$dir/fetlife/statuses";

  my $num = shift;
  my @links = @_;

  print "Downloading $num statuses...\n";

  my $i = 1;
  foreach my $page (@links) {
    print "$i/$num\r";

    &getStatus($page);

    $i++;
  }
}

sub getStatus {
  my $page = shift;
  my $tree;
  $mech->get($page);
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());
  my $name = basename($page->url());

  #### TODO: Strip out all the nonsense HTML we don't want. This includes:
  #            * The 'style="display:none;"' in comments on statuses.
  #            * The new comment list item.

  open(DATA, "> $dir/fetlife/statuses/$name.html") or die "Can't write $name.html";
  print DATA $tree->look_down( id => "status_$name" )->as_HTML(undef, "\t", {}), "\n\n";

  close DATA;
  $tree->delete();
}

sub downloadGroupPosts ($$) {
  mkdir "$dir/fetlife/group_posts";

  my $num = shift;
  my @links = @_;

  print "Downloading $num group posts...\n";

  my $i = 1;
  foreach my $page (@links) {
    print "$i/$num\r";

    # TODO: This only grabs the first page--a "post"--but should grab the whole thread.
    &getGroupPost($page);

    $i++;
  }
}

sub getGroupPost {
  my $page = shift;
  my $tree;
  $mech->get($page);
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());
  my $name = basename($page->url());

  # TODO: If this thread has more than one page of comments, we should grab those, too.

  open(DATA, "> $dir/fetlife/group_posts/$name.html") or die "Can't write $name.html";
  print DATA $tree->look_down( class => qr{group_post} )->as_HTML(undef, "\t", {}), "\n\n";
  print DATA $tree->look_down( id => 'comments' )->as_HTML(undef, "\t", {}), "\n\n";

  close DATA;
  $tree->delete();
}

sub downloadWriting {
  mkdir "$dir/fetlife/posts";

  print "Loading posts: .";
  $mech->get("https://fetlife.com/users/$id/posts");
  # Use FQURI in `find_all_links()` to avoid duplicate destinations in @links.
  my @links = $mech->find_all_links( url_regex => qr{https://fetlife.com/users/$id/posts/\d+$} );
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

sub downloadPics ($$) {
  mkdir "$dir/fetlife/pictures";

  my $num = shift;
  my @links = @_;

  print "Downloading $num pictures...\n";

  my $i = 1;
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
  # Don't download images we've already grabbed.
  # TODO: Extend this so we don't download pages/threads we've already grabbed, either.
  unless ( -f "$dir/fetlife/pictures/$name" ) {
    getstore($image->url(), "$dir/fetlife/pictures/$name");
  }
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());
  open(DATA, "> $dir/fetlife/pictures/$name.html") or die "Can't write $name.html: $!";
  my $picture = $tree->look_down( id => "picture" );
  my $pic_img = $picture->find_by_tag_name( 'img' );
  $pic_img    = \$pic_img->attr( 'src', $name );

  print DATA $picture->as_HTML(undef, "\t", {}), "\n\n";
  print DATA $tree->look_down( id => "comments" )->as_HTML(undef, "\t", {}), "\n\n";

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
  my $alt = shift;
  unless ($alt) { return $num == 1 ? "" : "s"; }
  else { return $num == 1 ? "" : "es"; }
}
